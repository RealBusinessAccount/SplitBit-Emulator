; Exercises console.asm, the modern console library.
;
; Every routine in it is called here with the cases that are easy to get wrong: a zero,
; the largest thing that fits, the boundary either side of a carry, and a leading zero
; that should not print. The reading half is driven by consoleTest.in, which ends with a
; line longer than the buffer so that the truncation and the swallowing of the rest are
; both shown rather than assumed.
;
; There is no BRI at the top of console.asm, so this program says where it begins in its
; Vector Segment. That is the whole of the arrangement the old library needed a branch for.

#Include console.asm

#Program

start:
  SETD.0 Banner
  CALL printString
  CALL newLine

  ; ---- Hexadecimal ----
  SETD.0 HexLabel
  CALL printString
  RSTA
  CALL printByteHex
  INIA 0x20
  OUTA 0x00
  INIA 0x0F
  CALL printByteHex
  INIA 0x20
  OUTA 0x00
  INIA 0xA5
  CALL printByteHex
  INIA 0x20
  OUTA 0x00
  INIA 0xFF
  CALL printByteHex
  CALL newLine

  SETD.0 WordHexLabel
  CALL printString
  SETD.0 Zero
  CALL printWordHex
  INIA 0x20
  OUTA 0x00
  SETD.0 Thousand
  CALL printWordHex
  INIA 0x20
  OUTA 0x00
  SETD.0 Largest
  CALL printWordHex
  CALL newLine

  ; ---- Decimal, one byte wide ----
  ; Zero has to print a digit, and a hundred has to not print its tens as a blank.
  SETD.0 ByteLabel
  CALL printString
  RSTA
  CALL printByteDecimal
  CALL blank
  INIA 0d7
  CALL printByteDecimal
  CALL blank
  INIA 0d42
  CALL printByteDecimal
  CALL blank
  INIA 0d100
  CALL printByteDecimal
  CALL blank
  INIA 0d255
  CALL printByteDecimal
  CALL newLine

  ; ---- Decimal, two bytes wide ----
  ; Ten thousand and one is the case that catches a place that stops counting too soon,
  ; and the three zeroes in the middle of it are the case that catches a leading zero
  ; test applied after the first digit.
  SETD.0 WordLabel
  CALL printString
  SETD.0 Zero
  CALL printWordDecimal
  CALL blank
  SETD.0 Nine
  CALL printWordDecimal
  CALL blank
  SETD.0 Ten
  CALL printWordDecimal
  CALL blank
  SETD.0 TwoFiveFive
  CALL printWordDecimal
  CALL blank
  SETD.0 Thousand
  CALL printWordDecimal
  CALL blank
  SETD.0 TenThousandOne
  CALL printWordDecimal
  CALL blank
  SETD.0 Largest
  CALL printWordDecimal
  CALL newLine

  ; ---- Spaces ----
  ; None of them is a fair number to ask for, and has to print nothing at all.
  SETD.0 SpaceLabel
  CALL printString
  INIA 0x7C
  OUTA 0x00
  RSTA
  CALL printSpaces
  INIA 0x7C
  OUTA 0x00
  INIA 0d4
  CALL printSpaces
  INIA 0x7C
  OUTA 0x00
  CALL newLine

  ; ---- Reading ----
  SETD.0 ReadLabel
  CALL printString
  CALL newLine

readLoop:
  SETD.0 LineBuffer
  INIB 0d16
  CALL readLine
  SETD.0 LineLength
  STQ.0

  ; Running out is not an empty line, and this is where the difference shows.
  SETD.0 ConsoleEndOfInput
  LDA.0
  BNA readDone

  INIA 0x5B
  OUTA 0x00
  SETD.0 LineBuffer
  CALL printString
  INIA 0x5D
  OUTA 0x00
  CALL blank
  SETD.0 LineLength
  LDA.0
  CALL printByteDecimal
  CALL newLine
  BRI readLoop

readDone:
  SETD.0 Ended
  CALL printString
  CALL newLine
  HALT

; One space. Used between the numbers so that each line reads as a list.
blank:
  INIA 0x20
  OUTA 0x00
  RET

#Data

Banner:
"console test"
HexLabel:
"byte hex:  "
WordHexLabel:
"word hex:  "
ByteLabel:
"byte dec:  "
WordLabel:
"word dec:  "
SpaceLabel:
"spaces:    "
ReadLabel:
"lines read:"
Ended:
"end of input"

Zero:
  0x00 0x00
Nine:
  0x00 0x09
Ten:
  0x00 0x0A
TwoFiveFive:
  0x00 0xFF
Thousand:
  0x03 0xE8
TenThousandOne:
  0x27 0x11
Largest:
  0xFF 0xFF

LineLength:
  0x00
LineBuffer:
  #Reserve 0d17

#Vectors

  Boot  start
