# Build the flag program for the DE1-SoC (ARMv7-A, bare metal).
#
#   make            build/flag.elf + build/flag.bin  (and the legacy program)
#   make run        assemble, then emulate and verify with tools/emulate.py (needs: pip install unicorn)
#   make figures    re-render docs/figures/flag.png
#   make clean
#
# Toolchain: uses GNU arm-none-eabi-* if present, otherwise `zig` (pip install ziglang,
# or https://ziglang.org) which bundles clang/lld and cross-assembles ARM out of the box.
# Override with  make TOOLCHAIN=gnu  or  make TOOLCHAIN=zig.

BUILD := build
LD_SCRIPT := src/link.ld

ifeq ($(TOOLCHAIN),)
  ifneq ($(shell command -v arm-none-eabi-as 2>/dev/null),)
    TOOLCHAIN := gnu
  else
    TOOLCHAIN := zig
  endif
endif

ifeq ($(TOOLCHAIN),gnu)
  AS      := arm-none-eabi-as
  LD      := arm-none-eabi-ld
  OBJCOPY := arm-none-eabi-objcopy
  OBJDUMP := arm-none-eabi-objdump
  ASFLAGS := -mcpu=cortex-a9 -g
  define assemble_link
	$(AS) $(ASFLAGS) $(1) -o $(2).o
	$(LD) -T $(LD_SCRIPT) $(2).o -o $(2)
  endef
else
  ZIG     ?= $(shell command -v zig 2>/dev/null || echo "python3 -m ziglang")
  OBJCOPY := $(ZIG) objcopy
  OBJDUMP := $(ZIG) objdump
  define assemble_link
	$(ZIG) cc -target arm-freestanding-eabi -mcpu=cortex_a9 -nostdlib -Wl,-T,$(LD_SCRIPT) $(1) -o $(2)
  endef
endif

.PHONY: all run legacy figures clean toolchain

all: $(BUILD)/flag.bin $(BUILD)/legacy.bin

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/flag.elf: src/flag.s $(LD_SCRIPT) | $(BUILD)
	$(call assemble_link,$<,$@)

$(BUILD)/legacy.elf: legacy/Flag.s $(LD_SCRIPT) | $(BUILD)
	$(call assemble_link,$<,$@)

$(BUILD)/%.bin: $(BUILD)/%.elf
	$(OBJCOPY) -O binary $< $@

run: $(BUILD)/flag.bin
	python3 tools/emulate.py $< --png $(BUILD)/flag.png

legacy: $(BUILD)/legacy.bin
	-python3 tools/emulate.py $< --png $(BUILD)/legacy.png --legacy

figures: $(BUILD)/flag.bin
	python3 tools/emulate.py $< --png docs/figures/flag.png

toolchain:
	@echo "TOOLCHAIN=$(TOOLCHAIN)"

clean:
	rm -rf $(BUILD)
