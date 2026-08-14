; Tests LDD and STD, the instructions that move a Data Pointer through Data Memory.
;
; STD writes a pointer into memory, LDD reads one back out. Together they let a
; program build and walk a table of addresses, which is the reason the CPU has
; more than one Data Pointer to walk it with.
;
; Correct output is:
;   Hello
;   World
;   H

#Program

start:
  ; Build a two entry address table at runtime.
  SETD.0 Slot0
  SETD.1 Hello
  STD.1.0           ; Write the address in DP1 to the memory addressed by DP0.
  SETD.0 Slot1
  SETD.1 World
  STD.1.0

  ; Walk the table, following each entry in turn.
  SETD.0 Slot0
  LDD.1.0           ; DP1 becomes the address stored at DP0.
  CALL printDP1
  DPUP.0 0d02       ; Step DP0 over the two byte entry.
  LDD.1.0
  CALL printDP1

  ; A pointer can also follow itself, which is what LDD with one pointer means.
  SETD.0 Slot0
  LDD.0.0           ; DP0 becomes the address it was pointing at.
  LDA.0
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00
  HALT

printDP1:
  ; Print the string addressed by DP1. DP1 is preserved across the CALL, so the
  ; caller gets it back untouched.
  LDA.1
  BRA printDone
  OUTA 0x00
  INCD.1
  BRI printDP1
 printDone:
  INIA 0x0A
  OUTA 0x00
  RET

#Data

Hello:
"Hello"

World:
"World"

; The table itself. Two entries, two bytes each, filled in at run time.
Slot0:
0x00 0x00
Slot1:
0x00 0x00
