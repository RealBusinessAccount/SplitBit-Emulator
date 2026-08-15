; Tests that the CPU stops when it meets a byte it cannot decode.
;
; 0xFE is not an instruction. Placing it in the Program Segment as a literal gets
; it past the assembler, which is the only way to build a program containing one.
;
; The CPU should raise the Fault Flag, halt, and leave the Program Counter pointing
; at the offending byte rather than stepping over it and carrying on. The emulator
; then reports what it was and where, and exits non zero.

#Program

start:
  INIA 0d65     ; Something harmless first, so the fault is not at address zero.
  0xFE          ; Not an instruction.
  HALT          ; Never reached.
