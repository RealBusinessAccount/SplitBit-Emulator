; Tests BRD, the only branch whose destination is not written into the program.
;
; A table of addresses in the Data Segment is walked with one Data Pointer, each
; entry is pulled out with LDD, and BRD jumps to it. That is dispatch: choosing
; where to go from data rather than from a branch the assembler laid down.
;
; Correct output is:
;   one
;   two
;   three
;   done

#Program

start:
  SETD.0 Handlers   ; DP0 walks the table of handler addresses.
  INIB 0d3          ; Three of them.

dispatchLoop:
  LDD.1.0           ; DP1 becomes the address of the next handler.
  BRD.1             ; Go there. The handler branches back to itself.

; Each handler prints its name and returns to the loop by hand. There is no CALL
; here on purpose, so that what BRD does is the only thing under test.
handlerOne:
  SETD.2 One
  CALL printDP2
  BRI nextHandler

handlerTwo:
  SETD.2 Two
  CALL printDP2
  BRI nextHandler

handlerThree:
  SETD.2 Three
  CALL printDP2
  BRI nextHandler

nextHandler:
  DPUP.0 0d02       ; Step over the two byte table entry.
  DECB
  BRB finished
  BRI dispatchLoop

finished:
  SETD.2 Done
  CALL printDP2
  HALT

printDP2:
  LDA.2
  BRA printDone
  OUTA 0x00
  INCD.2
  BRI printDP2
 printDone:
  INIA 0x0A
  OUTA 0x00
  RET

#Data

One:
"one"
Two:
"two"
Three:
"three"
Done:
"done"

; The dispatch table. Each name becomes the address of that handler.
Handlers:
handlerOne
handlerTwo
handlerThree
