; console.asm
; Talking to the console.
;
; This is the modern replacement for print.asm, which was written for a machine with one
; Data Pointer and no vector table. The old one is left where it is, because the programs
; that include it still work and are meant to keep working.
;
; Two things are different here, and both are deliberate.
;
; There is no branch at the top. print.asm begins with BRI start, so that a program
; including it arrives at its own entry point instead of falling into the library. That
; was the only way to do it before the Boot vector existed. A program including this file
; says where it begins in its own Vector Segment:
;
;   #Vectors
;     Boot  start
;
; And every routine here names the Data Pointer it works through rather than assuming the
; only one. A pointer handed in is DP0. Nothing here disturbs what the caller left in
; DP3, which is the one a return survives in.
;
; What a routine gives back is in Q, because Q and DP3 are the only things a RET does not
; put back the way it found them.
;
; Written by Anachronaut

#Program

; ---- Characters and strings ----

; A line feed.
newLine:
  INIA 0x0A
  OUTA 0x00
  RET

; DP0 names a string ending in a zero byte. Prints it.
printString:
  LDA.0
  BRA printStringDone
  OUTA 0x00
  INCD.0
  BRI printString
printStringDone:
  RET

; A holds how many spaces to print. None is a fair answer, and prints nothing.
printSpaces:
  BRA printSpacesDone
  INIB 0x20
printSpacesLoop:
  OUTB 0x00
  DECA
  BNA printSpacesLoop
printSpacesDone:
  RET

; ---- Hexadecimal ----

; A holds a byte. Prints it as two hexadecimal digits, high one first.
;
; A and B are a circular shift register sixteen bits long, so rotating right four times
; with B empty walks the high nybble down into place and parks the low one in B. The call
; between the two halves puts A and B back as they were, which is what lets the second
; rotation find the low nybble still waiting.
printByteHex:
  RSTB
  SHR SHR SHR SHR
  CALL printHexDigit
  RSTA
  SHL SHL SHL SHL
  CALL printHexDigit
  RET

; DP0 names two bytes, most significant first, the way every number on a SplitBit disk is
; stored. Prints them as four hexadecimal digits.
printWordHex:
  LDA.0
  CALL printByteHex
  INCD.0
  LDA.0
  CALL printByteHex
  RET

; A holds a nybble. Prints the one character that stands for it.
printHexDigit:
  INIB 0d10
  CCF
  SUB
  BRC printDecimalDigit ; Under ten, so it is a plain digit.
  INIB 0x37             ; 'A' is ten, so this is the offset that gets there.
  CCF
  ADD
  OUTQ 0x00
  RET

; A holds a digit from zero to nine. Prints it.
printDecimalDigit:
  INIB 0x30
  CCF
  ADD
  OUTQ 0x00
  RET

; ---- Decimal ----

; A holds a byte. Prints it in decimal, without leading zeroes.
printByteDecimal:
  SETD.0 ConsoleValue
  STA.0
  SETD.1 ConsoleLeading
  RSTA
  STA.1                 ; Nothing has been printed yet.

  INIA 0d100
  CALL printBytePlace
  INIA 0d10
  CALL printBytePlace

  ; Whatever is left is the ones, and it prints whether or not it is a zero, because a
  ; number has to show at least one digit.
  SETD.0 ConsoleValue
  LDA.0
  CALL printDecimalDigit
  RET

; A holds a power of ten. Counts how many times it comes out of ConsoleValue, prints that
; as a digit, and leaves the remainder behind. A leading zero prints nothing.
printBytePlace:
  SETD.2 ConsoleBytePower
  STA.2
  SETD.0 ConsoleValue
  SETD.1 ConsoleCount
  RSTA
  STA.1
printBytePlaceLoop:
  LDA.0
  LDB.2
  CCF
  SUB
  BRC printBytePlaceDone ; It went below zero, so it does not come out again.
  STQ.0
  LDA.1
  INCA
  STA.1
  BRI printBytePlaceLoop
printBytePlaceDone:
  LDA.1
  BNA printBytePlaceShow
  ; The digit is a zero, which only prints if something has been printed before it.
  SETD.2 ConsoleLeading
  LDA.2
  BRA printBytePlaceQuiet
  RSTA
printBytePlaceShow:
  CALL printDecimalDigit
  SETD.2 ConsoleLeading
  INIA 0x01
  STA.2
printBytePlaceQuiet:
  RET

; DP0 names a two byte number, most significant byte first. Prints it in decimal, without
; leading zeroes. Sixty five thousand five hundred and thirty five is the largest thing it
; can be handed, which is the whole of an address, so nothing overflows this.
printWordDecimal:
  SETD.1 ConsoleWord
  CALL consoleCopyWord
  SETD.1 ConsoleLeading
  RSTA
  STA.1

  SETD.0 ConsoleTenThousand
  CALL printWordPlace
  SETD.0 ConsoleThousand
  CALL printWordPlace
  SETD.0 ConsoleHundred
  CALL printWordPlace
  SETD.0 ConsoleTen
  CALL printWordPlace

  ; What is left is under ten, so it is in the low byte and it is the last digit.
  SETD.0 ConsoleWord
  INCD.0
  LDA.0
  CALL printDecimalDigit
  RET

; DP0 names a power of ten, two bytes of it. The same counting as printBytePlace, done
; sixteen bits wide.
printWordPlace:
  SETD.1 ConsolePower
  CALL consoleCopyWord
  SETD.1 ConsoleCount
  RSTA
  STA.1
printWordPlaceLoop:
  CALL consoleTakePower
  BNQ printWordPlaceDone
  SETD.1 ConsoleCount
  LDA.1
  INCA
  STA.1
  BRI printWordPlaceLoop
printWordPlaceDone:
  SETD.1 ConsoleCount
  LDA.1
  BNA printWordPlaceShow
  SETD.1 ConsoleLeading
  LDA.1
  BRA printWordPlaceQuiet
  RSTA
printWordPlaceShow:
  CALL printDecimalDigit
  SETD.1 ConsoleLeading
  INIA 0x01
  STA.1
printWordPlaceQuiet:
  RET

; Takes ConsolePower out of ConsoleWord, if it comes out at all. Q is zero if it did, and
; then ConsoleWord is the smaller for it. If it did not, ConsoleWord is left alone.
;
; The subtraction is done into a spare word rather than in place, because whether it fits
; is not known until the high half is done, and by then an in place low half would already
; have been spent.
;
; The low half clears the Carry Flag first and the high half does not: the borrow the low
; half leaves behind is exactly what the high half has to subtract as well. Nothing
; between them disturbs it, since only the arithmetic instructions and CCF touch it.
consoleTakePower:
  SETD.0 ConsoleWord
  INCD.0
  SETD.1 ConsolePower
  INCD.1
  LDA.0
  LDB.1
  CCF
  SUB
  SETD.2 ConsoleSpare
  INCD.2
  STQ.2

  SETD.0 ConsoleWord
  SETD.1 ConsolePower
  LDA.0
  LDB.1
  SUB
  BRC consoleTakeNothing
  SETD.2 ConsoleSpare
  STQ.2

  SETD.0 ConsoleSpare
  SETD.1 ConsoleWord
  CALL consoleCopyWord
  RSTA
  RSTB
  CCF
  ADD                   ; Q is zero: it came out.
  RET
consoleTakeNothing:
  RSTA
  INIB 0x01
  CCF
  ADD                   ; Q is one: it did not.
  RET

; Two bytes from DP0 to DP1, most significant first.
consoleCopyWord:
  LDA.0
  STA.1
  INCD.0
  INCD.1
  LDA.0
  STA.1
  RET

; ---- Reading ----

; DP0 names a buffer and B says how many characters it holds, not counting the zero byte
; that ends it. Reads a line from the console into it. Q is how long the line turned out
; to be.
;
; A line longer than the buffer is cut short, and the rest of it is read and thrown away
; rather than left to turn up as the next line.
;
; ConsoleEndOfInput is set if the console ran out instead of ending a line. That is a
; different thing from an empty line, and a program that reads until there is no more has
; to be able to tell them apart.
readLine:
  SETD.1 ConsoleRoom
  STB.1
  SETD.1 ConsoleLength
  RSTA
  STA.1
  SETD.1 ConsoleEndOfInput
  STA.1
readLineNext:
  INA 0x00
  INIB 0x0A
  CCF
  SUB
  BRQ readLineDone      ; A line feed ends the line. A is still the character.
  INIB 0xFF
  CCF
  SUB
  BRQ readLineEnd       ; There is no more to be had.

  ; Is there room for it? A still holds the character, so it is put somewhere safe while
  ; the counting is done.
  SETD.1 ConsoleChar
  STA.1
  SETD.1 ConsoleLength
  LDA.1
  SETD.1 ConsoleRoom
  LDB.1
  CCF
  SUB
  BRQ readLineNext      ; Full. Read on, and drop what comes.

  SETD.1 ConsoleChar
  LDA.1
  STA.0
  INCD.0
  SETD.1 ConsoleLength
  LDA.1
  INCA
  STA.1
  BRI readLineNext
readLineEnd:
  SETD.1 ConsoleEndOfInput
  INIA 0x01
  STA.1
readLineDone:
  RSTA
  STA.0                 ; The zero byte that ends it.
  SETD.1 ConsoleLength
  LDA.1
  RSTB
  CCF
  ADD                   ; Q is how long the line is.
  RET

#Data

; ---- What readLine keeps while it works ----

ConsoleRoom:
  0x00
ConsoleLength:
  0x00
ConsoleChar:
  0x00

; Set when the console ran out rather than ending a line. Cleared at the start of every
; readLine, so it always describes the last line read.
ConsoleEndOfInput:
  0x00

; ---- What the number routines keep while they work ----

; Whether any digit has been printed yet, which is what decides if a zero is a leading
; one or a real one.
ConsoleLeading:
  0x00
ConsoleCount:
  0x00
ConsoleValue:
  0x00
ConsoleBytePower:
  0x00
ConsolePower:
  0x00 0x00
ConsoleWord:
  0x00 0x00
ConsoleSpare:
  0x00 0x00

; The powers of ten, written the way every number here is written: most significant byte
; first.
ConsoleTenThousand:
  0x27 0x10
ConsoleThousand:
  0x03 0xE8
ConsoleHundred:
  0x00 0x64
ConsoleTen:
  0x00 0x0A
