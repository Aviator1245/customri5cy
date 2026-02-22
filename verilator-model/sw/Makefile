CC = riscv-none-elf-gcc
OBJCOPY = riscv-none-elf-objcopy
OBJDUMP = riscv-none-elf-objdump
SIZE = riscv-none-elf-size

# Optimized flags for small code size
CFLAGS = -march=rv32im_zicsr -mabi=ilp32 -Os -g -ffreestanding -mno-relax -ffunction-sections -fdata-sections
# Link with newlib for printf
LDFLAGS = -T linker.ld \
          -nostartfiles \
          -Wl,--no-relax \
          -Wl,--gc-sections \
          -Wl,-Map=firmware.map

# Link against newlib's libc and libm
LIBS = -lc -lm -lgcc

TARGET = firmware

all: $(TARGET).hex info

$(TARGET).elf: startup.S hello.c syscalls.c
	$(CC) $(CFLAGS) $^ $(LDFLAGS) $(LIBS) -o $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(TARGET).hex: $(TARGET).bin
	hexdump -v -e '1/1 "%02x\n"' $< > $@
	cp $@ ../firmware.hex

info: $(TARGET).elf $(TARGET).bin
	@echo ""
	@echo "=== Firmware Info ==="
	@$(SIZE) $(TARGET).elf
	@echo ""
	@echo "Binary size: $$(stat -f%z $(TARGET).bin 2>/dev/null || stat -c%s $(TARGET).bin) bytes"
	@echo "Hex lines: $$(wc -l < $(TARGET).hex)"
	@echo ""

disasm: $(TARGET).elf
	$(OBJDUMP) -d $< > $(TARGET).dis
	@echo "Disassembly saved to $(TARGET).dis"

clean:
	rm -f *.elf *.bin *.hex *.dis *.map

.PHONY: all info disasm clean
