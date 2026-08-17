; Tests interrupt on input: the console asking for attention instead of being asked.
;
; The control port has two bits and they are independent of one another. Bit 0 puts the
; console in key mode; bit 1 says to put the interrupt line up when a byte arrives. The
; console is on port 0x00, so that is the vector a key comes through - a device raises its
; line on its base port, and the status and control ports belong to the same device as the
; data port.
;
; The main program does nothing at all but wait to be told it is finished. It never looks
; at the console, which is the whole point: every byte is dealt with by the handler.
;
; What the status bits mean:
;   bit 0  READY       reading the data port will not have to wait
;   bit 1  ENDED       input has run out for good
;   bit 2  KEYMODE     the console is in key mode
;   bit 3  INTERRUPTS  the console is set to raise its line when a byte arrives
;
; This runs with input from a file rather than a terminal, so key mode has no terminal to
; put into another state and nothing here depends on one. A pipe with bytes in it is a
; console with keys waiting as far as the console is concerned.

#Include console.asm

#Program

start:
  CIF                       ; Nothing gets through until there is something to catch it.

  SETD.0 Banner
  CALL printString
  CALL newLine

  ; Key mode and interrupt on input, asked for in one write. Neither bit depends on the
  ; other, so there is no order to get wrong.
  INIA 0x03
  OUTA 0x02
  SETD.0 AskedLabel
  CALL printString
  CALL showStatus

  SETD.0 ArrivedLabel
  CALL printString
  CALL newLine

  SIF                       ; From here a byte arriving runs keyHandler.

waitLoop:
  ; Waiting without looking. Nothing in this loop touches the console, so every byte that
  ; comes out below was put there by something that interrupted this.
  SETD.3 Finished
  LDA.3
  RSTB
  OR                        ; Q is the flag, so this is a test for zero.
  BRQ waitLoop

  CALL newLine
  RSTA
  OUTA 0x02                 ; Line mode and no interrupts, the way it was found.
  SETD.0 DoneLabel
  CALL printString
  CALL showStatus
  HALT

; Entered because the console had something to say. It is never called.
;
; DP3 is used freely here: an interrupt saves all four Data Pointers and RETI puts them
; back, so a handler cannot disturb what it interrupted no matter what it touches.
keyHandler:
  INA 0x01
  INIB 0x02                 ; ENDED
  AND
  BNQ keyEnded
  INA 0x00                  ; The byte this interrupt was about.
  OUTA 0x00                 ; Nothing echoes in key mode, so the program does it.
  RETI

keyEnded:
  ; The end of input raises the line once, so a program driven entirely by interrupts
  ; still finds out that nothing more is coming. Without it this would wait forever for a
  ; key that cannot arrive.
  SETD.3 Finished
  INIA 0x01
  STA.3
  RETI

; Prints the status byte as hex and then names the bits that are up, so a change in the
; output says which bit moved rather than only that the number is different.
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
  PSHA

  INIB 0x04
  AND
  BRQ showNotKeys
  SETD.0 KeysWord
  CALL printString
showNotKeys:
  POPA

  INIB 0x08
  AND
  BRQ showNotInterrupts
  SETD.0 InterruptsWord
  CALL printString
showNotInterrupts:
  CALL newLine
  RET

#Data

Banner:
"console input interrupts"

AskedLabel:
"asked for:  "
ArrivedLabel:
"what arrived:"
DoneLabel:
"at the end: "

ReadyWord:
"ready "
EndedWord:
"ended "
KeysWord:
"keys "
InterruptsWord:
"interrupts "

; Set by the handler when the console says there will be no more bytes. It is the only
; thing the handler and the program it interrupts have to say to each other.
Finished:
  0x00

#Vectors

  Boot         start
  Device 0x00  keyHandler
