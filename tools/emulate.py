#!/usr/bin/env python3
"""Run a bare-metal DE1-SoC flag program in an ARM emulator and check the result.

The program is executed with Unicorn (QEMU's CPU core as a library) on a machine
model that mirrors what matters on the DE1-SoC Computer / CPUlator:

    0x00000000 .. 0x3FFFFFFF   SDRAM      (code is loaded at 0, the reset vector)
    0xC8000000 .. 0xC803FFFF   VGA pixel buffer memory (240 KiB used by the frame)

Every store outside the *visible* 320x240 frame is recorded; writes past the end
of the pixel-buffer memory (which the original program performed) are counted as
out-of-bounds.  The visible frame is rendered to a PNG and checked against the
expected stripe layout.

usage:
    tools/emulate.py build/flag.bin [--png docs/figures/flag.png] [--expect 80,80,80]
                     [--legacy]   (the original program never halts: stop when pc leaves the code)

exit status: 0 if all checks pass, 1 otherwise.
"""
from __future__ import annotations

import argparse
import struct
import sys
import zlib

try:
    from unicorn import UC_ARCH_ARM, UC_HOOK_CODE, UC_HOOK_MEM_WRITE, UC_MODE_ARM, Uc, UcError
    from unicorn.arm_const import UC_ARM_REG_PC
except ImportError:  # pragma: no cover
    sys.exit("the 'unicorn' package is required:  pip install unicorn")

PIXEL_BUFFER = 0xC8000000
WIDTH, HEIGHT, STRIDE, BPP = 320, 240, 1024, 2
FRAME_BYTES = HEIGHT * STRIDE                      # 0x3C000
PIXEL_MEMORY_END = PIXEL_BUFFER + 0x40000          # 256 KiB of pixel-buffer memory on the board

GREEN, WHITE, RED = 0x07E0, 0xFFFF, 0xF800
NAMES = {GREEN: "green", 0x0FE0: "green*", WHITE: "white", RED: "red"}


def emulate(binary: bytes, legacy: bool, max_insns: int):
    mu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    mu.mem_map(0x00000000, 0x40000000)             # SDRAM (lazily backed; only touched pages cost memory)
    mu.mem_map(PIXEL_BUFFER, 0x100000)             # pixel memory + slack so overruns are observable
    mu.mem_write(0, binary)

    stats = {"insns": 0, "stores": 0, "visible": 0, "invisible_pad": 0, "out_of_bounds": 0,
             "min_addr": None, "max_addr": None, "halted_at": None, "left_code": False}
    last_pc = {"pc": None, "same": 0}

    def on_code(uc, addr, size, _):
        stats["insns"] += 1
        # A branch-to-self (`b .`) is the idiomatic bare-metal halt: detect pc repeating.
        if addr == last_pc["pc"]:
            last_pc["same"] += 1
            if last_pc["same"] >= 3:
                stats["halted_at"] = addr
                uc.emu_stop()
        else:
            last_pc["pc"], last_pc["same"] = addr, 0
        if legacy and addr >= len(binary) - 20:      # original program: falls into its literal pool
            stats["left_code"] = True
            uc.emu_stop()

    def on_write(uc, access, addr, size, value, _):
        stats["stores"] += 1
        end = addr + size
        stats["min_addr"] = addr if stats["min_addr"] is None else min(stats["min_addr"], addr)
        stats["max_addr"] = end if stats["max_addr"] is None else max(stats["max_addr"], end)
        if end > PIXEL_BUFFER + FRAME_BYTES:
            stats["out_of_bounds"] += 1
        else:
            for a in range(addr, end, BPP):
                x = ((a - PIXEL_BUFFER) % STRIDE) // BPP
                if x < WIDTH:
                    stats["visible"] += 1
                else:
                    stats["invisible_pad"] += 1

    mu.hook_add(UC_HOOK_CODE, on_code)
    mu.hook_add(UC_HOOK_MEM_WRITE, on_write, begin=PIXEL_BUFFER, end=PIXEL_BUFFER + 0x100000)
    try:
        mu.emu_start(0, 0xFFFFFFFF, count=max_insns)
    except UcError as e:
        stats["exception"] = f"{e} at pc=0x{mu.reg_read(UC_ARM_REG_PC):08X}"
    return mu, stats


def frame_pixels(mu):
    fb = bytes(mu.mem_read(PIXEL_BUFFER, FRAME_BYTES))
    return [[struct.unpack_from("<H", fb, y * STRIDE + x * BPP)[0] for x in range(WIDTH)] for y in range(HEIGHT)]


def stripes(pixels):
    """Collapse the frame into runs of uniform rows: [(colour, row_count), ...]."""
    runs = []
    for row in pixels:
        colour = row[0] if all(p == row[0] for p in row) else None
        if runs and runs[-1][0] == colour:
            runs[-1][1] += 1
        else:
            runs.append([colour, 1])
    return [(c, n) for c, n in runs]


def write_png(pixels, path):
    def rgb(p):
        return ((p >> 11 & 31) * 255 // 31, (p >> 5 & 63) * 255 // 63, (p & 31) * 255 // 31)

    raw = b"".join(b"\x00" + bytes(v for p in row for v in rgb(p)) for row in pixels)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binary", help="flat binary (objcopy -O binary) loaded at address 0")
    ap.add_argument("--png", help="write the rendered frame here")
    ap.add_argument("--expect", default="80,80,80", help="expected stripe heights, top to bottom")
    ap.add_argument("--legacy", action="store_true", help="program has no halt loop; stop when it runs off its code")
    ap.add_argument("--max-insns", type=int, default=2_000_000)
    args = ap.parse_args()

    binary = open(args.binary, "rb").read()
    mu, st = emulate(binary, args.legacy, args.max_insns)
    pixels = frame_pixels(mu)
    runs = stripes(pixels)
    if args.png:
        write_png(pixels, args.png)

    print(f"instructions executed : {st['insns']:,}")
    print(f"stores to pixel memory: {st['stores']:,}  (visible pixels {st['visible']:,}, "
          f"invisible padding {st['invisible_pad']:,}, out of bounds {st['out_of_bounds']:,})")
    if st["min_addr"] is not None:
        print(f"written address range : 0x{st['min_addr']:08X} .. 0x{st['max_addr']:08X}  "
              f"(frame ends at 0x{PIXEL_BUFFER + FRAME_BYTES:08X})")
    print("stripes (colour, rows):", ", ".join(f"{NAMES.get(c, hex(c) if c is not None else 'mixed')}×{n}" for c, n in runs))
    if st["halted_at"] is not None:
        print(f"halted                : yes, spinning at pc=0x{st['halted_at']:08X}")
    elif st["left_code"]:
        print("halted                : NO — execution ran off the end of the code into data")
    else:
        print("halted                : NO —", st.get("exception", "instruction budget exhausted"))

    expected = [int(v) for v in args.expect.split(",")]
    got = [n for _, n in runs]
    ok = True
    if got != expected:
        print(f"FAIL stripe heights {got} != expected {expected}")
        ok = False
    if any(c is None for c, _ in runs):
        print("FAIL some rows are not uniformly coloured")
        ok = False
    if st["out_of_bounds"]:
        print("FAIL program wrote outside the pixel buffer")
        ok = False
    if st["halted_at"] is None:
        print("FAIL program did not reach a halt loop")
        ok = False
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
