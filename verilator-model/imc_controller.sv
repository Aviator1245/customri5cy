module imc_controller (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        req,
    input  logic        we,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    output logic        gnt,
    output logic        rvalid
);
    localparam ADDR_PROG_DATA  = 32'h400;
    localparam ADDR_PROG_ADDR  = 32'h404;
    localparam ADDR_V_INPUT_LO = 32'h408;
    localparam ADDR_V_INPUT_HI = 32'h40C;
    localparam ADDR_RESULT     = 32'h410; // 0x410 to 0x42C

    logic [63:0]  cb_voltages_packed;
    logic [255:0] cb_currents_packed;
    
    logic        cb_prog_en;
    logic [5:0]  cb_prog_addr;
    logic [7:0]  cb_prog_data;

    assign gnt = req;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rvalid <= 1'b0;
        else        rvalid <= req; 
    end

    reram_crossbar_8x8 crossbar_i (
        .clk(clk), 
        .rst_n(rst_n),
        .prog_enable(cb_prog_en), 
        .prog_addr(cb_prog_addr), 
        .prog_data(cb_prog_data),
        .voltages_packed(cb_voltages_packed),
        .currents_packed(cb_currents_packed)
    );

    // Write Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cb_prog_en <= 1'b0; 
            cb_prog_addr <= 6'h0; 
            cb_prog_data <= 8'h0;
            cb_voltages_packed <= 64'h0;
        end else begin
            if (cb_prog_en) cb_prog_en <= 1'b0; 

            if (req && we) begin
                if (addr == ADDR_PROG_DATA) begin
                    cb_prog_data <= wdata[7:0];
                end else if (addr == ADDR_PROG_ADDR) begin
                    cb_prog_addr <= wdata[5:0];
                    cb_prog_en   <= 1'b1; 
                end else if (addr == ADDR_V_INPUT_LO) begin
                    cb_voltages_packed[31:0] <= wdata;
                end else if (addr == ADDR_V_INPUT_HI) begin
                    cb_voltages_packed[63:32] <= wdata;
                end
            end
        end
    end

    // Sequential Read Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata <= 32'h0;
        end else begin
            if (req && !we) begin
                if (addr >= ADDR_RESULT && addr <= 32'h42C) begin
                    int idx = (addr - ADDR_RESULT) >> 2;
                    if (idx < 8) begin
                        rdata <= cb_currents_packed[idx*32 +: 32]; 
                    end else begin
                        rdata <= 32'h0;
                    end
                end else if (addr == ADDR_PROG_ADDR) begin
                    rdata <= {26'b0, cb_prog_addr};
                end else if (addr == ADDR_PROG_DATA) begin
                    rdata <= {24'b0, cb_prog_data};
                end else begin
                    rdata <= 32'h0;
                end
            end
        end
    end
endmodule
