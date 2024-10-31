; Tests for the printing subroutines provided by print.asm

#Include ../Libraries/print.asm
#Include printDigitTest.asm
#Include printDecimalTest.asm
#Include printHexTest.asm

#Program

clearRegisters:
  INIA 0x00;
  INIB 0x00;
  ADD
  RET

start:
  SETD String0
  CALL printString
  CALL lineFeed
  SETD String1
  CALL printString
  CALL lineFeed
  CALL clearRegisters
  CALL printDigitTest
  CALL lineFeed
  SETD String2
  CALL printString
  CALL lineFeed
  CALL clearRegisters
  CALL printByteDecimalTest
  CALL lineFeed
  SETD String3
  CALL printString
  CALL lineFeed
  CALL clearRegisters
  CALL printByteHexTest
  CALL lineFeed
  SETD String4
  CALL printString
  CALL lineFeed
  HALT

#Data

String0:
"Test suite for SplitBit's print.asm library."

String1:
"Testing printDigit..."

String2:
"Testing printByteDecimal..."

String3:
"Testing printByteHex..."

String4:
"Testing complete!"
