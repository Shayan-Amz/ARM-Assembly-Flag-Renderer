@ flag.s — draw the tricolour flag of Iran into the DE1-SoC VGA pixel buffer.
@
@ Target : ARMv7-A (Cortex-A9) bare metal — DE1-SoC Computer / CPUlator "ARMv7 DE1-SoC"
@ Build  : make            (GNU arm-none-eabi or zig; see Makefile)
@ Run    : paste into CPUlator, "Compile and Load", F5 — or  make run  (Unicorn emulator)
@
@ Display geometry (Intel FPGA University Program "DE1-SoC Computer" manual, §Pixel Buffer):
@
@     pixel (x, y)  lives at  PIXEL_BUFFER | (y << 10) | (x << 1)
@
@   i.e. 16-bit RGB565 pixels, 320 visible columns per row, but a row *stride* of
@   1024 bytes (512 pixel slots, of which only 320 are shown) and 240 rows.
@   The buffer therefore spans 0xC8000000 .. 0xC803BFFF (240 KiB).
@
@ Program structure:
@   _start        sets up a stack, walks a table of (colour, height) stripes and
@                 calls fill_rows for each one, then halts.
@   fill_rows     AAPCS-conforming leaf routine: fill `rows` whole rows starting at
@                 `dst` with the 16-bit `colour`, writing only the 320 visible pixels.
@
@ Colours are RGB565:  RRRRR GGGGGG BBBBB  (5 red, 6 green, 5 blue bits).

        .syntax unified
        .arch   armv7-a
        .cpu    cortex-a9
        .arm

@ ---------------------------------------------------------------- constants --
        .equ    PIXEL_BUFFER, 0xC8000000    @ DE1-SoC pixel buffer base
        .equ    WIDTH,        320           @ visible pixels per row
        .equ    HEIGHT,       240           @ rows
        .equ    STRIDE,       1024          @ bytes between consecutive rows (y << 10)
        .equ    BYTES_PP,     2             @ bytes per pixel (RGB565)
        .equ    ROW_BYTES,    WIDTH * BYTES_PP           @ 640 visible bytes per row
        .equ    ROW_PAD,      STRIDE - ROW_BYTES         @ 384 invisible bytes per row

        .equ    STACK_TOP,    0x3FFFFFFC    @ top of the 1 GiB SDRAM on the DE1-SoC

        @ RGB565 colours
        .equ    GREEN,        0x07E0        @ R=0  G=63 B=0
        .equ    WHITE,        0xFFFF        @ R=31 G=63 B=31
        .equ    RED,          0xF800        @ R=31 G=0  B=0

        .equ    STRIPE_ROWS,  HEIGHT / 3    @ 80 rows per stripe

@ ------------------------------------------------------------------ program --
        .text
        .global _start
        .type   _start, %function
_start:
        ldr     sp, =STACK_TOP              @ a valid stack is required before any BL

        ldr     r4, =PIXEL_BUFFER           @ r4 = destination of the next stripe
        ldr     r5, =stripes                @ r5 = table cursor
        ldr     r6, =stripes_end

draw_next_stripe:
        ldrh    r1, [r5], #2                @ r1 = colour            (arg 2)
        ldrh    r2, [r5], #2                @ r2 = number of rows    (arg 3)
        mov     r0, r4                      @ r0 = destination       (arg 1)
        bl      fill_rows                   @ r0 returns the address of the next row
        mov     r4, r0
        cmp     r5, r6
        blo     draw_next_stripe            @ unsigned compare: addresses may exceed 0x7FFFFFFF

halt:                                       @ bare metal has nowhere to return to:
        b       halt                        @ spin here (CPUlator shows the finished frame)
        .size   _start, . - _start

@ ---------------------------------------------------------------------------
@ fill_rows — fill whole rows of the pixel buffer with one colour.
@
@   r0  dst     address of the first pixel of the first row (must be row-aligned)
@   r1  colour  16-bit RGB565 value
@   r2  rows    number of rows to fill (0 is allowed)
@   →   r0      address of the row after the last one filled
@
@ Two pixels are packed into one 32-bit word so every store writes 4 bytes; the
@ inner loop therefore runs WIDTH/2 = 160 times per row.  Only r0–r3 are used, so
@ no registers need to be preserved (AAPCS: r0–r3 are caller-saved scratch).
@ ---------------------------------------------------------------------------
        .global fill_rows
        .type   fill_rows, %function
fill_rows:
        orr     r1, r1, r1, lsl #16         @ r1 = colour:colour (two pixels per word)
        cmp     r2, #0
        bxeq    lr                          @ nothing to do
.Lrow:
        mov     r3, #WIDTH / 2              @ words per visible row
.Lpixels:
        str     r1, [r0], #4                @ store two pixels, post-increment
        subs    r3, r3, #1
        bne     .Lpixels
        add     r0, r0, #ROW_PAD            @ skip the invisible remainder of the row
        subs    r2, r2, #1
        bne     .Lrow
        bx      lr
        .size   fill_rows, . - fill_rows

@ --------------------------------------------------------------------- data --
@ Stripe table: (colour, rows) halfword pairs, top to bottom.  Editing this table
@ is all it takes to draw a different horizontal tricolour.
        .section .rodata
        .align  2
stripes:
        .hword  GREEN, STRIPE_ROWS
        .hword  WHITE, STRIPE_ROWS
        .hword  RED,   STRIPE_ROWS
stripes_end:

        .end
