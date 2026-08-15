; #Align before either segment has been opened.
;
; The directive moves a cursor along, and outside a segment there is no cursor for
; it to move, so this has to be an error rather than quietly doing nothing.

  #Align 0x100

#Program

start:
  HALT
