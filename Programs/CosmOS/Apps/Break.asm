; Stopping a program to look at it.
;
; SWI osBreak shows every register as this program had them, waits for a key, and carries
; on. It is two bytes and it fires every time it is reached.
;
; WHY IT IS AN INSTRUCTION RATHER THAN SOMETHING SET FROM OUTSIDE. A breakpoint that was
; poked into a running program would have to overwrite an instruction, and then putting that
; instruction back in order to continue is the same act as disarming the breakpoint. Firing
; a second time would mean stepping over the restored instruction and putting the breakpoint
; back behind it, and this machine cannot step one instruction. Nothing is overwritten here,
; so there is nothing to restore and nothing to re-arm.
;
; The price is that it is part of the program. A build with breakpoints in it has different
; addresses from a build without, which is the same bargain every machine makes that has a
; break instruction.
;
; Correct output is two stops, showing A and B changing between them, and the addresses of
; the two SWIs.

#Include services.asm

#Program

  #Base 0x2000

start:
  SETD.0 Banner
  SWI osPrintString

  INIA 0d17
  INIB 0d34
  SETD.0 Marker
  SWI osBreak

  ; Something for the second stop to show as different.
  INIA 0d68
  INIB 0d85
  SETD.0 Banner
  SWI osBreak

  SETD.0 DoneText
  SWI osPrintString
  SWI osExit

#Data

  #Base 0x1000

Banner:
"two stops, and what the registers were at each
"
Marker:
"marker"
DoneText:
"carried on to the end
"
