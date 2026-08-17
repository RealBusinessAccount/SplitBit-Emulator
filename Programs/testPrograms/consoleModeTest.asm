; Exercises the console's status and control ports.
;
; The console answers on three ports now: 0x00 for bytes as it always did, 0x01 for what
; it is doing, and 0x02 to say which mode it should be in. The point of the mode is that
; the data port never changed, so this checks the old behaviour is still there as much as
; it checks the new behaviour arrived.
;
; What the status bits mean:
;   bit 0  READY    reading the data port will not have to wait
;   bit 1  ENDED    input has run out for good
;   bit 2  KEYMODE  the console is in key mode
;
; There is a fourth bit, for whether the console interrupts on input, and nothing here
; sets it. Polling and interrupting are the two ways to get a byte and this is the one
; about polling; consoleInterruptTest.asm is the other.
;
; This runs with input from a file rather than a terminal, so key mode has no terminal to
; put into another state and the mode bit is the only thing that changes. That is on
; purpose: the same program has to work either way, and a test that needed a terminal
; could not run here at all.

#Include console.asm

#Program

start:
  SETD.0 Banner
  CALL printString
  CALL newLine

  ; ---- What mode does it start in ----
  ;
  ; Nothing has been written to the control port, so this is how the machine comes up, and
  ; every program written before these ports existed runs in exactly this.
  SETD.0 AtStartLabel
  CALL printString
  CALL showStatus

  ; ---- Into key mode ----
  INIA 0x01
  OUTA 0x02
  SETD.0 KeyModeLabel
  CALL printString
  CALL showStatus

  ; ---- Read what is waiting ----
  ;
  ; Reading until ENDED rather than until a count, which is the thing that could not be
  ; done before: 0xFF from the data port used to mean both "the byte 0xFF" and "there is
  ; no more", and nothing could tell those apart.
  SETD.0 ReadLabel
  CALL printString
  CALL newLine
readLoop:
  INA 0x01
  INIB 0x02             ; ENDED
  AND
  BNQ readDone
  INA 0x00
  OUTA 0x00             ; Nothing echoes in key mode, so the program does it.
  BRI readLoop
readDone:
  CALL newLine

  ; ---- The status at the end of input ----
  ;
  ; ENDED is set and READY is clear, although a read would answer at once here: what it
  ; answers is 0xFF standing in for nothing. READY means there is a byte to be had, so the
  ; loop above stops on its own rather than taking imaginary bytes forever.
  SETD.0 AtEndLabel
  CALL printString
  CALL showStatus

  ; ---- Back to line mode ----
  RSTA
  OUTA 0x02
  SETD.0 LineModeLabel
  CALL printString
  CALL showStatus

  HALT

; Prints the status byte as hex and then names the bits that are up, so that a change in
; the output says which bit moved rather than only that the number is different.
showStatus:
  INA 0x01
  PSHA
  CALL printByteHex
  INIA 0x20
  OUTA 0x00
  POPA
  PSHA

  INIB 0x01
  AND
  BRQ showNotReady
  SETD.0 ReadyWord
  CALL printString
showNotReady:
  POPA
  PSHA

  INIB 0x02
  AND
  BRQ showNotEnded
  SETD.0 EndedWord
  CALL printString
showNotEnded:
  POPA

  INIB 0x04
  AND
  BRQ showNotKeys
  SETD.0 KeysWord
  CALL printString
showNotKeys:
  CALL newLine
  RET

#Data

Banner:
"console mode ports"

AtStartLabel:
"at start:   "
KeyModeLabel:
"key mode:   "
AtEndLabel:
"at the end: "
LineModeLabel:
"line mode:  "
ReadLabel:
"what came in:"

ReadyWord:
"ready "
EndedWord:
"ended "
KeysWord:
"keys "

#Vectors

  Boot  start
