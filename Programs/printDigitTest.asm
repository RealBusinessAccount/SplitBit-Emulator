#Include print.asm

#Program

start:
  INIB 0d10
  SETD byte
 loop:
  CALL printDecimalDigit
  LDA
  INCA
  STA
  SUB
  BRQ end
  CALL lineFeed
  BRI loop
 end:
  CALL lineFeed
  HALT

#Data

byte:
0x00
