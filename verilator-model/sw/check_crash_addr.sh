#!/bin/bash

cd ~/sandiskhack/ri5cy/verilator-model/sw

echo "=== Checking what's at crash address 0x102 ==="
echo ""

# 0x102 - 0x80 = 0x82 = 130 bytes offset
# So we need bytes 130-133 from firmware.bin

echo "Bytes at offset 130-133 (address 0x102):"
hexdump -C firmware.bin | grep "00000080"
echo ""

echo "Disassembly around 0x102:"
riscv-none-elf-objdump -d firmware.elf | grep -A 10 -B 10 " 102:"
echo ""

echo "Let's check where _write and printf are:"
riscv-none-elf-nm firmware.elf | grep -E "_write|printf|main|_start"
echo ""

echo "Memory map:"
head -50 firmware.map
