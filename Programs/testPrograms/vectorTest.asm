; Tests the Vector Segment: a Boot Vector pointing somewhere other than the start of the
; program, and a software interrupt the program names for itself.
;
; The decoy sits at address 0x0000, where execution would begin if the Boot Vector were
; not obeyed. It prints an X, so if an X ever appears the vector was ignored.
;
; The handler tramples every register it can reach. Everything printed afterwards comes
; out of the frame, which is the point: an interrupt gives back what it borrowed, and
; unlike a subroutine that includes Q and Data Pointer 3.
;
; Correct output is:
;   OK!
;   good
;   AFTER

#Program

decoy:
  INIA 0d88         ; 'X'. Never reached.
  OUTA 0x00
  HALT

realStart:
  CCF
  INIA 0d79         ; 'O'
  INIB 0d75         ; 'K'
  SETD.0 Good       ; DP0 is preserved across a CALL as well.
  SETD.3 After      ; DP3 is not, but an interrupt has to give it back anyway.

  SWI stampTrap

  OUTA 0x00         ; 'O'
  OUTB 0x00         ; 'K'
  BRC carryLost
  INIA 0d33         ; '!', so the Status register came back too.
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00

  CALL printDP0
  CALL printDP3
  HALT

carryLost:
  INIA 0d63         ; '?'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00
  HALT

; The handler. Nothing it does to a register should survive.
stampRegisters:
  INIA 0xFF
  INIB 0x01
  ADD               ; Q is stamped, and the Carry Flag is set.
  SETD.0 Bad
  SETD.3 Bad
  RETI

printDP0:
  LDA.0
  BRA done0
  OUTA 0x00
  INCD.0
  BRI printDP0
 done0:
  INIA 0x0A
  OUTA 0x00
  RET

printDP3:
  LDA.3
  BRA done3
  OUTA 0x00
  INCD.3
  BRI printDP3
 done3:
  INIA 0x0A
  OUTA 0x00
  RET

#Data

Good:
"good"
Bad:
"bad"
After:
"AFTER"

#Vectors

  Boot            realStart
  stampTrap       stampRegisters
