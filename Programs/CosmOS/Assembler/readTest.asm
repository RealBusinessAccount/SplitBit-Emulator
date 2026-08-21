; The source reader on its own, before anything is built on top of it.
;
; Everything else in the assembler reads its source through srcNext, so a fault in here
; would turn up later as a mysterious wrong byte in an output file. It is worth checking by
; itself, against a file whose contents are already known.
;
; It reads whatever it was told to, prints every character back, and then says how many
; lines went past. The file it is given is deliberately bigger than one block, so the seam
; between one block and the next is crossed rather than assumed.
;
; Written by Anachronaut

#Include services.asm

#Program

  #Base 0x2000

start:
  SETD.0 Wanted
  INIB 0d23
  SWI osArgument
  SETD.0 Wanted
  LDA.0
  BRA nothingAsked

  SETD.0 Wanted
  CALL srcOpen
  BNQ noFile

readLoop:
  CALL srcNext
  BNQ readDone
  SETD.0 SrcChar
  LDA.0
  OUTA 0x00                 ; Straight to the console: one character is not a string.
  BRI readLoop

readDone:
  SETD.0 LinesText
  SWI osPrintString
  SETD.0 SrcLine
  LDA.0
  INCD.0
  LDB.0
  SWI osPrintNumber
  SETD.0 NewLine
  SWI osPrintString
  SWI osExit

nothingAsked:
  SETD.0 AskText
  SWI osPrintString
  SWI osExit

noFile:
  SETD.0 NoFileText
  SWI osPrintString
  SWI osExit

#Data

  #Base 0x1000

Wanted:
  #Reserve 0d23

LinesText:
"---- lines: "
NewLine:
"
"
AskText:
"say which file
"
NoFileText:
"no such file
"

; The libraries go last, after both segments have been based. An included file that carries
; code brings its own #Program and #Data lines with it, and a #Base has to come before
; anything is in the segment it bases - so the bases are set here and the code arrives after.
#Include numbers.asm
#Include source.asm
