; Subroutines for printing int16 values to the console.

#Include print.asm
#Include int16.asm

#Program

start:
 SETD PrintInt16dec
 CALL printInt16dec
 CALL lineFeed
 HALT

printInt16dec:
  ; We're gonna print an int16 as a decimal.
  ; The Data Pointer is set to our int16.
  ; Let's copy it into a temporary location where we can set up an operand.
  LDA
  INCD
  LDB
  SETD PrintInt16dec
  STA
  INCD
  STB
  ; Load the buffer address into the Data Pointer
  SETD PrintInt16decBuffer
  ; Let's clear it before we use it.
  RSTA STA INCD STA INCD STA INCD STA INCD STA
  PSHD      ; Save the offset Data Pointer value to the Stack.
 printInt16decLoop:
  SETD PrintInt16dec
  ; Set Operand B to 0d10.
  DPUP 0x02
  INIA 0d10
  RSTB
  STB
  INCD
  STA
  DPDN 0x03
  ; Now call int16div.
  CALL int16div
  ; Store the remainder. We only need the low byte.
  INCD
  LDA
  POPD      ; Pop the pointer to the current place value from the Stack.
  STA
  DECD      ; Decrement and store the Data Pointer on the Stack again.
  PSHD
  ; If the dividend is 0, we're done.
  INCD
  LDA
  INCD
  LDB
  OR
  BRQ printInt16decLoopDone
  ; Now move the quotient up to Operand A.
  SETD PrintInt16dec
  DPUP 0x02
  LDA
  INCD
  LDB
  DPDN 0x03
  STA
  INCD
  STB
  ; Now branch back to the loop.
  BRI printInt16decLoop
 printInt16decLoopDone:
  SETD PrintInt16decBuffer
  INIB 0x0A
 printBufferHex:
  LDA
  CCF
  SUB
  BRQ continue
  CALL printByteHex
  CALL blankSpace
  INCD
  BRI printBufferHex
 continue:
  CALL lineFeed
  ; All we need to do now is pop the Data Pointer value back off the stack and print the digits until we reach a value of 0x0A.
  POPD
  SETD PrintInt16decBuffer
  LDA
  INIB 0x0A
  BRA printInt16decSkipLeadingZeros
  BRI printInt16decLoop1
 printInt16decSkipLeadingZeros:
  INCD
  LDA
  BRA printInt16decSkipLeadingZeros
 printInt16decLoop1:
  LDA
  CCF
  SUB
  ; If Q is zero, we've hit the terminator and are done printing.
  BRQ printInt16decDone
  CALL printDecimalDigit
  INCD
  ; Branch back to see if there are more digits to print.
  BRI printInt16decLoop1
 printInt16decDone:
  RET ; Return to the caller.



#Data

PrintInt16dec:
 0x07 0xD1 ; Operand A
 0x00 0x00 ; Operand B

PrintInt16decBuffer:
; This needs to be a five byte buffer to store each digit value.
; Let's make it six and use the last byte as a terminator outside the range of 0-9.
0x00 0x00 0x00 0x00 0x00 0x0A
