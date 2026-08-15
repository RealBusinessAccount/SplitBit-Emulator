; Deliberately broken, to check that the assembler still catches it.
; The same name is defined twice, which used to be accepted silently, with every
; reference quietly resolving to whichever definition came first.

#Program

start:
  BRI twice

twice:
  HALT

twice:
  HALT
