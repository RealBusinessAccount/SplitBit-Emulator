; Two vectors pinned to the same number.
;
; This is the mistake pinning makes possible: numbers the assembler hands out cannot
; collide, and numbers a person writes down can. Since the whole point of a pinned number
; is that something outside this program is going to use it, two names sharing one is a
; disagreement that has to be caught here rather than discovered by whatever calls the
; wrong one.
;
; The service names in services.asm sit at 16, 17 and 18, so a program that includes them
; and pins its own trap at one of those is caught by this same check.

#Program

start:
  SWI first
  HALT

firstHandler:
  RETI

secondHandler:
  RETI

#Vectors

  Boot           start
  first   0d20   firstHandler
  second  0d20   secondHandler
