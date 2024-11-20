; Test for the hexadecimal printing routines.

#Program
 printByteHexTest:
  RSTA
  INIB 0xFF
 printHexTestLoop:
  CALL printByteHex
  CALL blankSpace
  INCA
  DECB
  BRC printHexTestend
  BRI printHexTestLoop
  printHexTestend:
  CALL lineFeed
  RET

#Data
