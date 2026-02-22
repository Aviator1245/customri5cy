module dp_ram
  #(
    parameter ADDR_WIDTH = 20   // 1 MB RAM
  )(
    input  logic clk,

    /////////////////////////////////////////////////////////////
    // PORT A → Instruction Fetch
    /////////////////////////////////////////////////////////////
    input  logic                   en_a_i,
    input  logic [ADDR_WIDTH-1:0]  addr_a_i,
    input  logic [31:0]            wdata_a_i,
    output logic [127:0]           rdata_a_o,
    input  logic                   we_a_i,
    input  logic [3:0]             be_a_i,

    /////////////////////////////////////////////////////////////
    // PORT B → Data Access
    /////////////////////////////////////////////////////////////
    input  logic                   en_b_i,
    input  logic [ADDR_WIDTH-1:0]  addr_b_i,
    input  logic [31:0]            wdata_b_i,
    output logic [31:0]            rdata_b_o,
    input  logic                   we_b_i,
    input  logic [3:0]             be_b_i
  );

  localparam RAM_BYTES = 2**ADDR_WIDTH;

  logic [7:0] mem [0:RAM_BYTES-1];

  logic [ADDR_WIDTH-1:0] addr_b_aligned;

  /////////////////////////////////////////////////////////////
  // Word Align Data Port
  /////////////////////////////////////////////////////////////
  always_comb addr_b_aligned = {addr_b_i[ADDR_WIDTH-1:2], 2'b00};

  /////////////////////////////////////////////////////////////
  // RAM Behavior
  /////////////////////////////////////////////////////////////
  always_ff @(posedge clk)
  begin

    ////////////////////////////////
    // PORT A → Instruction Fetch
    ////////////////////////////////
    if (en_a_i)
    begin
      rdata_a_o[  0+:8] <= mem[addr_a_i +  0];
      rdata_a_o[  8+:8] <= mem[addr_a_i +  1];
      rdata_a_o[ 16+:8] <= mem[addr_a_i +  2];
      rdata_a_o[ 24+:8] <= mem[addr_a_i +  3];
      rdata_a_o[ 32+:8] <= mem[addr_a_i +  4];
      rdata_a_o[ 40+:8] <= mem[addr_a_i +  5];
      rdata_a_o[ 48+:8] <= mem[addr_a_i +  6];
      rdata_a_o[ 56+:8] <= mem[addr_a_i +  7];
      rdata_a_o[ 64+:8] <= mem[addr_a_i +  8];
      rdata_a_o[ 72+:8] <= mem[addr_a_i +  9];
      rdata_a_o[ 80+:8] <= mem[addr_a_i + 10];
      rdata_a_o[ 88+:8] <= mem[addr_a_i + 11];
      rdata_a_o[ 96+:8] <= mem[addr_a_i + 12];
      rdata_a_o[104+:8] <= mem[addr_a_i + 13];
      rdata_a_o[112+:8] <= mem[addr_a_i + 14];
      rdata_a_o[120+:8] <= mem[addr_a_i + 15];
    end

    ////////////////////////////////
    // PORT B → Data Access
    ////////////////////////////////
    if (en_b_i)
    begin
      if (we_b_i)
      begin
        if (be_b_i[0]) mem[addr_b_aligned + 0] <= wdata_b_i[7:0];
        if (be_b_i[1]) mem[addr_b_aligned + 1] <= wdata_b_i[15:8];
        if (be_b_i[2]) mem[addr_b_aligned + 2] <= wdata_b_i[23:16];
        if (be_b_i[3]) mem[addr_b_aligned + 3] <= wdata_b_i[31:24];
      end
      else
      begin
        rdata_b_o[7:0]   <= mem[addr_b_aligned + 0];
        rdata_b_o[15:8]  <= mem[addr_b_aligned + 1];
        rdata_b_o[23:16] <= mem[addr_b_aligned + 2];
        rdata_b_o[31:24] <= mem[addr_b_aligned + 3];
      end
    end
  end


  function [7:0] readByte;
    /* verilator public */
    input integer byte_addr;
    readByte = mem[byte_addr];
  endfunction

  task writeByte;
    /* verilator public */
    input integer byte_addr;
    input [7:0] val;
    mem[byte_addr] = val;
  endtask

endmodule

