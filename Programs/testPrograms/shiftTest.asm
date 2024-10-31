; A simple test for the new SHL and SHR instructions.

#Include print.asm

#Program

start:
  SETD String0
  CALL printString
 loop0:
  SETD TestValue0
  CALL printDecimal
  LDA
  SHL
  STA
  SETD Space
  CALL printString
  BRA doB
  BRI loop0
 doB:
  CALL lineFeed
  SETD String1
  CALL printString
  SETD TestValue0
  STB
 loop1:
  SETD TestValue0
  CALL printDecimal
  LDB
  SHL
  STB
  SETD Space
  CALL printString
  BRB doRight
  BRA loop1
 doRight:
  CALL lineFeed
  SETD String0
  CALL printString
 loop2:
  SETD TestValue1
  CALL printDecimal
  LDA
  SHR
  STA
  SETD Space
  CALL printString
  BRA doRightB
  BRI loop2
 doRightB:
  CALL lineFeed
  SETD String1
  CALL printString
  SETD TestValue1
  STB
 loop3:
  SETD TestValue1
  CALL printDecimal
  LDB
  SHR
  STB
  SETD Space
  CALL printString
  BRB end
  BRA loop3
 end:
  CALL lineFeed
  HALT

#Data
TestValue0:
  0d01

TestValue1:
  0d128

String0:
 "A values: "

String1:
 "B values: "

Space:
 " "
