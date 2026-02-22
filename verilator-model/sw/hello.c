// =============================================================
// CPU vs ReRAM IMC Inference Comparison
// =============================================================

#include <stdio.h>
#include <stdint.h>
#include "mnist_weights_int8.h"

// --- Peripheral Base Addresses ---
#define IMC_PROG_DATA   (*((volatile uint32_t*)0x400))
#define IMC_PROG_ADDR   (*((volatile uint32_t*)0x404))
#define IMC_V_INPUT_LO  (*((volatile uint32_t*)0x408))
#define IMC_V_INPUT_HI  (*((volatile uint32_t*)0x40C))
#define IMC_RESULT(i)   (*((volatile uint32_t*)(0x410 + (i)*4)))
#define CYCLE_CTR       (*((volatile uint32_t*)0x300))

static inline uint32_t read_cycles() { return CYCLE_CTR; }

static int32_t hidden_acc[HIDDEN_SIZE];
static int8_t  hidden_act[HIDDEN_SIZE] __attribute__((aligned(4)));
static int32_t output_acc[OUTPUT_SIZE];

// ==========================================
// 1. Pure CPU Implementation
// ==========================================
static void cpu_mv_u8(const int8_t *W, const uint8_t *inp, int32_t *out, int rows, int cols) {
    for (int r = 0; r < rows; r++) {
        int32_t acc = 0;
        for (int c = 0; c < cols; c++) {
            acc += (int32_t)W[r*cols+c] * (int32_t)inp[c];
        }
        out[r] = acc;
    }
}

static void cpu_mv_i8(const int8_t *W, const int8_t *inp, int32_t *out, int rows, int cols) {
    for (int r = 0; r < rows; r++) {
        int32_t acc = 0;
        for (int c = 0; c < cols; c++) {
            acc += (int32_t)W[r*cols+c] * (int32_t)inp[c];
        }
        out[r] = acc;
    }
}

static int argmax(const int32_t *a, int n) {
    int best = 0;
    for (int i = 1; i < n; i++)
        if (a[i] > a[best]) best = i;
    return best;
}

static int infer_cpu(const uint8_t *img) {
    cpu_mv_u8(w1_int8, img, hidden_acc, HIDDEN_SIZE, INPUT_SIZE);
    for (int i = 0; i < HIDDEN_SIZE; i++) {
        int32_t v = hidden_acc[i] + b1_int32[i];
        if (v < 0) v = 0; 
        v /= H_DIV;
        hidden_act[i] = (v > 127) ? (int8_t)127 : (int8_t)v;
    }

    cpu_mv_i8(w2_int8, hidden_act, output_acc, OUTPUT_SIZE, HIDDEN_SIZE);
    for (int i = 0; i < OUTPUT_SIZE; i++) {
        output_acc[i] += b2_int32[i];
    }
    return argmax(output_acc, OUTPUT_SIZE);
}

// ==========================================
// 2. ReRAM IMC Implementation
// ==========================================
static void imc_tile_mac(const int8_t *W, int rows, int cols, const uint8_t *inp, int32_t *out, int r_start, int c_start) {
    // Program Tile
    for (int r = 0; r < 8; r++) {
        int w_row = r_start + r;
        for (int c = 0; c < 8; c++) {
            int w_col = c_start + c;
            uint32_t g_val = 128; 
            if (w_row < rows && w_col < cols) g_val = (uint32_t)(W[w_row * cols + w_col] + 128); 
            IMC_PROG_DATA = g_val;
            IMC_PROG_ADDR = (r * 8) + c;
        }
    }

    // Set Inputs
    uint8_t v[8] = {0};
    uint32_t sum_v = 0;
    for(int c = 0; c < 8; c++) {
        if((c_start + c) < cols) {
            v[c] = inp[c_start + c];
            sum_v += v[c];
        }
    }
    IMC_V_INPUT_LO = (v[0]) | (v[1] << 8) | (v[2] << 16) | (v[3] << 24);
    IMC_V_INPUT_HI = (v[4]) | (v[5] << 8) | (v[6] << 16) | (v[7] << 24);
    
    for(volatile int d=0; d<10; d++); // Hardware settle delay

    // Read and Correct
    for (int r = 0; r < 8; r++) {
        int w_row = r_start + r;
        if (w_row < rows) {
            uint32_t raw_current = IMC_RESULT(r);
            int32_t true_mac = (int32_t)raw_current - (128 * (int32_t)sum_v);
            out[w_row] += true_mac;
        }
    }
}

static void imc_layer_execution(const int8_t *W, const uint8_t *inp, int32_t *out, int rows, int cols) {
    for (int r = 0; r < rows; r++) out[r] = 0;
    for (int cs = 0; cs < cols; cs += 8) {
        for (int rs = 0; rs < rows; rs += 8) {
            imc_tile_mac(W, rows, cols, inp, out, rs, cs);
        }
    }
}

static int infer_imc(const uint8_t *img) {
    imc_layer_execution(w1_int8, img, hidden_acc, HIDDEN_SIZE, INPUT_SIZE);
    for (int i = 0; i < HIDDEN_SIZE; i++) {
        int32_t v = hidden_acc[i] + b1_int32[i];
        if (v < 0) v = 0; 
        v /= H_DIV;       
        hidden_act[i] = (v > 127) ? (int8_t)127 : (int8_t)v;
    }

    imc_layer_execution(w2_int8, (const uint8_t*)hidden_act, output_acc, OUTPUT_SIZE, HIDDEN_SIZE);
    for (int i = 0; i < OUTPUT_SIZE; i++) {
        output_acc[i] += b2_int32[i];
    }
    return argmax(output_acc, OUTPUT_SIZE);
}

// ==========================================
// Main Execution
// ==========================================
int main(void) {
    printf("\n========================================================\n");
    printf(" CPU vs ReRAM IMC (8x8) Inference Benchmark\n");
    printf("========================================================\n\n");

    uint32_t total_cpu_cycles = 0;
    uint32_t total_imc_cycles = 0;
    int cpu_correct = 0;
    int imc_correct = 0;

    printf("%-5s | %-5s | %-12s | %-12s | %-8s\n", "Image", "Label", "CPU Cycles", "IMC Cycles", "Match?");
    printf("--------------------------------------------------------\n");

    for (int d = 0; d < NUM_TEST_IMAGES; d++) {
        int label = test_labels[d];

        // CPU Inference
        uint32_t t0 = read_cycles();
        int pred_cpu = infer_cpu(test_images[d]);
        uint32_t cpu_cyc = read_cycles() - t0;
        
        // IMC Inference
        t0 = read_cycles();
        int pred_imc = infer_imc(test_images[d]);
        uint32_t imc_cyc = read_cycles() - t0;

        total_cpu_cycles += cpu_cyc;
        total_imc_cycles += imc_cyc;

        if (pred_cpu == label) cpu_correct++;
        if (pred_imc == label) imc_correct++;

        printf("  %d   |   %d   | %-12u | %-12u | %s\n", 
               d, label, cpu_cyc, imc_cyc, 
               (pred_cpu == pred_imc) ? "YES" : "NO");
    }

    printf("--------------------------------------------------------\n");
    printf("\nRESULTS:\n");
    printf("  CPU Accuracy: %d/10\n", cpu_correct);
    printf("  IMC Accuracy: %d/10\n", imc_correct);
    printf("  Avg CPU Cycles: %u\n", total_cpu_cycles / 10);
    printf("  Avg IMC Cycles: %u\n", total_imc_cycles / 10);
    printf("\n========================================================\n\n");

    while(1);
    return 0;
}
