; Vectors with numbers written down, and vectors numbered by the assembler, in one program.
;
; A software vector number matters only when two separately assembled programs have to
; agree about it. The system's services are the case that exists today: something calls
; osExit without having been assembled alongside whatever implements it, so both sides
; have to mean the same number by that name.
;
; Numbers from 16 to 63 are for exactly that and are never handed out. Everything from 64
; up is handed out in the order it is written, and belongs to one program.
;
; This pins one at each end of the reserved range and leaves a third to the assembler. All
; three are then called by name, which is the only way a program ever refers to one - the
; number is a fact about the machine, not something a program says twice.
;
; Correct output is:
;   pinned vectors
;   twenty
;   sixty three
;   automatic
;   done

#Include console.asm

#Program

start:
  SETD.0 Banner
  CALL printString
  CALL newLine

  SWI atTwenty
  SWI atSixtyThree
  SWI automatic

  SETD.0 DoneText
  CALL printString
  CALL newLine
  HALT

; Each of these says which one it is, so a number going to the wrong place is a wrong word
; rather than a silence.
twentyHandler:
  SETD.0 TwentyText
  CALL printString
  CALL newLine
  RETI

sixtyThreeHandler:
  SETD.0 SixtyThreeText
  CALL printString
  CALL newLine
  RETI

automaticHandler:
  SETD.0 AutomaticText
  CALL printString
  CALL newLine
  RETI

#Data

Banner:
"pinned vectors"
TwentyText:
"twenty"
SixtyThreeText:
"sixty three"
AutomaticText:
"automatic"
DoneText:
"done"

#Vectors

  Boot                  start
  atTwenty      0d20    twentyHandler
  atSixtyThree  0d63    sixtyThreeHandler
  automatic             automaticHandler
