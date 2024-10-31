#Program

printDigitTest:
  INIB 0d10
 printDigitTestLoop:
  CALL printDecimalDigit
  INCA
  SUB
  CCF
  BRQ printDigitTestend
  CALL lineFeed
  BRI printDigitTestLoop
 printDigitTestend:
  CALL lineFeed
  RET

#Data
