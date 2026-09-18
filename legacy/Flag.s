.global _start
.equ endlist1, 0xc8015000   // End of first stripe
.equ endlist2, 0xc8029000   // End of second stripe
.equ endlist3, 0xc8045000   // End of third stripe
.equ green, 0x0fe00fe0
.equ white, 0xffffffff
.equ red, 0xf800f800
_start:
  MOV r0, #0xc8000000      // Base address of framebuffer
  STR r0, [r0]            // Initialize framebuffer

  // First stripe (green)
  LDR r1, =green      // Green color value
  LDR r3, =endlist1
loop1:
  STR r1, [r0]            // Store color value in framebuffer
  ADD r0, r0, #4          // Move to next pixel
  CMP r0, r3
  BEQ exit1
  BAL loop1

exit1:

  // Second stripe (white)
  LDR r1, =white      // White color value
  LDR r3, =endlist2
loop2:
  STR r1, [r0]
  ADD r0, r0, #4
  CMP r0, r3
  BEQ exit2
  BAL loop2

exit2:

  // Third stripe (red)
  LDR r1, =red      // Red color value
  LDR r3, =endlist3
loop3:
  STR r1, [r0]
  ADD r0, r0, #4
  CMP r0, r3
  BEQ exit3
  BAL loop3
exit3: