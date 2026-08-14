; Tests address tables written down by the assembler.
;
; Naming a label in the Data Segment places its two byte address there. That is
; what lets a program lay down a table of addresses ahead of time and walk it
; with LDD, rather than having to build the table at run time with STD.
;
; The label after the table also checks that the assembler counts those two
; bytes when it works out the addresses of everything that follows.
;
; Correct output is:
;   one
;   two
;   three
;   AFTER

#Program

start:
  SETD.0 Table
  INIB 0d3          ; Three entries in the table.

nextEntry:
  LDD.1.0           ; DP1 becomes the address held in this table slot.
  CALL printDP1
  DPUP.0 0d02       ; Step DP0 over the two byte slot.
  DECB
  BRB tableDone
  BRI nextEntry

tableDone:
  ; Anything placed after the table has to be where the assembler said it was.
  SETD.2 After
  CALL printDP2
  HALT

printDP1:
  LDA.1
  BRA print1Done
  OUTA 0x00
  INCD.1
  BRI printDP1
 print1Done:
  INIA 0x0A
  OUTA 0x00
  RET

printDP2:
  LDA.2
  BRA print2Done
  OUTA 0x00
  INCD.2
  BRI printDP2
 print2Done:
  INIA 0x0A
  OUTA 0x00
  RET

#Data

One:
"one"
Two:
"two"
Three:
"three"

; The table. Each of these names becomes the two byte address of that string.
Table:
One
Two
Three

After:
"AFTER"
