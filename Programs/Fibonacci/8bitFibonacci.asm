; A Fibonacci number generating program that uses only one byte to store the value.

#Include Libraries/print.asm

#Program
start:
  ; Load our initial values into A and B.
  INIA 0x00
  CALL printByteDecimal
  CALL blankSpace
  ; Move the value into B.
  PSHA
  POPB
  ; Load the next starting value into A.
  INIA 0x01
  CALL printByteDecimal
  CALL blankSpace
 loop:
  ADD                       ; Add the values together.
  BRC end                   ; If the value overflows, we're done.
  ; Copy A into B
  PSHA
  POPB
  ; Copy Q into A
  PSHQ
  POPA
  ; Print A.
  CALL printByteDecimal
  CALL blankSpace
  BRI loop                  ; Loop again.
 end:
  CALL lineFeed
  HALT
