; Tests for the printDecimal subroutine.

#Program

printByteDecimalTest:
  INIB 0xFF   ; Load 255 into B.
 printDecimalTestloop:
 ; Print A and a blank space.
  CALL printByteDecimal
  CALL blankSpace
  INCA    ; Increment A.
  DECB    ; Decrement B.
  ; If B underflows, we're done.
  BRC printDecimalTestend
  BRI printDecimalTestloop  ; Branch back to the start of the loop.
 printDecimalTestend:
  CALL lineFeed
  RET

#Data

Space:
  " "
