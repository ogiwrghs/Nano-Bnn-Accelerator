#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <math.h>

#include "npu_weights.h"
#include "npu_images.h"
#include "npu_thresholds.h"
#include "npu_output.h"

// Base address of the Lightweight HPS-to-FPGA bridge
#define HW_REGS_BASE 0xFF200000
#define HW_REGS_SPAN 4096

// Offsets from Qsys
#define PIO_RESET_N_OFFSET 0x00
#define PIO_UIO_OUT_OFFSET 0x10
#define PIO_UO_OUT_OFFSET  0x20
#define PIO_UIO_IN_OFFSET  0x30
#define PIO_UI_IN_OFFSET   0x40

// The ultimate safe write. Uses 8-bit pointers and stalls the ARM 
// long enough for the 50MHz FPGA to register the signal 
void npu_write(volatile uint8_t *reg, uint8_t val) {
    *reg = val;
    for(volatile int d = 0; d < 1000; d++); 
}

int read_acc10(int addr, volatile uint8_t *uio_in, volatile uint8_t *uo_out, volatile uint8_t *uio_out) {
    npu_write(uio_in, (addr << 1)); 
    uint8_t low_8 = *uo_out;
    uint8_t high_2 = (*uio_out >> 6) & 0x03;
    return (high_2 << 8) | low_8;
}

void do_inference(const uint8_t* img, const char* name, volatile uint8_t* rst_n, volatile uint8_t* uio_in, volatile uint8_t* ui_in, volatile uint8_t* uo_out, volatile uint8_t* uio_out) {
    printf("\n--- NPU Inference for %s ---\n", name);
    uint8_t l1_acts[64] = {0};

    int l1_log_acc[16];
    int l2_log_acc[16];
    float l2_log_bn[16];


    // LAYER 1: 512 Neurons
    for (int pass = 0; pass < 64; pass++) {
        npu_write(rst_n, 0); 
        npu_write(rst_n, 1);

        for (int b = 0; b < 98; b++) {
            
            // 1. Load Weights for the 8 active neurons
            for (int n = 0; n < 8; n++) {
                npu_write(ui_in, npu_weights[(pass * 8 + n) * 98 + b]); 
                npu_write(uio_in, 0x01 | (n << 1));                     
                npu_write(uio_in, 0x00);                                
            }

            // 2. Broadcast image byte and pulse compute!
            npu_write(ui_in, img[b]);   
            npu_write(uio_in, 0x10);    
            npu_write(uio_in, 0x00);    
        }

        // Read accumulators
        for (int n = 0; n < 8; n++) {
            int acc = read_acc10(n, uio_in, uo_out, uio_out);
            int global_n = pass * 8 + n;
            
            if (global_n < 16) l1_log_acc[global_n] = acc; 

            int act = 0;
            if (L1_SIGN[global_n] == 0) {
                if (acc > L1_THRESH[global_n]) act = 1;
            } else {
                if (acc < L1_THRESH[global_n]) act = 1;
            }
            if (act) l1_acts[global_n / 8] |= (1 << (7 - (global_n % 8)));
        }
    }


    // LAYER 2: 256 Neurons
    float l2_bn_out[256];
    int w_offset = 512 * 98;
    
    for (int pass = 0; pass < 32; pass++) {
        npu_write(rst_n, 0); 
        npu_write(rst_n, 1);

        for (int b = 0; b < 64; b++) {
            
            for (int n = 0; n < 8; n++) {
                npu_write(ui_in, npu_weights[w_offset + (pass * 8 + n) * 64 + b]);
                npu_write(uio_in, 0x01 | (n << 1));
                npu_write(uio_in, 0x00);
            }

            npu_write(ui_in, l1_acts[b]);
            npu_write(uio_in, 0x10); 
            npu_write(uio_in, 0x00); 
        }

        for (int n = 0; n < 8; n++) {
            int acc = read_acc10(n, uio_in, uo_out, uio_out);
            int global_n = pass * 8 + n;
            
            // Popcount to Keras Dot Product
            float dot_product = (2.0f * (float)acc) - 512.0f;
            float norm = (dot_product - L2_MEAN[global_n]) / sqrt(L2_VAR[global_n] + L2_EPS);
            float bn_val = (L2_GAMMA[global_n] * norm) + L2_BETA[global_n];
            
            l2_bn_out[global_n] = bn_val;

            if (global_n < 16) {
                l2_log_acc[global_n] = acc;
                l2_log_bn[global_n] = bn_val;
            }
        }
    }

    // DENSE LAYER (25 Classes)
    
    float scores[25];
    float max_score = -999999.0;
    int max_class = -1;
    for (int c = 0; c < 25; c++) {
        scores[c] = OUT_B[c];
        for (int n = 0; n < 256; n++) {
            scores[c] += l2_bn_out[n] * OUT_W[n][c];
        }
        if (scores[c] > max_score) {
            max_score = scores[c];
            max_class = c;
        }
    }

    // --- LOGGING ---
    printf("L1 First 16 Accumulators:\n");
    for(int i=0; i<16; i++) {
        printf("  Neuron %02d: Acc=%3d (Thresh=%3d, Sign=%d)\n", i, l1_log_acc[i], L1_THRESH[i], L1_SIGN[i]);
    }
    
    printf("\nL2 First 16 Accumulators & BN Outputs:\n");
    for(int i=0; i<16; i++) {
        printf("  Neuron %02d: Acc=%3d -> BN=%.4f\n", i, l2_log_acc[i], l2_log_bn[i]);
    }

    char letter = max_class + 'A';
    if (max_class >= 9) letter++;
    printf("\n>> FINAL VERDICT: Class %d (Letter %c) <<\n", max_class, letter);
}

int main() {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        printf("ERROR: Could not open /dev/mem\n");
        return 1;
    }
    
    uint8_t *base = (uint8_t *)mmap(NULL, HW_REGS_SPAN, PROT_READ|PROT_WRITE, MAP_SHARED, fd, HW_REGS_BASE);
    if (base == MAP_FAILED) {
        printf("ERROR: mmap failed!\n");
        close(fd);
        return 1;
    }

    // EXTREMELY IMPORTANT: Reverted to 8-bit pointers to ensure Avalon bus compatibility
    volatile uint8_t *rst_n   = (volatile uint8_t *)(base + PIO_RESET_N_OFFSET);
    volatile uint8_t *uio_out = (volatile uint8_t *)(base + PIO_UIO_OUT_OFFSET);
    volatile uint8_t *uo_out  = (volatile uint8_t *)(base + PIO_UO_OUT_OFFSET);
    volatile uint8_t *uio_in  = (volatile uint8_t *)(base + PIO_UIO_IN_OFFSET);
    volatile uint8_t *ui_in   = (volatile uint8_t *)(base + PIO_UI_IN_OFFSET);

    printf("Pinging NPU Reset Pin...\n");
    npu_write(rst_n, 1);
    printf("NPU is ALIVE and out of reset!\n");

    do_inference(img_letter_A, "Letter A", rst_n, uio_in, ui_in, uo_out, uio_out);
    do_inference(img_letter_B, "Letter B", rst_n, uio_in, ui_in, uo_out, uio_out);

    munmap(base, HW_REGS_SPAN);
    close(fd);
    return 0;
}
