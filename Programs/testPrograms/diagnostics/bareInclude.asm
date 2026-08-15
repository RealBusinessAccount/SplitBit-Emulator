; Deliberately broken, to check that the assembler still catches it.
; The file ends straight after the keyword, so there is no name to read. This
; used to walk into whatever the array happened to hold and crash.

#Program

start:
  HALT

#Include
