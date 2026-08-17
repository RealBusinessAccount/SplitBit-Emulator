; A program for CosmOS to load and run.
;
; It carries no library of its own and no vector table. Everything it can do it asks the
; system for, by name, through services.asm, which the system includes too. The order of
; the names in that one file is what gives them their numbers, so neither side has a
; number written down anywhere and the two cannot disagree about them.
;
; Compare it with Programs/loadable/hello.asm, which is the same idea one step earlier:
; that one talks to the console port itself and stops with HALT, because when it was
; written there was no system to ask and nowhere to give the machine back to.
;
; It is assembled for where it will live. #Base says so, and that makes the assembler
; write it out as a loadable program rather than as a boot image. Nothing relocates
; anything, so those addresses have to be the ones CosmOS puts it at.

#Include services.asm

#Program

  #Base 0x2000          ; Above the system, which keeps below here.

greet:
  SETD.0 Opening
  SWI osPrintString

  SETD.0 Question
  SWI osPrintString

  SETD.0 Answer
  INIB 0d31
  SWI osReadLine

  SETD.0 Hello
  SWI osPrintString
  SETD.0 Answer
  SWI osPrintString
  SETD.0 Ending
  SWI osPrintString

  ; Give the machine back. The system takes its Stack back at this point, so everything
  ; this program pushed goes with it.
  SWI osExit

#Data

  #Base 0x1000          ; And its data above the system's.

Opening:
"a program, loaded off a disk, running on the system that loaded it
"
Question:
"what should I call you? "
Hello:
"hello, "
Ending:
". that is all I do.
"

; Thirty one characters and the zero byte that ends them.
Answer:
  #Reserve 0d32
