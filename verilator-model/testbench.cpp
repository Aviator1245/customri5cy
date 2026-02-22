#include "Vtop.h"
#include "verilated.h"
#include <iostream>
#include <map>
#include <string>

#define UART_ADDR 0x100

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vtop *top = new Vtop;
    
    top->clk_i = 0;
    top->rstn_i = 0;
    top->fetch_enable_i = 0;
    top->irq_i = 0;
    top->debug_req_i = 0;
    top->debug_we_i = 0;
    top->debug_addr_i = 0;
    top->debug_wdata_i = 0;
    
    // Reset
    for (int i = 0; i < 20; i++) {
        top->clk_i = !top->clk_i;
        top->eval();
    }
    
    top->rstn_i = 1;
    for (int i = 0; i < 10; i++) {
        top->clk_i = !top->clk_i;
        top->eval();
    }
    
    top->fetch_enable_i = 1;
    
    uint64_t max_cycles = 20000000;
    bool last_uart_write = false;
    std::string current_line = "";
    
    std::map<std::string, uint64_t> markers;
    uint64_t cycle = 0;
    
    for (; cycle < max_cycles; cycle++) {
        top->clk_i = 0;
        top->eval();
        
        top->clk_i = 1;
        top->eval();
        
        bool uart_write = (top->data_req_o && top->data_we_o && top->data_addr_o == UART_ADDR);
        
        if (uart_write && !last_uart_write) {
            char ch = (char)(top->data_wdata_o & 0xFF);
            std::cout << ch << std::flush;
            current_line += ch;
            
            if (ch == '\n') {
                // Check for markers
                if (current_line.find("@@START_") != std::string::npos) {
                    size_t pos = current_line.find("@@START_");
                    std::string marker = current_line.substr(pos + 8);
                    marker = marker.substr(0, marker.find('\n'));
                    markers["START_" + marker] = cycle;
                }
                else if (current_line.find("@@END_") != std::string::npos) {
                    size_t pos = current_line.find("@@END_");
                    std::string marker = current_line.substr(pos + 6);
                    marker = marker.substr(0, marker.find('\n'));
                    markers["END_" + marker] = cycle;
                }
                current_line = "";
            }
        }
        
        last_uart_write = uart_write;
    }
    
    delete top;
    
    // Calculate and print performance
    std::cout << "\n\n";
    std::cout << "============================================\n";
    std::cout << "Performance Breakdown (Actual Cycles):\n";
    std::cout << "============================================\n";
    
    auto calc_diff = [&](const char* name, const std::string& start_key, const std::string& end_key) {
        if (markers.count(start_key) && markers.count(end_key)) {
            uint64_t diff = markers[end_key] - markers[start_key];
            printf("%-20s %12lu cycles\n", name, diff);
            return diff;
        }
        return (uint64_t)0;
    };
    
    uint64_t prepare = calc_diff("Prepare input:", "START_PREPARE", "END_PREPARE");
    uint64_t layer1  = calc_diff("Layer 1 (784->32):", "START_LAYER1", "END_LAYER1");
    uint64_t relu    = calc_diff("ReLU:", "START_RELU", "END_RELU");
    uint64_t layer2  = calc_diff("Layer 2 (32->10):", "START_LAYER2", "END_LAYER2");
    uint64_t argmax  = calc_diff("Argmax:", "START_ARGMAX", "END_ARGMAX");
    
    std::cout << "--------------------------------------------\n";
    
    uint64_t total = calc_diff("TOTAL:", "START_TOTAL", "END_TOTAL");
    
    std::cout << "============================================\n";
    std::cout << "\nBaseline established! Now let's build the NPU!\n";
    
    return 0;
}
