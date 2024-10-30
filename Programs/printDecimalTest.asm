; Tests for the printDecimal subroutine.

#Include print.asm

#Program

start:
  INIB 0xFF         ; Load 255 into B.
 loop:
  SETD MyDecimal    ; Set D to our decimal.
  SUB
  CCF               ; Clear the Carry Flag.
  CALL printDecimal ; Print the value.
  LDA               ; Load the value into A.
  INCA              ; Increment it.
  STA               ; Store it again.
  SETD Space
  CALL printString  ; Print a space between the the numbers.
  BRQ end           ; If Q is zero, we're done.
  BRI loop          ; Branch back to the start of the loop.
 end:
  CALL lineFeed
  HALT

#Data

MyDecimal:
  0x00

Space:
  " "
