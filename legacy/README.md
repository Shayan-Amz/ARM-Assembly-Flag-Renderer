# legacy/

`Flag.s` is the **original course submission** (Computer Architecture lab, Semnan University),
kept verbatim except for line-ending normalisation. It draws the flag correctly enough to look
right on screen, which is exactly why its defects are instructive — none of them is visible
without measuring:

| Defect | Evidence (`make legacy`) | Fix in `src/flag.s` |
|--------|--------------------------|---------------------|
| Stripe boundaries are byte addresses (`0xC8015000`, `0xC8029000`) that do not fall on multiples of 80 rows | stripes are **84 / 80 / 76** rows | heights expressed in rows; addresses derived from `y << 10` |
| The last loop runs to `0xC8045000`, past the end of the 240 KiB frame (`0xC803C000`) and past the 256 KiB of pixel memory | 9 216 out-of-bounds stores | loop bounds derived from `HEIGHT` |
| No halt after the last stripe — execution falls through into the literal pool and executes data | emulator: undefined-instruction exception at `pc = 0x60`; CPUlator: "executing data" warning | `halt: b halt` |
| All 1024 bytes of every row are written although only 640 are visible | 46 080 wasted pixel stores (38 % of the work), 353 k instructions | inner loop covers 320 pixels, then skips the 384-byte pad; 116 k instructions |
| `0x0FE0` sets bit 11, which is the least-significant **red** bit, not green | — | `0x07E0` |
| `BEQ exit` / `BAL loop` pair where a single `BNE loop` suffices; `STR r0, [r0]` has no purpose | — | `subs` + `bne` loops |

The program is still assembled by the Makefile (`build/legacy.bin`) so the comparison in the
main README can be reproduced.
