; Tests for the printDecimal subroutine.

#Program

printByteDecimalTest:
  INIB 0xFF                 ; Load 255 into B.
 printDecimalTestloop:
  SUB
  CCF                       ; Clear the Carry Flag.
  CALL printByteDecimal         ; Print the value.
  INCA                      ; Increment it.
  PSHA
  INIA 0x00
  CALL blankSpace
  POPA
  BRQ printDecimalTestend                   ; If Q is zero, we're done.
  BRI printDecimalTestloop  ; Branch back to the start of the loop.
 printDecimalTestend:
  CALL lineFeed
  RET

#Data

Space:
  " "
