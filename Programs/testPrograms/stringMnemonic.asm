; A string whose text spells an instruction.
;
; The quotes are gone by the time the assembler looks at a token, so a string reading "ADD"
; used to be assembled as the ADD instruction - which failed with "attempting to assemble
; outside the Program Segment", a message about a mistake nobody had made. Mnemonics match
; without regard to case, so "or" and "and" were caught by it too, and those are ordinary
; enough words to want in a message.
;
; Correct output is:
;   ADD OR and NOP

#Include console.asm

#Program

start:
  SETD.0 First
  CALL printString
  CALL blank
  SETD.0 Second
  CALL printString
  CALL blank
  SETD.0 Third
  CALL printString
  CALL blank
  SETD.0 Fourth
  CALL printString
  CALL newLine
  HALT

blank:
  INIA 0x20
  OUTA 0x00
  RET

#Data

First:
"ADD"
Second:
"OR"
Third:
"and"
Fourth:
"NOP"

#Vectors

  Boot start
