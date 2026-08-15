; #Align with no number after it.
;
; Without this check the next token is taken as the alignment, which would silently
; align to whatever the following instruction happened to be worth.

#Program

start:
  HALT
  #Align
