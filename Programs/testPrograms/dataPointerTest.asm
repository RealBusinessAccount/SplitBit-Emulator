; Tests the Data Pointer calling convention.
;
; Every Data Pointer is aimed at a different marker byte, then a subroutine
; repoints all four of them at Z and returns.
;
; DP0 through DP2 are preserved across a CALL, so they should come back still
; aimed at their own markers. DP3 is volatile, which is what lets a subroutine
; hand an address back to its caller, so it should come back aimed at Z.
;
; Correct output is ABCZ.

#Program

start:
  SETD.0 MarkA
  SETD.1 MarkB
  SETD.2 MarkC
  SETD.3 MarkD
  CALL clobber

  ; Read a byte through each pointer in turn and print it.
  LDA.0
  OUTA 0x00
  LDA.1
  OUTA 0x00
  LDA.2
  OUTA 0x00
  LDA.3
  OUTA 0x00

  INIA 0x0A
  OUTA 0x00
  HALT

clobber:
  ; Aim every pointer somewhere else. Only the change to DP3 should outlive the RET.
  SETD.0 MarkZ
  SETD.1 MarkZ
  SETD.2 MarkZ
  SETD.3 MarkZ
  RET

#Data

MarkA:
"A"
MarkB:
"B"
MarkC:
"C"
MarkD:
"D"
MarkZ:
"Z"
