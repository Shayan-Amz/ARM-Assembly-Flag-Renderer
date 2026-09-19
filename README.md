# Drawing the flag of Iran in ARM assembly

[![CI](https://github.com/Shayan-Amz/ARM-Assembly-Flag-Renderer/actions/workflows/ci.yml/badge.svg)](https://github.com/Shayan-Amz/ARM-Assembly-Flag-Renderer/actions/workflows/ci.yml)
[![ARMv7-A](https://img.shields.io/badge/ARMv7--A-Cortex--A9-0091BD?logo=arm&logoColor=white)](src/flag.s)
[![Bare metal](https://img.shields.io/badge/bare--metal-DE1--SoC%20%2F%20CPUlator-orange)](https://cpulator.01xz.net/?sys=arm-de1soc)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A bare-metal ARMv7 program that paints the flag of Iran by writing RGB565 pixels straight into the
memory-mapped VGA frame buffer of the **DE1-SoC Computer** (Intel FPGA University Program), the
board used in the Computer Architecture course. There is no operating system underneath it: the
program starts at the reset vector, fills 240 rows of 320 pixels, and stops in a branch-to-self loop.
The whole program — code and data together — is 116 bytes.

<p align="center">
  <img src="docs/figures/flag.png" alt="The flag, rendered from the emulator's frame buffer" width="620">
  <br><sub>The frame written by <code>src/flag.s</code>, rendered to PNG by <code>tools/emulate.py</code>.</sub>
</p>

The repository also contains the small test harness I built to check the output without a board:
it runs the assembled binary under [Unicorn](https://www.unicorn-engine.org/) (QEMU's CPU core),
renders the frame buffer to a PNG and verifies the geometry, the memory accesses and the
termination of the program.

---

## The hardware model

The DE1-SoC Computer exposes its VGA frame as a **pixel buffer** — a region of memory that a DMA
controller scans out continuously. Nothing has to be initialised; writing a halfword puts a dot on
the screen.

```
                31              10 9         1 0
                ┌─────────────────┬───────────┬─┐
  pixel (x, y)  │ 0xC8000000 base │  y        │x│      address = 0xC8000000 | y << 10 | x << 1
                └─────────────────┴───────────┴─┘

  resolution        320 × 240 visible pixels
  pixel format      16-bit RGB565:   R4 R3 R2 R1 R0 | G5 G4 G3 G2 G1 G0 | B4 B3 B2 B1 B0
  row stride        1024 bytes  (= 512 pixel slots; columns 320…511 are never displayed)
  frame size        240 rows × 1024 B = 240 KiB   →  0xC8000000 … 0xC803BFFF
```

The `x << 1 | y << 10` layout is why the stride is 1024 bytes and not 640: the hardware trades 38 %
of the memory for an address computation that is two shifts and an OR instead of a multiply.

Colours are RGB565, so 8-bit channels are converted with `R >> 3`, `G >> 2`, `B >> 3`:

| stripe | RGB565 | R | G | B |
|--------|--------|---|---|---|
| green  | `0x07E0` | 0 | 63 | 0 |
| white  | `0xFFFF` | 31 | 63 | 31 |
| red    | `0xF800` | 31 | 0 | 0 |

---

## The program

[`src/flag.s`](src/flag.s) — 116 bytes of code and data, GNU `as` syntax (`.syntax unified`).

```
_start
  ├─ ldr sp, =STACK_TOP          a stack is required before any BL
  ├─ for each (colour, rows) in stripes:
  │     r0 = dst, r1 = colour, r2 = rows
  │     bl fill_rows             → r0 = address of the next row
  └─ halt:  b halt               bare metal has nowhere to return to

fill_rows (r0 dst, r1 colour, r2 rows) → r0
  orr  r1, r1, r1, lsl #16       pack two pixels per word
  for each row:
      160 ×  str r1, [r0], #4    320 visible pixels, post-indexed store
      add  r0, r0, #384          skip the invisible part of the row
  bx   lr

stripes:  .hword GREEN,80,  WHITE,80,  RED,80      (.rodata — edit this to draw another tricolour)
```

A few things I paid attention to while writing it:

* **Geometry from named constants.** `WIDTH`, `HEIGHT`, `STRIDE` and `HEIGHT / 3` are the only
  numbers that describe the layout, so the stripe boundaries follow from the screen geometry rather
  than from addresses typed by hand.
* **A real subroutine.** `fill_rows` follows the ARM Procedure Call Standard (AAPCS): arguments in
  `r0–r2`, result in `r0`, only caller-saved scratch registers touched, return with `bx lr`. Being a
  leaf routine it needs no stack frame, but `_start` still sets `sp` so the convention holds if the
  routine ever grows.
* **Data-driven.** The stripe table lives in `.rodata`; the code does not know how many stripes
  there are or what colour they have.
* **Unsigned address compares.** Pixel-buffer addresses are above `0x80000000`, so a signed `blt`
  would treat them as negative; the loops use `blo`/`bne` on `subs` instead.
* **Tight inner loop.** Post-indexed stores (`str r1, [r0], #4`) fold the pointer increment into the
  store and `subs … bne` folds the loop test into the decrement — the inner loop is three
  instructions per two pixels.
* **Explicit halt.** After the last stripe the program spins in `b halt`; on bare metal there is no
  caller to return to, and falling through `.text` would run into the literal pool.

---

## Building and running

### In CPUlator (no installation)

1. Open <https://cpulator.01xz.net/?sys=arm-de1soc>.
2. Paste [`src/flag.s`](src/flag.s) into the editor, press **Compile and Load**, then **Run** (F5).
3. The flag appears in the *VGA pixel buffer* device window and the CPU ends up spinning at `halt`.

### With a toolchain

The Makefile uses GNU `arm-none-eabi-{as,ld,objcopy}` when installed and otherwise falls back to
[`zig`](https://ziglang.org) (`pip install ziglang`), whose bundled clang/lld cross-assembles ARM
without any extra packages.

```bash
make                     # build/flag.elf, build/flag.bin
pip install unicorn      # one-off: the emulator used by the test harness
make run                 # emulate, render build/flag.png, verify
make figures             # regenerate docs/figures/flag.png
```

`build/flag.elf` can also be loaded into CPUlator directly (*File → Load executable*), and the flat
`flag.bin` is what a boot ROM would copy to address 0.

---

## Checking the output

[`tools/emulate.py`](tools/emulate.py) builds a minimal machine model — SDRAM at 0 plus the
pixel-buffer memory at `0xC8000000` — executes the binary with Unicorn and checks:

* **geometry** — every row is uniformly coloured and the stripe run-lengths are exactly `80, 80, 80`;
* **memory safety** — no store lands beyond the end of the 240 KiB frame (stores into the invisible
  row padding are counted too);
* **termination** — the program reaches a branch-to-self halt loop instead of executing data or
  exhausting the instruction budget;
* **cost** — the instruction count is reported, which on this simple in-order core is a decent proxy
  for cycles.

The rendered frame is written to `docs/figures/flag.png`. GitHub Actions assembles the program with
**both** toolchains on every push, runs the harness and uploads the frame as a build artifact.

---

## Project structure

```
.
├── src/
│   ├── flag.s            the program (described above)
│   └── link.ld           bare-metal link script: .text at 0x00000000 (reset vector), then .rodata
├── tools/emulate.py      Unicorn-based emulator, PNG renderer and checker
├── docs/figures/         flag.png (the rendered frame)
├── Makefile              toolchain selection (gnu / zig), run and figures targets
├── .github/workflows/ci.yml
└── LICENSE (MIT)
```

---

## Going further

* **Another tricolour** — edit the three `.hword` pairs in `stripes`; the rows need not be equal.
* **Vertical stripes** — a `fill_columns` sibling of `fill_rows` that steps by `STRIDE` in the inner
  loop and by 2 in the outer one.
* **The emblem** — the centre of the flag carries the emblem and the Kufic *takbīr* runs along the
  stripe borders; a 1-bit sprite blitted with `ldrb`/`strh` from a `.rodata` bitmap would add it.
* **Double buffering** — the pixel-buffer DMA controller at `0xFF203020` supports page flipping
  (write the back-buffer address, then write to the *buffer* register to swap on the next vsync),
  which removes tearing for animated content.

---

## References

1. Intel FPGA University Program, *DE1-SoC Computer System with ARM Cortex-A9* — pixel-buffer
   layout, VGA controller registers and memory map.
2. Arm Ltd., *Procedure Call Standard for the Arm Architecture (AAPCS32)*.
3. Arm Ltd., *ARM Architecture Reference Manual, ARMv7-A and ARMv7-R edition* — instruction
   semantics, post-indexed addressing, `subs`/`bne`.
4. H. Wong, [CPUlator Computer System Simulator](https://cpulator.01xz.net/doc/).
5. N. A. Quynh, D. H. Vu, "Unicorn: Next Generation CPU Emulator Framework", Black Hat USA 2015.

---

## License

Released under the [MIT License](LICENSE).
