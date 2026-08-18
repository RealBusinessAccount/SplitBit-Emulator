; A loaded program that is interrupted by the console rather than asking it for anything.
;
; Until the loadable program format could carry vectors, this could not be written. A
; handler has to be an address in the vector table, and a program that is not the one the
; machine booted from had no way to say what its vectors were, so interrupts belonged to
; boot images and every loaded program had to poll. Snake polls for exactly that reason.
;
; What this shows is the whole path: the assembler writes the vectors into the file, the
; system installs them when the program is run, the console raises its line, the handler
; runs, and the system takes the vectors back out again when the program gives the machine
; back. Nothing in the waiting loop below looks at the console at all.
;
; The vector is named by port, because a device interrupts on the port it is plugged into
; and the console is on port 0x00.

#Include services.asm

#Program

  #Base 0x2000

start:
  CIF                       ; Nothing arrives until there is something to catch it.

  ; Set rather than trusted to be zero. Running a program a second time does not load it
  ; again, so its Data Segment is exactly as the last run left it - and the last thing the
  ; last run did was set this.
  RSTA
  SETD.0 Stopping
  STA.0

  SETD.0 Banner
  CALL printString
  CALL newLine

  ; Key mode and interrupt on input, in one write, since the two control bits are
  ; independent of each other.
  INIA 0x03
  OUTA 0x02
  SIF

wait:
  ; This loop is the point. It never touches the console, so every character that appears
  ; below was put there by something that interrupted it.
  SETD.3 Stopping
  LDA.3
  RSTB
  OR
  BRQ wait

  CALL newLine
  RSTA
  OUTA 0x02                 ; Line mode and no interrupts, the way it was found.
  SETD.0 DoneText
  CALL printString
  CALL newLine
  SWI osExit

; Entered because the console had something to say. Never called.
keyHandler:
  INA 0x01
  INIB 0x01                 ; READY: is there a byte, as opposed to the end of input?
  AND
  BRQ keyNoByte
  INA 0x00

  INIB 0x71                 ; q, which is how this program is stopped.
  XOR
  BRQ keyStop

  OUTA 0x00                 ; Nothing echoes in key mode, so the handler does it.
  RETI

keyNoByte:
  ; The end of input raises the line once as well, so a program driven entirely by
  ; interrupts is told when nothing more is coming instead of waiting for ever.
keyStop:
  SETD.3 Stopping
  INIA 0x01
  STA.3
  RETI

#Data

  #Base 0x1000

Banner:
"keys, by interrupt. q stops."
DoneText:
"the console has been handed back"

; The only thing the handler and the loop it interrupts have to say to each other.
Stopping:
  0x00

#Vectors

  Boot         start
  Device 0x00  keyHandler

#Include console.asm
