; A string written into the Program Segment.
;
; This used to assemble. The string contributed no bytes and no message: the second pass
; has a case for putting a string in the Data buffer and none for the Program buffer, so
; it fell through the switch and was gone. A program written this way would branch to a
; label that pointed at whatever followed instead.
;
; It is refused rather than emitted, because a string in Program Memory could not be read
; by the program holding it. No instruction on this machine reads Program Memory; only the
; memory controller can. Anybody writing this meant #Data.

#Program

start:
  SETD.0 Greeting
  HALT

Greeting:
"this is not where this goes"
