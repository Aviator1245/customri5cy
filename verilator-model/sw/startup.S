.section .text
.global _start
.global __irq_entry

_start:
    # Set up stack - far from code area
    lui sp, 0xF0        # sp = 0xF0000
    
    # Set up global pointer manually
    lui gp, 0x1         # gp = 0x1000
    addi gp, gp, -0x780 # gp = 0x880
    
    # Zero BSS
    la t0, __bss_start
    la t1, __bss_end
1:
    bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:
    
    # Call main
    jal ra, main
    
    # Hang if main returns
3:
    j 3b

# Exception/Interrupt handler
__irq_entry:
    # Just hang on any exception
    j __irq_entry
