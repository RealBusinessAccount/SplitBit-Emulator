; The services the system offers, named and numbered.
;
; Both sides include this. The system follows it with handlers for the ones it implements.
; A program that only calls them includes this and nothing else, and can then say them by
; name, because a line with a name and nothing after it declares what a vector is called
; and what number it has without claiming to implement it.
;
; THE NUMBERS ARE WRITTEN DOWN HERE, and that is the only place they are written. They
; used to be decided by the order of the lines, which worked and was quietly fragile: a
; service inserted in the middle renumbered everything after it, and a program already
; assembled against the old numbers would go on calling the number rather than the name.
; Worse, the numbers a program got for its OWN traps moved depending on whether it had
; included this file, and a program that had not was given 16 - which is osPrintString.
;
; So these are pinned. They come from the range set aside for numbers that two separately
; assembled programs have to agree about; everything a program names for itself is drawn
; from higher up and cannot collide with these however it is built. Adding a service takes
; the next free number here and disturbs nothing.
;
; Written by Anachronaut

#Vectors

  osPrintString  0d16   ; DP0 names a string. Prints it.
  osReadLine     0d17   ; DP0 names somewhere to put a line read from the console.
  osExit         0d18   ; Give the machine back to the system.
  osArgument     0d19   ; DP0 names somewhere to put the rest of the run command.
