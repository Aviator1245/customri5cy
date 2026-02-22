// =============================================================
// NPU Coprocessor - 8x8 MAC Array with mixed signed/unsigned
// =============================================================
module npu_coprocessor (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        cpu_write,
    input  logic [6:0]  cpu_byte_off,
    input  logic [31:0] cpu_wdata,
    input  logic        cpu_read,
    input  logic [6:0]  cpu_read_off,
    output logic [31:0] cpu_rdata
);
    // Weights: always signed INT8
    logic signed [7:0] weight_buf [0:63];
    
    // Inputs: stored as 8-bit, but MAC treats as UNSIGNED for layer1
    logic [7:0] input_buf [0:7];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 64; i++) weight_buf[i] <= 8'sh0;
            for (int i = 0; i < 8;  i++) input_buf[i]  <= 8'h0;
        end else if (cpu_write) begin
            if (cpu_byte_off < 7'h40) begin
                automatic int base = {cpu_byte_off[5:2], 2'b00};
                weight_buf[base+0] <= $signed(cpu_wdata[7:0]);
                weight_buf[base+1] <= $signed(cpu_wdata[15:8]);
                weight_buf[base+2] <= $signed(cpu_wdata[23:16]);
                weight_buf[base+3] <= $signed(cpu_wdata[31:24]);
            end else if (cpu_byte_off >= 7'h40 && cpu_byte_off <= 7'h47) begin
                automatic int base = cpu_byte_off[2] ? 4 : 0;
                input_buf[base+0] <= cpu_wdata[7:0];    // unsigned
                input_buf[base+1] <= cpu_wdata[15:8];
                input_buf[base+2] <= cpu_wdata[23:16];
                input_buf[base+3] <= cpu_wdata[31:24];
            end
        end
    end

    // Combinational MAC: signed weight × UNSIGNED input
    logic signed [31:0] mac_out [0:7];
    always_comb begin
        for (int row = 0; row < 8; row++) begin
            automatic logic signed [31:0] acc = 32'sh0;
            for (int col = 0; col < 8; col++) begin
                // Treat input as unsigned by zero-extending to 32-bit
                automatic logic signed [31:0] w = $signed(weight_buf[row*8+col]);
                automatic logic signed [31:0] x = {24'h0, input_buf[col]};  // unsigned extend
                acc += w * x;
            end
            mac_out[row] = acc;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cpu_rdata <= 32'h0;
        else if (cpu_read) begin
            if (cpu_read_off == 7'h6C)
                cpu_rdata <= 32'h1;
            else if (cpu_read_off >= 7'h48 && cpu_read_off <= 7'h64) begin
                automatic int row = (int'(cpu_read_off) - 8'h48) >> 2;
                cpu_rdata <= mac_out[row];
            end else
                cpu_rdata <= 32'hDEADCAFE;
        end
    end
endmodule
