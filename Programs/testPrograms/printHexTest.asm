; Test for the hexadecimal printing routines.

#Program
 printByteHexTest:
  INIB 0xFF
  CALL printByteHex
 printHexTestLoop:
  PSHA
  INIA 0x00
  CALL blankSpace
  POPA
  INCA
  SUB
  CCF
  CALL printByteHex
  BRQ printHexTestend
  BRI printHexTestLoop
  printHexTestend:
  CALL lineFeed
  RET

#Data
