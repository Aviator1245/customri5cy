// Copyright 2026 - NPU for RI5CY
// 8×8 MAC Array - 64 parallel MACs

module mac_array_8x8 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,
    input  logic        clear,
    
    // 8 weights per row, 8 rows = 64 weights
    input  logic signed [7:0]  weights [0:7][0:7],
    
    // 8 activations (broadcast to all rows)
    input  logic signed [7:0]  activations [0:7],
    
    // 8 outputs (one per row)
    output logic signed [31:0] results [0:7]
);

    // Internal: partial results for each MAC
    logic signed [31:0] mac_results [0:7][0:7];
    
    //═══════════════════════════════════════════════════════════
    // Generate 8 rows × 8 columns = 64 MAC units
    //═══════════════════════════════════════════════════════════
    genvar row, col;
    generate
        for (row = 0; row < 8; row++) begin : row_gen
            for (col = 0; col < 8; col++) begin : col_gen
                
                mac_unit mac (
                    .clk(clk),
                    .rst_n(rst_n),
                    .enable(enable),
                    .clear(clear),
                    .weight(weights[row][col]),
                    .activation(activations[col]),
                    .result(mac_results[row][col])
                );
                
            end
        end
    endgenerate
    
    //═══════════════════════════════════════════════════════════
    // Sum all 8 MACs in each row to get final result
    //═══════════════════════════════════════════════════════════
    always_comb begin
        for (int r = 0; r < 8; r++) begin
            results[r] = mac_results[r][0] + mac_results[r][1] + 
                         mac_results[r][2] + mac_results[r][3] +
                         mac_results[r][4] + mac_results[r][5] +
                         mac_results[r][6] + mac_results[r][7];
        end
    end

endmodule
