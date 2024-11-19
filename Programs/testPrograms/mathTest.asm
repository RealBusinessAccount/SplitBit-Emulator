; A test for the new math subroutines.

#Include ../Libraries/print.asm
#Include ../Libraries/math.asm

#Program
 start:
  SETD SomeInt16Operands
  CALL int16sub
  BRC end
  LDA
  CALL printByteHex
  INCD
  LDA
  CALL printByteHex
  INIA 0x3A
  OUTA 0x00
  BRI start
 end:
  CALL lineFeed
  HALT

#Data

SomeInt16Operands:
  0xFF 0xFF
  0x00 0x01
