ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0, LENGTH = 16K }
SECTIONS {
    .text : { *(.text.start) *(.text*) } > ram
    .rodata : { *(.rodata*) } > ram
    .data : { *(.data*) *(.sdata*) } > ram
    .bss : { *(.bss*) *(.sbss*) *(COMMON) } > ram
    _end = .;
    _stack_top = ORIGIN(ram) + LENGTH(ram);
    ASSERT(_end < _stack_top - 2048, "Firmware leaves insufficient stack")
}
