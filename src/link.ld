/* Bare-metal link script for the DE1-SoC / CPUlator: code at address 0 (reset vector). */
ENTRY(_start)
MEMORY
{
  SDRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x40000000
}
SECTIONS
{
  .text : { *(.text*) *(.rodata*) } > SDRAM
  .data : { *(.data*) } > SDRAM
  .bss  : { *(.bss*) }  > SDRAM
  /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) }
}
