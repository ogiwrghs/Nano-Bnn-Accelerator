`default_nettype none

module neuron (
    input  wire clk,
    input  wire reset,
    input  wire enable,
    input  wire [7:0] pixels,
    input  wire [7:0] weights,
    output reg  [9:0] accumulator
);

    wire [7:0] xnor_out;
    wire [3:0] popcount;

    assign xnor_out = ~(pixels ^ weights);

    assign popcount = xnor_out[0] + xnor_out[1] + xnor_out[2] + xnor_out[3] +
                      xnor_out[4] + xnor_out[5] + xnor_out[6] + xnor_out[7];

    reg enable_d;

    always @(posedge clk) begin
        if (reset) begin
            accumulator <= 10'd0;
            enable_d <= 1'b0;
        end else begin
            // accumulate only on rising edge of enable
            if (enable && !enable_d) begin
                accumulator <= accumulator + popcount;
            end
            enable_d <= enable;
        end
    end

endmodule