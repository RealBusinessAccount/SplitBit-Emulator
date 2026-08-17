; The services the system offers, named and numbered.
;
; Both sides include this. The system follows it with handlers for the ones it implements.
; A program that only calls them includes this and nothing else, and can then say them by
; name, because a line with a name and nothing after it declares what a vector is called
; and what number it has without claiming to implement it.
;
; The order here is what fixes the numbers, and it is fixed in one file, so the two sides
; cannot disagree about them and nobody has to write a number down. Adding a service goes
; at the end: putting one in the middle would renumber everything after it, and any
; program already assembled against the old numbers would call the wrong thing.
;
; Written by Anachronaut

#Vectors

  osPrintString         ; DP0 names a string. Prints it.
  osReadLine            ; DP0 names somewhere to put a line read from the console.
  osExit                ; Give the machine back to the system.
