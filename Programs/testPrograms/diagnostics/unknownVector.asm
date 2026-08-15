; SWI names something that was never given a handler.
;
; A vector name is not a label, so the usual "undefined label" error would be
; misleading. It has to say that the name needs a #Vectors entry.

#Program

start:
  SWI neverDeclared
  HALT
