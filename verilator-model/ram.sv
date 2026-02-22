module ram
#(
    parameter ADDR_WIDTH = 20   // 1 MB RAM
)
(
    input  logic        clk,
    input  logic        rst_n,

    /////////////////////////////////////////////////////////////
    // Instruction Port
    /////////////////////////////////////////////////////////////
    input  logic                  instr_req_i,
    input  logic [ADDR_WIDTH-1:0] instr_addr_i,
    output logic [127:0]          instr_rdata_o,
    output logic                  instr_rvalid_o,
    output logic                  instr_gnt_o,

    /////////////////////////////////////////////////////////////
    // Data Port
    /////////////////////////////////////////////////////////////
    input  logic                  data_req_i,
    input  logic [ADDR_WIDTH-1:0] data_addr_i,
    input  logic                  data_we_i,
    input  logic [3:0]            data_be_i,
    input  logic [31:0]           data_wdata_i,
    output logic [31:0]           data_rdata_o,
    output logic                  data_rvalid_o,
    output logic                  data_gnt_o
);

  /////////////////////////////////////////////////////////////
  // Immediate Grants
  /////////////////////////////////////////////////////////////
  assign instr_gnt_o = instr_req_i;
  assign data_gnt_o  = data_req_i;

  /////////////////////////////////////////////////////////////
  // Valid Signals
  /////////////////////////////////////////////////////////////
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_rvalid_o <= 1'b0;
      data_rvalid_o  <= 1'b0;
    end 
    else begin
      instr_rvalid_o <= instr_req_i;
      data_rvalid_o  <= data_req_i;
    end
  end

  /////////////////////////////////////////////////////////////
  // Dual-Port RAM
  /////////////////////////////////////////////////////////////
  dp_ram #(
      .ADDR_WIDTH(ADDR_WIDTH)
  ) dp_ram_i (
      .clk       (clk),

      ///////////////////////
      // PORT A → INSTRUCTION
      ///////////////////////
      .en_a_i    (instr_req_i),
      .addr_a_i  (instr_addr_i),
      .wdata_a_i (32'b0),
      .rdata_a_o (instr_rdata_o),
      .we_a_i    (1'b0),
      .be_a_i    (4'b0),

      ///////////////////////
      // PORT B → DATA
      ///////////////////////
      .en_b_i    (data_req_i),
      .addr_b_i  (data_addr_i),
      .wdata_b_i (data_wdata_i),
      .rdata_b_o (data_rdata_o),
      .we_b_i    (data_we_i),
      .be_b_i    (data_be_i)
  );

  /////////////////////////////////////////////////////////////
  // Firmware Loader - LARGER BUFFER
  /////////////////////////////////////////////////////////////
  integer i;
  integer file;
  integer bytes_read;

  localparam RAM_BYTES = 2**ADDR_WIDTH;
  localparam MAX_FW_SIZE = 262144;  // 256 KiB
  reg [7:0] temp_mem [0:MAX_FW_SIZE-1];

  initial begin
    $display("=======================================");
    $display("Loading firmware into RAM...");
    $display("=======================================");

    /////////////////////////////////////////////////////////////
    // Clear ALL RAM
    /////////////////////////////////////////////////////////////
    for (i = 0; i < RAM_BYTES; i = i + 1)
      dp_ram_i.mem[i] = 8'h00;

    /////////////////////////////////////////////////////////////
    // Clear temp memory
    /////////////////////////////////////////////////////////////
    for (i = 0; i < MAX_FW_SIZE; i = i + 1)
      temp_mem[i] = 8'hXX;

    /////////////////////////////////////////////////////////////
    // Check firmware existence
    /////////////////////////////////////////////////////////////
    file = $fopen("firmware.hex", "r");
    if (file == 0) begin
      $display("ERROR: firmware.hex NOT FOUND");
      $finish;
    end
    $fclose(file);

    $display("firmware.hex FOUND");

    /////////////////////////////////////////////////////////////
    // Read firmware
    /////////////////////////////////////////////////////////////
    $readmemh("firmware.hex", temp_mem);

    /////////////////////////////////////////////////////////////
    // Count valid bytes
    /////////////////////////////////////////////////////////////
    bytes_read = 0;
    for (i = 0; i < MAX_FW_SIZE; i = i + 1) begin
      if (temp_mem[i] !== 8'hXX) begin
        bytes_read = bytes_read + 1;
      end
    end

    $display("Firmware size: %0d bytes (0x%0x)", bytes_read, bytes_read);

    /////////////////////////////////////////////////////////////
    // Copy ALL valid bytes to RAM at 0x80
    /////////////////////////////////////////////////////////////
    for (i = 0; i < bytes_read; i = i + 1) begin
      dp_ram_i.mem[32'h80 + i] = temp_mem[i];
    end

    $display("Firmware loaded to RAM @ 0x80");

    /////////////////////////////////////////////////////////////
    // Sanity Dump
    /////////////////////////////////////////////////////////////
    $display("First 16 instructions:");

    for (i = 0; i < 16; i = i + 1) begin
      $display("  [0x%08x] = %02x %02x %02x %02x",
               32'h80 + (i*4),
               dp_ram_i.mem[32'h80 + (i*4) + 0],
               dp_ram_i.mem[32'h80 + (i*4) + 1],
               dp_ram_i.mem[32'h80 + (i*4) + 2],
               dp_ram_i.mem[32'h80 + (i*4) + 3]);
    end

    $display("=======================================");
  end

endmodule
