// Copyright 2026 - NPU for RI5CY
// Single INT8 MAC Unit

module mac_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,      // Compute enable
    input  logic        clear,       // Clear accumulator
    input  logic signed [7:0]  weight,      // INT8 weight
    input  logic signed [7:0]  activation,  // INT8 input
    output logic signed [31:0] result       // INT32 accumulator
);

    logic signed [31:0] accumulator;
    logic signed [15:0] product;
    
    // Multiply (combinational)
    always_comb begin
        product = weight * activation;
    end
    
    // Accumulate (sequential)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 32'h0;
        end else if (clear) begin
            accumulator <= 32'h0;
        end else if (enable) begin
            accumulator <= accumulator + $signed(product);
        end
    end
    
    assign result = accumulator;

endmodule
