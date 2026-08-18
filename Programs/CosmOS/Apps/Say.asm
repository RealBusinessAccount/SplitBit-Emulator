; A program that is told what to work on.
;
; Everything loaded before this one did the same thing however it was started, because
; there was no way to tell one anything. A tool that edits a document needs to know which
; document, and that is the same need a dozen other things will have, so it is a service
; rather than something an editor arranges for itself.
;
;   run                 says it was given nothing
;   run whatever else   says "whatever else"
;
; The whole rest of the line arrives, spaces and all, rather than a list of words. What
; counts as an argument is the program's business; the system's business is handing over
; what was typed.

#Include services.asm

#Program

  #Base 0x2000

start:
  SETD.0 Given
  INIB 0d64
  SWI osArgument

  SETD.0 Given
  LDA.0
  BRA sayNothing

  SETD.0 SaidText
  SWI osPrintString
  SETD.0 Given
  SWI osPrintString
  BRI sayEnd

sayNothing:
  SETD.0 NothingText
  SWI osPrintString

sayEnd:
  SETD.0 NewLine
  SWI osPrintString
  SWI osExit

#Data

  #Base 0x1000

SaidText:
"it says: "
NothingText:
"nothing was said"
NewLine:
  0x0A 0x00

Given:
  #Reserve 0d64
