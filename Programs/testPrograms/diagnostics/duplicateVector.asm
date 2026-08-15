; Two handlers claiming the same vector.
;
; Device lines name a port directly, so two of them can collide even though the
; assembler numbers the named vectors itself.

#Program

start:
  HALT

firstHandler:
  RETI

secondHandler:
  RETI

#Vectors

  Device 0x10  firstHandler
  Device 0x10  secondHandler
