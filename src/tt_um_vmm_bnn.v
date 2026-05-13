`default_nettype none

module tt_um_vmm_bnn (
    input  wire [7:0] ui_in,    // 8 Είσοδοι: Pixels ή Weights (ανάλογα το mode)
    output wire [7:0] uo_out,   // 8 Έξοδοι: Τα κάτω 8 bits του Accumulator
    input  wire [7:0] uio_in,   // 8 Bidirectional (χρησιμοποιούνται ως Control Pins)
    output wire [7:0] uio_out,  // Τα πάνω 2 bits του Accumulator βγαίνουν από εδώ
    output wire [7:0] uio_oe,   // Ποια pins είναι έξοδοι (1) και ποια είσοδοι (0)
    input  wire       ena,      // Enable του Tiny Tapeout
    input  wire       clk,      // Clock (από τον RP2040)
    input  wire       rst_n     // Reset (Active Low)
);

    // --- 1. ΚΑΛΩΔΙΩΣΗ ΕΛΕΓΧΟΥ (Control Signals) ---
    wire load_weights = uio_in[0];      // 1 = Φόρτωση, 0 = Υπολογισμός
    wire [2:0] addr   = uio_in[3:1];    // Διεύθυνση Νευρώνα (0-7)
    wire compute_en   = uio_in[4];      // 1 = Άθροισε, 0 = Πάγωσε

    // Στήνουμε τα Bidirectional pins: Θέλουμε τα 7 και 6 να είναι Έξοδοι (1), τα υπόλοιπα Είσοδοι (0)
    assign uio_oe = 8'b11000000;

    // Το Tiny Tapeout έχει Reset που ενεργοποιείται με το 0 (rst_n). Το κάνουμε κανονικό.
    wire reset = ~rst_n;

    // --- 2. Η ΜΝΗΜΗ ΤΩΝ ΒΑΡΩΝ (64 D-Flip-Flops) ---
    reg [7:0] weight_regs [0:7];

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 8; i = i + 1) begin
                weight_regs[i] <= 8'd0;
            end
        end else if (load_weights) begin
            // Αν είμαστε σε φόρτωση, γράψε την είσοδο στον επιλεγμένο Νευρώνα
            weight_regs[addr] <= ui_in;
        end
    end

    // Καλώδια για να διαβάζουμε τα 10-bit αθροίσματα από τους 8 Νευρώνες
    wire [9:0] acc_out [0:7];

    // --- 3. ΣΥΝΔΕΣΗ ΤΩΝ 8 ΝΕΥΡΩΝΩΝ (Το "Κρέας" του NPU) ---
    genvar j;
    generate
        for (j = 0; j < 8; j = j + 1) begin : gen_neurons
            neuron n (
                .clk(clk),
                .reset(reset),
                .enable(compute_en && !load_weights), // Υπολογίζει ΜΟΝΟ αν ΔΕΝ φορτώνει βάρη
                .pixels(ui_in),
                .weights(weight_regs[j]),
                .accumulator(acc_out[j])
            );
        end
    endgenerate

    // --- 4. MULTIPLEXER ΕΞΟΔΟΥ (Output Routing) ---
    // Διαβάζουμε το άθροισμα του Νευρώνα που μας ζητάει ο RP2040 (μέσω του addr)
    wire [9:0] selected_acc = acc_out[addr];

    // Στέλνουμε τα 8 κάτω bits στα κανονικά outputs
    assign uo_out = selected_acc[7:0];
    
    // Στέλνουμε τα 2 πάνω bits στα ελεύθερα bidirectional pins
    assign uio_out[7:6] = selected_acc[9:8];
    assign uio_out[5:0] = 6'b000000; // Γειώνουμε τα υπόλοιπα για ασφάλεια

endmodule