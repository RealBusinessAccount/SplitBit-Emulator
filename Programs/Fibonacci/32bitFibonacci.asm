; A Fibonacci number generating program that uses four bytes to store the value.

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
  INCD
  LDA
  PSHA
  INCD
  LDA
  PSHA
  ; Next, store ValueB on the stack.
  SETD ValueB
  LDA
  PSHA
  INCD
  LDA
  PSHA
  INCD
  LDA
  PSHA
  INCD
  LDA
  PSHA
  ; Then pop ValueB into ValueA.
  SETD ValueA
  INCD INCD INCD
  POPA
  STA
  DECD
  POPA
  STA
  DECD
  POPA
  STA
  DECD
  POPA
  STA
  ; Then pop ValueA into ValueB.
  SETD ValueB
  INCD INCD INCD
  POPA
  STA
  DECD
  POPA
  STA
  DECD
  POPA
  STA
  DECD
  POPA
  STA
  ; Print ValueA.
  SETD ValueA
  INCD INCD INCD
  LDA
  CALL printByteHex
  DECD
  LDA
  CALL printByteHex
  DECD
  LDA
  CALL printByteHex
  DECD
  LDA
  CALL printByteHex
  CALL blankSpace
  ; Now add ValueA and ValueB, and store the result in ValueA.
  ; Add the lowest bytes of ValueA and ValueB.
  SETD ValueB
  LDB
  SETD ValueA
  LDA
  ADD
  ; Store it in ValueA's lowest byte.
  STQ
  ; Add the second lowest bytes of ValueA and ValueB.
  SETD ValueB
  INCD
  LDB
  SETD ValueA
  INCD
  LDA
  ADD
  ; Store it in ValueA's second lowest byte.
  STQ
  ; Add the second highest bytes of ValueA and ValueB.
  SETD ValueB
  INCD INCD
  LDB
  SETD ValueA
  INCD INCD
  LDA
  ADD
  ; Store it in ValueA's third lowest byte.
  STQ
  ; Add the highest bytes of ValueA and ValueB.
  SETD ValueB
  INCD INCD INCD
  LDB
  SETD ValueA
  INCD INCD INCD
  LDA
  ADD
  ; If this addition overflows, we're done.
  BRC end
  ; Otherwise, store the result in ValueA's highest byte.
  STQ
  ; And branch back to the beginning of the loop.
  BRI start
 end:
  CALL lineFeed
  HALT

#Data

ValueA:
; Lowest byte ... Highest byte.
0x01 0x00 0x00 0x00

ValueB:
; Lowest byte ...  Highest byte.
0x00 0x00 0x00 0x00
