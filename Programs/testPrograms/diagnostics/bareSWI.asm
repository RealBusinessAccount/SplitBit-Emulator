; SWI with nothing after it.
;
; Without the operand check this assembles, and SWI quietly takes the next
; instruction as its vector number. Everything after it then shifts by a byte.

#Program

start:
  SWI
  HALT
