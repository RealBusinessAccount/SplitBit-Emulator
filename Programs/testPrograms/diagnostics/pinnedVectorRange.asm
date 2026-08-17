; A vector pinned to a number that is not anybody's to give.
;
; 100 is in the range the assembler hands out by itself. A program that pinned one there
; would be claiming a number that the assembler might also give to the next trap somebody
; declared, which is exactly the collision pinning exists to prevent.

#Program

start:
  SWI mine
  HALT

myHandler:
  RETI

#Vectors

  Boot        start
  mine  0d100 myHandler
