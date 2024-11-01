; A Fibonacci number generating program that uses two bytes to store the value.

#Include Libraries/print.asm

#Program
start:
  ; Swap ValueB and ValueA.
  ; First, store ValueA on the stack.
  SETD ValueA
  LDA
  PSHA
  INCD
  LDA
  PSHA
  ; Now copy ValueB into AB.
  SETD ValueB
  LDA ; High byte
  INCD
  LDB ; Low byte
  ; Now save it back to ValueA
  SETD ValueA
  STA ; High byte
  INCD
  STB ; Low byte.
  ; Now retrieve value A from the stack and store it in ValueB.
  POPB
  POPA
  SETD ValueB
  STA
  INCD
  STB
  ; Print ValueA.
  SETD ValueA
  LDA
  CALL printByteHex
  INCD
  LDA
  CALL printByteHex
  CALL blankSpace
  ; Now add ValueA and ValueB, and store the result in ValueA.
  ; Add the low bytes of ValueA and ValueB
  SETD ValueB
  INCD
  LDA
  SETD ValueA
  INCD
  LDB
  CCF
  ADD
  ; Store the result in ValueA.
  STQ
  ; Now add the high bytes of ValueA and ValueB.
  DECD
  LDB
  SETD ValueB
  LDA
  ADD
  ; If this addition overflows, we're done.
  BRC end
  ; Otherwise, store the result in ValueA.
  SETD ValueA
  STQ
  ; And branch back to the beginning of the loop.
  BRI start
 end:
  CALL lineFeed
  HALT

#Data

ValueA:
; Low byte, high byte.
0x00 0x01

ValueB:
; Low byte, high byte.
0x00 0x00
