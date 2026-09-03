# 🇮🇷 Bare-Metal ARM Assembly Iranian Flag Renderer

[![Language: ARM Assembly](https://img.shields.io/badge/Language-ARMv7_Assembly-red.svg?style=for-the-badge)](https://developer.arm.com/documentation/)
[![Target: Framebuffer](https://img.shields.io/badge/Target-Memory--Mapped_Framebuffer-blue.svg?style=for-the-badge)]()
[![Platform: CPUlator / DE1-SoC](https://img.shields.io/badge/Platform-CPUlator_%2F_DE1--SoC-green.svg?style=for-the-badge)](https://cpulator.01xz.net/)

A bare-metal ARMv7 assembly program that renders the tri-color flag of Iran directly into a memory-mapped VGA pixel buffer (framebuffer) using direct word-aligned memory writes.

---

## 📌 Architecture & Display Specifications

- **Base Framebuffer Address:** `0xC8000000`
- **Color Depth:** 16-bit RGB565 (Packed 2 pixels per 32-bit register)
- **Pixel Stride:** 4 bytes per double-pixel word write (`ADD r0, r0, #4`)

### Memory Mapping & Stripe Boundaries

| Stripe | Color | 32-bit Packed Hex | Start Address | End Boundary |
| :--- | :--- | :--- | :--- | :--- |
| **Top** | Green | `0x0FE00FE0` | `0xC8000000` | `0xC8015000` |
| **Middle** | White | `0xFFFFFFFF` | `0xC8015000` | `0xC8029000` |
| **Bottom** | Red | `0xF800F800` | `0xC8029000` | `0xC8045000` |

---

## 🔄 Algorithm & Execution Logic

1. **Base Initialization:** Loads the base memory-mapped framebuffer pointer (`0xC8000000`) into register `r0`.
2. **Stripe 1 (Green):** Loads packed 32-bit green color code and loop-writes sequentially until address reaches `0xC8015000`.
3. **Stripe 2 (White):** Loads packed 32-bit white color code and continues writing sequentially until `0xC8029000`.
4. **Stripe 3 (Red):** Loads packed 32-bit red color code and fills the remaining display memory up to `0xC8045000`.

---

## 🚀 How to Run

### Method 1: In CPUlator Simulator (Recommended)
1. Open the [CPUlator ARMv7 Simulator](https://cpulator.01xz.net/?sys=arm-de10-lite).
2. Set architecture/system to **ARMv7 DE1-SoC** or **ARMv7 DE10-Lite**.
3. Paste the contents of `flag.s` into the editor.
4. Click **Compile and Load**, then hit **Run (F5)**.
5. Inspect the rendered flag output in the **VGA Pixel Buffer Display** window.

### Method 2: GNU ARM Embedded Toolchain
Assemble and link into an ELF binary:
```bash
arm-none-eabi-as -mcpu=cortex-a9 flag.s -o flag.o
arm-none-eabi-ld -Ttext 0x00000000 flag.o -o flag.elf
