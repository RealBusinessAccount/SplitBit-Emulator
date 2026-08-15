; Tests MVSD, which copies the Stack Pointer into a Data Pointer.
;
; The Stack Pointer still cannot be written, so this does not let a program move the
; Stack. It lets a program find it, which is what reading anything already on the Stack
; requires. Without it, the manual's claim that a Data Pointer can be aimed at the Stack
; is not something a program can actually act on: there is no way to learn where the
; Stack is without already knowing.
;
; An interrupt handler needs this to reach its own frame, which is how a fault handler
; steps over the byte that failed and carries on.
;
; Correct output is:
;   OK

#Program

start:
  ; Push two bytes, then go looking for them.
  INIA 0d79         ; 'O'
  PSHA
  INIA 0d75         ; 'K'
  PSHA

  ; The Stack Pointer points at the next free slot, so the byte pushed last sits one
  ; above it, and the one before that sits two above.
  MVSD.0
  DPUP.0 0d01
  LDA.0             ; 'K', the last one pushed.
  INCD.0
  LDB.0             ; 'O', the one before it.

  OUTB 0x00
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00
  HALT
