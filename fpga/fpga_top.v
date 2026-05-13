`default_nettype none

module fpga_top (
    input  wire       CLOCK_50, 
    input  wire [3:0] KEY,      
    output wire [3:0] LEDR,  

    // --- ΚΑΛΩΔΙΑ ΓΙΑ ΤΗ RAM ΤΟΥ ARM (ΑΠΑΡΑΙΤΗΤΑ ΓΙΑ ΤΟ QUARTUS) ---
    output wire [14:0] hps_memory_mem_a,
    output wire [2:0]  hps_memory_mem_ba,
    output wire        hps_memory_mem_ck,
    output wire        hps_memory_mem_ck_n,
    output wire        hps_memory_mem_cke,
    output wire        hps_memory_mem_cs_n,
    output wire        hps_memory_mem_ras_n,
    output wire        hps_memory_mem_cas_n,
    output wire        hps_memory_mem_we_n,
    output wire        hps_memory_mem_reset_n,
    inout  wire [31:0] hps_memory_mem_dq,
    inout  wire [3:0]  hps_memory_mem_dqs,
    inout  wire [3:0]  hps_memory_mem_dqs_n,
    output wire        hps_memory_mem_odt,
    output wire [3:0]  hps_memory_mem_dm,
    input  wire        hps_memory_oct_rzqin
);

    wire reset_n_from_hps;

    wire [7:0] arm_to_npu_ui;   
    wire [7:0] arm_to_npu_uio;  
    wire [7:0] npu_to_arm_uo;   
    
    wire [7:0] npu_uio_out;     
    wire [7:0] npu_uio_oe;      

    // --- 1. Ο Επεξεργαστής ARM ---
    soc_system u0 (
        .clk_clk                               (CLOCK_50),       
        .reset_reset_n                         (KEY[0]),  
        .pio_uio_out_external_connection_export      (npu_uio_out),
        .pio_reset_n_external_connection_export (reset_n_from_hps),
        
        // Συνδέουμε τη RAM του ARM με τα εξωτερικά pins!
        .memory_mem_a                          (hps_memory_mem_a),
        .memory_mem_ba                         (hps_memory_mem_ba),
        .memory_mem_ck                         (hps_memory_mem_ck),
        .memory_mem_ck_n                       (hps_memory_mem_ck_n),
        .memory_mem_cke                        (hps_memory_mem_cke),
        .memory_mem_cs_n                       (hps_memory_mem_cs_n),
        .memory_mem_ras_n                      (hps_memory_mem_ras_n),
        .memory_mem_cas_n                      (hps_memory_mem_cas_n),
        .memory_mem_we_n                       (hps_memory_mem_we_n),
        .memory_mem_reset_n                    (hps_memory_mem_reset_n),
        .memory_mem_dq                         (hps_memory_mem_dq),
        .memory_mem_dqs                        (hps_memory_mem_dqs),
        .memory_mem_dqs_n                      (hps_memory_mem_dqs_n),
        .memory_mem_odt                        (hps_memory_mem_odt),
        .memory_mem_dm                         (hps_memory_mem_dm),
        .memory_oct_rzqin                      (hps_memory_oct_rzqin),

        // Τα NPU PIOs
        .pio_ui_in_external_connection_export  (arm_to_npu_ui),  
        .pio_uio_in_external_connection_export (arm_to_npu_uio), 
        .pio_uo_out_external_connection_export (npu_to_arm_uo)   
    );

    // --- 2. Το NPU μας ---
    tt_um_vmm_bnn my_npu (
        .ui_in   (arm_to_npu_ui),   
        .uo_out  (npu_to_arm_uo),   
        .uio_in  (arm_to_npu_uio),  
        .uio_out (npu_uio_out),
        .uio_oe  (npu_uio_oe),
        .ena     (1'b1),            
        .clk     (CLOCK_50),        
        .rst_n   (reset_n_from_hps)   // κρατάς και το κουμπί        
    );

    // --- 3. LEDs ---
    assign LEDR[3:0] = npu_to_arm_uo[3:0];

endmodule