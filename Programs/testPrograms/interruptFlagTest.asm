; Tests SIF and CIF, the Interrupt Flag.
;
; Nothing reads the Interrupt Flag yet, so what this proves is that the two
; instructions decode, execute, and leave everything else exactly as they found
; it. The Carry Flag is the part worth checking, because it lives in the same
; Status register and a careless mask would take it out.
;
; Correct output is:
;   OKC

#Program

start:
  ; Load two registers, run the new instructions across them, and prove that
  ; nothing moved.
  INIA 0d79         ; 'O'
  INIB 0d75         ; 'K'
  SIF
  CIF
  SIF
  OUTA 0x00         ; Still 'O'.
  OUTB 0x00         ; Still 'K'.

  ; Now set the Carry Flag, and work the Interrupt Flag around it.
  CCF
  INIA 0xFF
  INIB 0x01
  ADD               ; Q = 0, and the Carry Flag is set.
  SIF
  CIF
  BRC carryHeld

  ; Falling through here means one flag trampled the other.
  INIA 0d88         ; 'X'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00
  HALT

carryHeld:
  INIA 0d67         ; 'C'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00
  HALT
