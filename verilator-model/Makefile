# Makefile for Verilator model of RI5CY

VERILATOR = verilator
VDIR = obj_dir
CPPFLAGS = -I$(VDIR) `pkg-config --cflags verilator`
CXXFLAGS = -Wall -Werror -std=c++14
CXX = g++
LD = g++

SRC = testbench.cpp
OBJS = testbench.o
EXE = testbench
TOP = top

VSRC = ../include/riscv_defines.sv        \
       ../include/riscv_tracer_defines.sv \
       ../alu.sv                          \
       ../alu_div.sv                      \
       cluster_clock_gating.sv            \
       ../compressed_decoder.sv           \
       ../controller.sv                   \
       ../cs_registers.sv                 \
       ../debug_unit.sv                   \
       ../decoder.sv                      \
       dp_ram.sv                          \
       ../exc_controller.sv               \
       ../ex_stage.sv                     \
       ../hwloop_controller.sv            \
       ../hwloop_regs.sv                  \
       ../id_stage.sv                     \
       ../if_stage.sv                     \
       ../load_store_unit.sv              \
       ../mult.sv                         \
       ../prefetch_buffer.sv              \
       ../prefetch_L0_buffer.sv           \
       ram.sv                             \
       ../riscv_core.sv                   \
       ../register_file_ff.sv             \
       mac_unit.sv                        \
       mac_array_8x8.sv                   \
       npu_coprocessor.sv                 \
       reram_behavioral.sv                \
       imc_controller.sv                  \
       top.sv

VINC = ../include

VINCS = $(VINC)/riscv_config.sv           \
        $(VINC)/riscv_defines.sv          \
        $(VINC)/riscv_tracer_defines.sv

VSMK = V$(TOP).mk
VMK  = $(VDIR)/$(VSMK)

$(VDIR)/$(TOP): $(VDIR) $(VMK)
	$(MAKE) -C $(VDIR) -f $(VSMK)

$(VDIR):
	mkdir -p $@

$(VMK): $(VSRC) $(VINCS)
	verilator -O3 -fno-dead-assigns \
                  -CFLAGS "-O3 -g3 -std=gnu++14" \
                  -Wno-CASEINCOMPLETE -Wno-LITENDIAN -Wno-UNOPT \
	          -Wno-UNOPTFLAT -Wno-WIDTH -Wno-fatal --top-module top \
	          --Mdir $(VDIR) --trace -DPULP_FPGA_EMUL -cc \
	          +incdir+$(VINC) $(VSRC) $(SRC) --exe

.PHONY: clean
clean:
	$(RM) -r $(VDIR)
	$(RM) $(EXE) $(OBJS)
