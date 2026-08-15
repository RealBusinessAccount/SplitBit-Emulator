; Tests MVQA and MVQB.
;
; Every ALU result lands in Q, and Q is not an ALU operand. Without these two
; instructions the only way to use a result in the next sum is to store it into
; Data Memory and load it back, which costs two instructions and a Data Pointer
; that has to be pointing somewhere sensible.
;
; Correct output is:
;   AAA

#Program

start:
  CCF
  INIA 0d60
  INIB 0d5
  ADD           ; Q = 65, which is 'A'.
  MVQA          ; A = 65
  OUTA 0x00
  MVQB          ; And B, from the same result.
  OUTB 0x00

  ; A running total kept entirely in registers, which is the thing that was not
  ; possible before. Nothing here touches Data Memory at all.
  CCF
  RSTA
  INIB 0d1
  ADD           ; Q = 1
  MVQA
  ADD           ; Q = 2
  MVQA
  ADD           ; Q = 3
  MVQA
  INIB 0d62
  ADD           ; Q = 65 again
  MVQA
  OUTA 0x00

  INIA 0x0A
  OUTA 0x00
  HALT
