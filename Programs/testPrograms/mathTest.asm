; A test for the new math subroutines.

#Include ../Libraries/print.asm
#Include ../Libraries/int8.asm
#Include ../Libraries/int16.asm

#Program
 start:
  SETD SomeInt16Operands
  CALL int16div
  LDA
  CALL printByteHex
  INCD
  LDA
  CALL printByteHex
  CALL blankSpace
  INCD
  LDA
  CALL printByteHex
  INCD
  LDA
  CALL printByteHex
 end:
  CALL lineFeed
  HALT

#Data

SomeInt16Operands:
  0x01 0xF4
  0x00 0x0A
