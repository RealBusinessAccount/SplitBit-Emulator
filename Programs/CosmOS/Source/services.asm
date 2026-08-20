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

; ---- What the system does with the disk on a program's behalf ----
;
; A loaded program that wanted a file used to include the whole filesystem, which is two
; and a half kilobytes of it carrying a private copy of code the system already has
; running. These are that code, reachable.
;
; NOTHING HERE MOUNTS ANYTHING. The system mounted the disk before it read the prompt, and
; there is one disk with one buffer registered as one bank; a program mounting it again was
; only ever an artefact of having its own copy of the library.
;
; Sizes are in bytes and fit the registers exactly. A file that can be read into Data
; Memory is under 64K by definition, so its length is sixteen bits: coming back it is DP3,
; going out it is A and B together, and neither direction needs a record in memory that
; both sides have to agree on the shape of.
  osFileRead     0d20   ; DP0 names it, DP1 says where. Q is zero if it read, DP3 is how many bytes.
  osFileSave     0d21   ; DP0 names it, DP1 is the bytes, A and B are how many. Q is zero if it saved.
  osFileDelete   0d22   ; DP0 names it. Q is zero if it went.
  osFileRename   0d23   ; DP0 is the name it has, DP1 the name it should have. Q is zero if it moved.

; ---- And with the console ----
;
; printString is already up there. This is the other half of what a program prints: a
; number, in decimal, without leading zeroes. A and B together, so one service covers both
; a line number and a byte count and there is no need for two.
  osPrintNumber  0d24

; ---- Stopping to look ----
;
; A breakpoint. Put SWI osBreak anywhere in a program and the system shows every register as
; the program had them, waits for a key, and carries on.
;
; NOTHING IS OVERWRITTEN, which is what makes this simple. A breakpoint that replaced an
; instruction would have to put it back to continue, and putting it back disarms the
; breakpoint - so firing twice would need the instruction to be stepped over and the
; breakpoint replaced behind it, and this machine has no way to step one instruction. An SWI
; costs two bytes of the program and fires for ever, because there was never anything to
; restore. The price is that it is part of the program: a build with breakpoints in it has
; different addresses from one without.
  osBreak        0d25
