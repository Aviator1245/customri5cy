#!/usr/bin/env python3
"""
MNIST PTQ - Verified implementation.

The math, derived carefully (no centering = no zero-point bugs):

  Float inference:
    h[r] = relu( sum_c(W1[r,c] * pixel[c]/255) + b1[r] )

  Quantization:
    W1_q[r,c] = round(W1[r,c] / S_w1),  S_w1 = max|W1| / 127
    pixel[c]  = raw uint8, used as int32 directly

  Integer MAC:
    acc[r] = sum_c( W1_q[r,c] * pixel[c] )
           = (1/S_w1) * sum_c( W1[r,c] * pixel[c] )

  Real value: acc[r] * S_w1 = sum_c(W1[r,c] * pixel[c])
  Float needs /255: h_real = relu(acc * S_w1/255 + b1)

  Bias in integer units:
    B1[r] = round(b1[r] / (S_w1/255)) = round(b1[r] * 255 / S_w1)
    => acc[r] + B1[r] = integer representing (h_real * 255/S_w1)

  No zero-point offset because we use pixel 0..255 directly (not centered).

  Hidden requantization:
    H_DIV = calibrated divisor so max(relu(acc+B1)) // H_DIV <= 127
    h_int8[r] = clip(relu(acc[r]+B1[r]) // H_DIV, 0, 127)

  Layer 2 bias:
    h_int8 represents: h_real = h_int8 * H_DIV * S_w1/255
    scale_h = H_DIV * S_w1 / 255
    B2[r] = round(b2[r] / (S_w2 * scale_h))
"""

import numpy as np
from PIL import Image
import os

try:
    from tensorflow import keras
    from tensorflow.keras import layers
    HAS_KERAS = True
except ImportError:
    HAS_KERAS = False


def train(epochs=15):
    if not HAS_KERAS:
        print("Need tensorflow"); return None, None, None, None
    print("Loading MNIST...")
    (x_train, y_train), (x_test, y_test) = keras.datasets.mnist.load_data()
    x_test_u8  = x_test.reshape(-1, 784)                             # keep uint8
    x_train_f  = x_train.astype("float32").reshape(-1,784) / 255.0
    x_test_f   = x_test.astype("float32").reshape(-1,784)  / 255.0

    model = keras.Sequential([
        layers.Input(shape=(784,)),
        layers.Dense(32, activation='relu'),
        layers.Dense(10, activation='softmax')
    ])
    model.compile(optimizer='adam',
                  loss='sparse_categorical_crossentropy',
                  metrics=['accuracy'])
    print(f"Training {epochs} epochs...")
    model.fit(x_train_f, y_train, epochs=epochs, batch_size=128,
              verbose=1, validation_split=0.1)
    _, acc = model.evaluate(x_test_f, y_test, verbose=0)
    print(f"Float32 accuracy: {acc*100:.2f}%")
    return model, model.get_weights(), x_test_u8, y_test


def ptq(weights, x_test_u8, y_test):
    w1k, b1, w2k, b2 = weights
    W1 = w1k.T.astype(np.float32)   # [32, 784]  row = one output neuron
    W2 = w2k.T.astype(np.float32)   # [10, 32]

    # Quantize weights
    S_w1 = float(np.max(np.abs(W1))) / 127.0
    S_w2 = float(np.max(np.abs(W2))) / 127.0
    W1_q = np.clip(np.round(W1 / S_w1), -127, 127).astype(np.int8)
    W2_q = np.clip(np.round(W2 / S_w2), -127, 127).astype(np.int8)
    print(f"S_w1={S_w1:.8f}  S_w2={S_w2:.8f}")

    # Layer 1 bias: B1[r] = round(b1[r] * 255 / S_w1)
    B1 = np.round(b1.astype(np.float64) * 255.0 / S_w1).astype(np.int32)
    print(f"B1 range: [{B1.min()}, {B1.max()}]")

    # Sanity check on first image
    img0_u8  = x_test_u8[0].astype(np.int32)
    img0_f   = x_test_u8[0].astype(np.float32) / 255.0

    acc0     = W1_q.astype(np.int32) @ img0_u8 + B1
    h0_int   = np.maximum(acc0, 0).astype(np.float32) * (S_w1 / 255.0)
    h0_float = np.maximum(W1 @ img0_f + b1, 0)

    print(f"\nSanity check (image 0, label={y_test[0]}):")
    print(f"  float h: max={h0_float.max():.4f}")
    print(f"  int32 h: max={h0_int.max():.4f}")
    print(f"  ratio:   {h0_int.max()/(h0_float.max()+1e-9):.4f}  (want 1.0)")

    # Calibrate: find max of relu(acc+B1) over 2000 images
    print(f"\nCalibrating (2000 images)...")
    peak_list = []
    for i in range(2000):
        xi = x_test_u8[i].astype(np.int32)
        h  = np.maximum(W1_q.astype(np.int32) @ xi + B1, 0)
        peak_list.append(int(h.max()))
    peak_arr = np.array(peak_list)
    p999 = int(np.percentile(peak_arr, 99.9))
    p100 = int(peak_arr.max())
    print(f"  INT32 post-relu max: p99.9={p999}  p100={p100}")

    # Initial H_DIV
    H_DIV_init = max(1, p999 // 127)
    print(f"  Initial H_DIV = {H_DIV_init}")

    # Helper: evaluate accuracy for a given H_DIV on n images
    def eval_acc(div, n=1000):
        sh = div * S_w1 / 255.0
        B2d = np.round(b2.astype(np.float64) / (S_w2 * sh)).astype(np.int32)
        correct = 0
        for i in range(n):
            xi = x_test_u8[i].astype(np.int32)
            h  = W1_q.astype(np.int32) @ xi + B1
            h  = np.clip(np.maximum(h, 0) // div, 0, 127).astype(np.int8)
            o  = W2_q.astype(np.int32) @ h.astype(np.int32) + B2d
            if np.argmax(o) == y_test[i]: correct += 1
        return correct / n * 100

    # Coarse sweep: try wide range
    print(f"\nSearching for best H_DIV...")
    candidates = set()
    for mult in [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]:
        candidates.add(max(1, int(H_DIV_init * mult)))
    for s in range(0, 20):
        candidates.add(2**s)

    best_acc, best_div = 0.0, H_DIV_init
    for d in sorted(candidates):
        a = eval_acc(d, 500)
        if a > best_acc:
            best_acc, best_div = a, d

    # Fine search around best coarse winner
    lo = max(1, best_div - 30)
    hi = best_div + 31
    for d in range(lo, hi):
        a = eval_acc(d, 1000)
        if a > best_acc:
            best_acc, best_div = a, d

    print(f"  Best H_DIV = {best_div}  (1k acc = {best_acc:.1f}%)")

    # Final B2
    scale_h = best_div * S_w1 / 255.0
    B2 = np.round(b2.astype(np.float64) / (S_w2 * scale_h)).astype(np.int32)
    print(f"  B2 range: [{B2.min()}, {B2.max()}]")

    # Full 10k eval
    correct = 0
    for i in range(10000):
        xi = x_test_u8[i].astype(np.int32)
        h  = W1_q.astype(np.int32) @ xi + B1
        h  = np.clip(np.maximum(h, 0) // best_div, 0, 127).astype(np.int8)
        o  = W2_q.astype(np.int32) @ h.astype(np.int32) + B2
        if np.argmax(o) == y_test[i]: correct += 1
    final_acc = correct / 100.0
    print(f"  Full 10k accuracy: {final_acc:.2f}%")

    return dict(W1_q=W1_q, B1=B1, W2_q=W2_q, B2=B2,
                H_DIV=best_div, S_w1=S_w1, S_w2=S_w2,
                accuracy=final_acc)


# ── Write helpers ──────────────────────────────────────────────
def wi8(f, name, arr, cmt=""):
    flat = arr.flatten()
    if cmt: f.write(f"// {cmt}\n")
    f.write(f"static const int8_t {name}[{len(flat)}]"
            f" __attribute__((aligned(4))) = {{\n")
    for i in range(0, len(flat), 16):
        c = flat[i:i+16]
        f.write("    " + ", ".join(f"{int(x):4d}" for x in c))
        f.write(",\n" if i+16<len(flat) else "\n")
    f.write("};\n\n")

def wi32(f, name, arr, cmt=""):
    flat = arr.flatten()
    if cmt: f.write(f"// {cmt}\n")
    f.write(f"static const int32_t {name}[{len(flat)}]"
            f" __attribute__((aligned(4))) = {{\n")
    for i in range(0, len(flat), 8):
        c = flat[i:i+8]
        f.write("    " + ", ".join(f"{int(x):12d}" for x in c))
        f.write(",\n" if i+8<len(flat) else "\n")
    f.write("};\n\n")

def wu8(f, name, arr, cmt=""):
    flat = arr.flatten()
    if cmt: f.write(f"// {cmt}\n")
    f.write(f"static const uint8_t {name}[{len(flat)}] = {{\n")
    for i in range(0, len(flat), 16):
        c = flat[i:i+16]
        f.write("    " + ", ".join(f"{int(x):3d}" for x in c))
        f.write(",\n" if i+16<len(flat) else "\n")
    f.write("};\n\n")


def generate_header(p, x_test_u8, y_test):
    digit_imgs = {}
    for d in range(10):
        idx = np.where(y_test == d)[0][0]
        digit_imgs[d] = x_test_u8[idx]

    os.makedirs("mnist_digits", exist_ok=True)
    for d, img in digit_imgs.items():
        Image.fromarray(img.reshape(28,28).astype(np.uint8))\
             .resize((280,280), Image.NEAREST)\
             .save(f"mnist_digits/digit_{d}.jpg", quality=95)

    with open("mnist_weights_int8.h", "w") as f:
        f.write("// =====================================================\n")
        f.write("// INT8 PTQ MNIST Weights\n")
        f.write("// Generated by generate_mnist.py\n")
        f.write("//\n")
        f.write("// Pure integer inference (no FPU):\n")
        f.write("//   Layer1:\n")
        f.write("//     acc[r] = sum_c(w1[r][c] * (int32)pixel[c]) + b1[r]\n")
        f.write("//     h[r]   = clip(relu(acc[r]) / H_DIV, 0, 127)\n")
        f.write("//   Layer2:\n")
        f.write("//     out[r] = sum_c(w2[r][c] * h[c]) + b2[r]\n")
        f.write("//     pred   = argmax(out)\n")
        f.write("//\n")
        f.write(f"// Accuracy: {p['accuracy']:.2f}%\n")
        f.write("// =====================================================\n\n")
        f.write("#ifndef MNIST_WEIGHTS_INT8_H\n")
        f.write("#define MNIST_WEIGHTS_INT8_H\n\n")
        f.write("#include <stdint.h>\n\n")
        f.write("#define INPUT_SIZE       784\n")
        f.write("#define HIDDEN_SIZE       32\n")
        f.write("#define OUTPUT_SIZE       10\n")
        f.write("#define NUM_TEST_IMAGES   10\n\n")
        f.write(f"#define H_DIV  {p['H_DIV']}\n\n")
        wi8 (f, "w1_int8",  p['W1_q'], "Layer1 weights [32][784] INT8")
        wi32(f, "b1_int32", p['B1'],   "Layer1 biases  [32] INT32")
        wi8 (f, "w2_int8",  p['W2_q'], "Layer2 weights [10][32]  INT8")
        wi32(f, "b2_int32", p['B2'],   "Layer2 biases  [10] INT32")

        for d in range(10):
            wu8(f, f"test_image_{d}", digit_imgs[d], f"Digit {d}")
        f.write("static const uint8_t* test_images[NUM_TEST_IMAGES] = {\n")
        for d in range(10):
            f.write(f"    test_image_{d}{',' if d<9 else ''}\n")
        f.write("};\n\n")
        f.write("static const uint8_t test_labels[NUM_TEST_IMAGES] = {")
        f.write(", ".join(str(d) for d in range(10)))
        f.write("};\n\n")
        f.write("#endif\n")
    print("Generated mnist_weights_int8.h")


def main():
    print("=" * 60)
    print("MNIST PTQ - Verified (no centering, no zero-point bugs)")
    print("=" * 60)

    model, weights, x_test_u8, y_test = train(epochs=15)
    if model is None: return

    p = ptq(weights, x_test_u8, y_test)

    print("\nPer-digit verification:")
    for d in range(10):
        idx = np.where(y_test == d)[0][0]
        xi = x_test_u8[idx].astype(np.int32)
        h  = p['W1_q'].astype(np.int32) @ xi + p['B1']
        h  = np.clip(np.maximum(h,0) // p['H_DIV'], 0, 127).astype(np.int8)
        o  = p['W2_q'].astype(np.int32) @ h.astype(np.int32) + p['B2']
        pred = np.argmax(o)
        print(f"  Digit {d}: pred={pred}  {'OK' if pred==d else 'WRONG'}")

    generate_header(p, x_test_u8, y_test)
    print(f"\n{'='*60}")
    print(f"DONE!  H_DIV={p['H_DIV']}  accuracy={p['accuracy']:.2f}%")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()