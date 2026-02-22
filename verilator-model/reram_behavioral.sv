
// reram_cell_behavioral.sv
// Behavioral model of ReRAM based on Verilog-A Linear Ion Drift

module reram_cell_behavioral #(
    parameter real RON  = 100.0,
    parameter real ROFF = 200000.0,  
    parameter real D    = 3.0e-9,
    parameter real UV   = 1.0e-15,
    parameter real DT   = 1.0e-9,
    parameter int  W_BITS = 16
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] voltage_in,
    output logic [15:0] current_out,
    output logic [15:0] w_state
);
    logic [W_BITS-1:0] w;
    logic [W_BITS-1:0] w_next;
    localparam real DWDT_COEFF = (UV * RON / D) * 65536.0;
    localparam int  DWDT_SCALED = int'(DWDT_COEFF);
    logic [31:0] resistance;
    logic [31:0] current;
    
    always_comb begin
        automatic longint r_temp;
        r_temp = (int'(RON) * w) + (int'(ROFF) * (65536 - w));
        resistance = r_temp >> 16;
        if (resistance != 0) current = (voltage_in * 1000) / resistance;
        else                 current = 32'hFFFFFFFF;
    end
    
    always_comb begin
        automatic longint dwdt;
        automatic longint w_delta;
        automatic int signed current_signed = signed'(current);
        dwdt = DWDT_SCALED * current_signed;
        w_delta = (dwdt * int'(DT * 1e9)) >> 16;
        w_next = w + w_delta[W_BITS-1:0];
        if (w_next > 65535) w_next = 65535;
        else if (w_next[W_BITS-1]) w_next = 0;
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) w <= 16'h8000;
        else        w <= w_next;
    end
    
    assign w_state = w;
    assign current_out = current[15:0];
endmodule

//═══════════════════════════════════════════════════════════
// Simplified Version for Fast Simulation
module reram_cell_simple (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        program_enable,
    input  logic [7:0]  target_conductance,
    input  logic [7:0]  voltage_in,
    output logic [15:0] current_out
);
    logic [7:0] conductance_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conductance_state <= 8'h00;
        end else if (program_enable) begin
            conductance_state <= target_conductance;
        end
    end

    // Exact integer math: V * G
    assign current_out = 16'( (32'(voltage_in) * 32'(conductance_state)) );
endmodule

module reram_crossbar_8x8 (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         prog_enable,
    input  logic [5:0]   prog_addr,
    input  logic [7:0]   prog_data,
    input  logic [63:0]  voltages_packed,  
    output logic [255:0] currents_packed   
);
    logic [15:0] flat_cell_currents [0:63];

    genvar r, c;
    generate
        for (r = 0; r < 8; r++) begin : row_gen
            for (c = 0; c < 8; c++) begin : col_gen
                logic [7:0] v_in;
                assign v_in = voltages_packed[c*8 +: 8];

                reram_cell_simple cell_inst (
                    .clk            (clk),
                    .rst_n          (rst_n),
                    .program_enable (prog_enable && (prog_addr == (r*8 + c))),
                    .target_conductance(prog_data),
                    .voltage_in     (v_in),
                    .current_out    (flat_cell_currents[r*8 + c])
                );
            end
        end
    endgenerate

    always_comb begin
        for (int i = 0; i < 8; i++) begin
            automatic logic [63:0] row_sum = 0;
            for (int j = 0; j < 8; j++) begin
                row_sum = row_sum + 64'(flat_cell_currents[i*8 + j]);
            end
            // EXACT MATH: Pass the raw sum directly without dividing
            currents_packed[i*32 +: 32] = 32'(row_sum);
        end
    end
endmodule



//═══════════════════════════════════════════════════════════
// Testbench Example
//═══════════════════════════════════════════════════════════

module tb_reram;
    logic clk, rst_n;
    logic [7:0] voltages[0:7];
    logic [15:0] currents[0:7];
    
    // Instantiate crossbar
    reram_crossbar_8x8 dut (
        .clk(clk),
        .rst_n(rst_n),
        .prog_enable(1'b0),
        .prog_addr(6'h0),
        .prog_data(8'h0),
        .voltages(voltages),
        .currents(currents)
    );
    
    // Clock
    initial clk = 0;
    always #5 clk = ~clk;
    
    // Test
    initial begin
        rst_n = 0;
        #20 rst_n = 1;
        
        // Program identity matrix
        for (int i = 0; i < 8; i++) begin
            @(posedge clk);
            dut.prog_enable = 1;
            dut.prog_addr = i*8 + i;     // Diagonal
            dut.prog_data = 8'hFF;       // Max conductance
        end
        
        @(posedge clk);
        dut.prog_enable = 0;
        
        // Apply inputs
        for (int i = 0; i < 8; i++)
            voltages[i] = i + 1;  // [1,2,3,4,5,6,7,8]
        
        #100;
        
        // Check outputs (should equal inputs for identity matrix)
        for (int i = 0; i < 8; i++)
            $display("Current[%0d] = %0d (expected %0d)", 
                     i, currents[i], voltages[i]);
        
        $finish;
    end
    
endmodule
