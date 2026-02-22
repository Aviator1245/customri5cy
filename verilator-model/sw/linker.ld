ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80, LENGTH = 1M
}

SECTIONS
{
    .vectors 0x80 : {
        KEEP(*(.vectors))
    } > RAM

    .text : {
        *(.text*)
    } > RAM

    .rodata : {
        *(.rodata*)
    } > RAM

    .data : {
        *(.data*)
    } > RAM

    .bss : {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > RAM

    . = ALIGN(4);
    _end = .;
    
    /* Provide heap start */
    __heap_start = .;

    /* Global pointer */
    __global_pointer$ = 0x880;
}
