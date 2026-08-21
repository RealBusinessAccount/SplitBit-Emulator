; The assembler's front end on its own, one line per token.
;
; Prints the line each token started on, what the token turned out to be, how many bytes
; it will come to, and the token itself between brackets so that whitespace at either end
; would show if any ever leaked in.
;
; WHAT A TOKEN IS is the part worth checking here rather than at the far end. A wrong
; classification does not produce a wrong byte in an obvious place - it produces a right
; looking program of the wrong length, with everything after it shifted, and by then the
; only symptom is that a label points at the middle of an instruction.
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

tokenLoop:
  CALL tokNext
  BNQ tokensDone

  SETD.0 TokLine
  LDA.0
  INCD.0
  LDB.0
  SWI osPrintNumber

  CALL clsToken
  BNQ badToken

  ; Which of the six it turned out to be. The names are four characters and a space, so
  ; the columns line up without any counting.
  SETD.0 TypeNames
  SETD.2 ClsType
  LDA.2
  CALL nameOfType
  SETD.1 NamePointer
  LDD.0.1
  SWI osPrintString

  SETD.0 ClsLength
  LDA.0
  INCD.0
  LDB.0
  SWI osPrintNumber         ; Sixteen bits: a string of 255 characters is 256 bytes long.

  SETD.0 OpenMark
  SWI osPrintString
  SETD.0 TokText
  SWI osPrintString
  SETD.0 CloseMark
  SWI osPrintString
  BRI tokenLoop

badToken:
  SETD.0 StoppedText
  SWI osPrintString
  SWI osExit

; The name of type A, out of a table of fixed width entries so that no pointer arithmetic
; is needed beyond a multiply by the width.
nameOfType:
  SETD.0 TypeWidth
  LDB.0
  RSTA
  SETD.0 NameLeft
  STA.0
  SETD.2 ClsType
  LDA.2
  SETD.0 NameOffset
  CALL numZero
nameLoop:
  SETD.2 ClsType
  LDA.2
  SETD.0 NameLeft
  LDB.0
  CCF
  SUB
  BRQ nameFound
  SETD.0 TypeWidth
  LDA.0
  SETD.0 NameOffset
  CALL numAddByte
  SETD.0 NameLeft
  LDA.0
  INCA
  STA.0
  BRI nameLoop
nameFound:
  ; The answer is left in NamePointer rather than in DP0, because a RET puts Data Pointers
  ; 0 to 2 back as they were: a routine cannot hand back a pointer, only write one down.
  SETD.0 TypeNames
  SETD.1 NamePointer
  STD.0.1
  SETD.0 NamePointer
  SETD.2 NameOffset
  CALL numAdd
  RET

tokensDone:
  SETD.0 DoneText
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

OpenMark:
" ["
CloseMark:
"]
"
; Six names of eleven characters each, counting the zero the assembler puts on the end of
; every string. Written one to a line so that adding a type is adding a line.
TypeNames:
"  keyword "
"  instr   "
"  value   "
"  string  "
"  label:  "
"  label   "
TypeWidth:
  0d11
NameLeft:
  0x00
NameOffset:
  0x00 0x00
NamePointer:
  0x00 0x00

StoppedText:
"---- stopped: the assembler does not understand that
"
DoneText:
"---- no more tokens
"
AskText:
"say which file
"
NoFileText:
"no such file
"

#Include scratch.asm
#Include numbers.asm
#Include source.asm
#Include token.asm
#Include classify.asm
#Include table.asm
