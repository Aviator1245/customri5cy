// top.sv - Final Fixed Version
module top
#(
    parameter INSTR_RDATA_WIDTH = 128,
    parameter ADDR_WIDTH        = 22,
    parameter BOOT_ADDR         = 'h80,
    parameter UART_ADDR         = 'h100,
    parameter NPU_BASE          = 'h200,
    parameter NPU_END           = 'h270,
    parameter CYCLE_ADDR        = 'h300,
    parameter IMC_BASE          = 'h400,
    parameter IMC_END           = 'h430
)
(
    input  logic        clk_i,
    input  logic        rstn_i,
    input  logic [31:0] irq_i,
    input  logic        debug_req_i,
    output logic        debug_gnt_o,
    output logic        debug_rvalid_o,
    input  logic [14:0] debug_addr_i,
    input  logic        debug_we_i,
    input  logic [31:0] debug_wdata_i,
    output logic [31:0] debug_rdata_o,
    output logic        debug_halted_o,
    input  logic        fetch_enable_i,
    output logic        core_busy_o,
    output logic        data_req_o,
    output logic        data_we_o,
    output logic [31:0] data_addr_o,
    output logic [31:0] data_wdata_o
);

    // Bus Signals
    logic                  instr_req, instr_gnt, instr_rvalid;
    logic [ADDR_WIDTH-1:0] instr_addr;
    logic [127:0]          instr_rdata;
    logic                  data_req, data_gnt, data_rvalid;
    logic [ADDR_WIDTH-1:0] data_addr;
    logic                  data_we;
    logic [31:0]           data_wdata, data_rdata;
    logic [3:0]            data_be;

    // Address Decoding
    logic is_uart, is_npu, is_cycle, is_ram, is_imc;
    assign is_uart  = data_req && (data_addr == UART_ADDR);
    assign is_npu   = data_req && ({10'b0,data_addr} >= NPU_BASE) && ({10'b0,data_addr} < NPU_END);
    assign is_cycle = data_req && (data_addr == CYCLE_ADDR);
    assign is_imc   = data_req && ({10'b0,data_addr} >= IMC_BASE) && ({10'b0,data_addr} < IMC_END);
    assign is_ram   = data_req && !is_uart && !is_npu && !is_cycle && !is_imc;

    // UART
    logic uart_rvalid;
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) uart_rvalid <= 1'b0;
        else         uart_rvalid <= is_uart;
    end

    // Cycle Counter
    logic [31:0] cycle_ctr;
    logic        cycle_rvalid;
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin cycle_ctr <= 0; cycle_rvalid <= 0; end
        else begin
            cycle_ctr    <= cycle_ctr + 1;
            cycle_rvalid <= is_cycle;
        end
    end

    // NPU
    logic [31:0] npu_rdata;
    logic        npu_rvalid;
    npu_coprocessor npu_i (
        .clk(clk_i), .rst_n(rstn_i),
        .cpu_write(is_npu && data_we), .cpu_byte_off(data_addr[6:0]), .cpu_wdata(data_wdata),
        .cpu_read(is_npu && !data_we), .cpu_read_off(data_addr[6:0]), .cpu_rdata(npu_rdata)
    );
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) npu_rvalid <= 1'b0;
        else         npu_rvalid <= is_npu;
    end

    // IMC (ReRAM)
    logic [31:0] imc_rdata;
    logic        imc_rvalid;
    imc_controller imc_i (
        .clk(clk_i), .rst_n(rstn_i),
        .req(is_imc), .we(data_we), .addr({10'b0, data_addr}),
        .wdata(data_wdata), .rdata(imc_rdata), .gnt(), .rvalid(imc_rvalid)
    );

    // RAM
    logic [31:0] ram_rdata;
    logic        ram_rvalid;
    ram #(.ADDR_WIDTH(ADDR_WIDTH-2)) ram_i (
        .clk(clk_i), .rst_n(rstn_i),
        .instr_req_i(instr_req), .instr_addr_i(instr_addr), .instr_rdata_o(instr_rdata),
        .instr_rvalid_o(instr_rvalid), .instr_gnt_o(instr_gnt),
        .data_req_i(is_ram), .data_addr_i(data_addr), .data_we_i(data_we), .data_be_i(data_be),
        .data_wdata_i(data_wdata), .data_rdata_o(ram_rdata), .data_rvalid_o(ram_rvalid), .data_gnt_o()
    );

    // Bus Mux
    assign data_gnt = is_uart | is_npu | is_cycle | is_ram | is_imc;
    assign data_rvalid = uart_rvalid | npu_rvalid | cycle_rvalid | ram_rvalid | imc_rvalid;
    assign data_rdata = npu_rvalid ? npu_rdata : 
                        cycle_rvalid ? cycle_ctr : 
                        imc_rvalid ? imc_rdata : 
                        ram_rdata;

    // TB Output
    assign data_req_o = is_uart;
    assign data_we_o = data_we;
    assign data_addr_o = {10'b0, data_addr};
    assign data_wdata_o = data_wdata;

    // RI5CY Core
    riscv_core #(.INSTR_RDATA_WIDTH(INSTR_RDATA_WIDTH)) riscv_core_i (
        .clk_i(clk_i), .rst_ni(rstn_i), .clock_en_i(1'b1), .test_en_i(1'b1),
        .boot_addr_i(BOOT_ADDR), .core_id_i(4'h0), .cluster_id_i(6'h0),
        .instr_addr_o(instr_addr), .instr_req_o(instr_req), .instr_rdata_i(instr_rdata),
        .instr_gnt_i(instr_gnt), .instr_rvalid_i(instr_rvalid),
        .data_addr_o(data_addr), .data_wdata_o(data_wdata), .data_we_o(data_we),
        .data_req_o(data_req), .data_be_o(data_be), .data_rdata_i(data_rdata),
        .data_gnt_i(data_gnt), .data_rvalid_i(data_rvalid), .data_err_i(1'b0),
        .irq_i(irq_i), .debug_req_i(debug_req_i), .debug_gnt_o(debug_gnt_o),
        .debug_rvalid_o(debug_rvalid_o), .debug_addr_i(debug_addr_i),
        .debug_we_i(debug_we_i), .debug_wdata_i(debug_wdata_i), .debug_rdata_o(debug_rdata_o),
        .debug_halted_o(debug_halted_o), .debug_halt_i(1'b0), .debug_resume_i(1'b0),
        .fetch_enable_i(fetch_enable_i), .core_busy_o(core_busy_o), .ext_perf_counters_i()
    );

endmodule
