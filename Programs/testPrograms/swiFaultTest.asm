; Tests a software interrupt that names a vector with nothing installed in it.
;
; Until the assembler can lay down a vector table, every entry reads as zero, and zero
; means no handler. Dispatching through one has to stop the machine and say which
; vector was empty, rather than jumping to the bottom of Program Memory and running
; whatever happens to be sitting there.
;
; The letter is printed first so that it is obvious the program ran at all, and that it
; stopped exactly where it should have.
;
; Correct output is:
;   O
;   a fault naming software vector 20, and a non zero exit.

#Program

start:
  INIA 0d79         ; 'O'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00

  SWI 0d20          ; Nothing is installed here.

  ; Never reached. If the machine ever prints this, the empty vector was taken.
  INIA 0d88         ; 'X'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00
  HALT
