; Tests MVDS, which copies a Data Pointer into the Stack Pointer.
;
; This is the dangerous one. Moving the Stack Pointer abandons everything below the new
; position: return addresses, saved registers, interrupt frames, all of it. Nothing is
; unwound, because moving the Stack does not move what is on it.
;
; It is here for one job, and that job is what this program acts out. A system that runs
; other programs and takes the machine back afterwards cannot do so without it. A program
; that gives up part way through leaves whatever it pushed behind, and nothing is ever
; going to return and tidy it away. Without MVDS the Stack only ever moves downward, a
; little further with every program run, and a shell cannot outlive many of them.
;
; The other half of the story is that moving the Stack does not destroy what was on it.
; A routine that puts the Stack Pointer back where it found it returns perfectly normally,
; because the frame was only stepped away from. Both halves are acted out here, and the
; nesting case with them: two routines that each borrow a Stack, one inside the other,
; each keeping its own saved Stack Pointer on the Stack it borrowed. A fixed location in
; Data Memory would fail exactly there, and would fail silently.
;
; Both sequences are the ones the Programming Manual prints under "The Stack Pointer,
; Set By Hand", so if either example ever stops working this test says so.
;
; Correct output is:
;   stack reclaim test
;   at start:  FFFF
;   spent:     FFF7
;   reclaimed: FFFF
;   still good: 33
;   borrowed:  7 and 9
;   back home: FFFF

#Include console.asm

#Program

start:
  SETD.0 Banner
  CALL printString
  CALL newLine

  ; Where the Stack is before anything has touched it. Read first, so that no call has
  ; had a chance to move it.
  MVSD.0
  SETD.1 SavedStack
  STD.0.1

  SETD.0 StartLabel
  CALL printString
  SETD.0 SavedStack
  CALL printWordHex
  CALL newLine

  ; Spend some Stack and never give it back. This is not a subroutine, because a
  ; subroutine that pushed without popping would take its own return address with it.
  ; It stands in for a program that stops half way through.
  INIA 0x11
  PSHA PSHA PSHA PSHA
  PSHA PSHA PSHA PSHA

  MVSD.0
  SETD.1 Spent
  STD.0.1

  SETD.0 SpentLabel
  CALL printString
  SETD.0 Spent
  CALL printWordHex
  CALL newLine

  ; Take it back. Nothing pops those eight bytes: they are simply no longer on the Stack,
  ; which is the whole of what reclaiming means.
  SETD.1 SavedStack
  LDD.0.1
  MVDS.0

  MVSD.0
  SETD.1 Reclaimed
  STD.0.1

  SETD.0 ReclaimedLabel
  CALL printString
  SETD.0 Reclaimed
  CALL printWordHex
  CALL newLine

  ; A Stack Pointer in the right place is not proof that the Stack works. Push something
  ; through it and get it back, so that the reclaimed Stack is shown to be usable and not
  ; merely well positioned.
  SETD.0 GoodLabel
  CALL printString
  INIA 0d33
  PSHA
  RSTA
  POPA
  CALL printByteDecimal
  CALL newLine

  ; ---- Moving the Stack and coming back from it ----
  ; borrower runs on a Stack of its own and returns with a plain RET, which only works
  ; because putting the Stack Pointer back leaves the frame exactly as CALL left it.
  CALL borrower

  SETD.0 BorrowedLabel
  CALL printString
  SETD.0 OuterResult
  LDA.0
  CALL printByteDecimal
  SETD.0 AndText
  CALL printString
  SETD.0 InnerResult
  LDA.0
  CALL printByteDecimal
  CALL newLine

  ; The Stack has to be back where it started, or the nesting quietly lost track of it.
  MVSD.0
  SETD.1 Reclaimed
  STD.0.1
  SETD.0 HomeLabel
  CALL printString
  SETD.0 Reclaimed
  CALL printWordHex
  CALL newLine
  HALT

; Borrows a Stack, works on it, calls something that does the same thing again, then puts
; the Stack back and returns. The old Stack Pointer goes onto the borrowed Stack rather
; than into a fixed place in memory, which is what makes the nesting safe: the inner
; routine keeps its own copy on its own Stack and cannot tread on this one.
borrower:
  MVSD.3
  SETD.0 OuterTop
  MVDS.0
  PSHD.3

  INIA 0d7
  PSHA
  RSTA
  POPA
  SETD.1 OuterResult
  STA.1

  CALL innerBorrower

  POPD.3
  MVDS.3
  RET

; The same again, one level down and on a Stack of its own.
innerBorrower:
  MVSD.3
  SETD.0 InnerTop
  MVDS.0
  PSHD.3

  INIA 0d9
  PSHA
  RSTA
  POPA
  SETD.1 InnerResult
  STA.1

  POPD.3
  MVDS.3
  RET

#Data

Banner:
"stack reclaim test"
StartLabel:
"at start:  "
SpentLabel:
"spent:     "
ReclaimedLabel:
"reclaimed: "
GoodLabel:
"still good: "
BorrowedLabel:
"borrowed:  "
AndText:
" and "
HomeLabel:
"back home: "

SavedStack:
  0x00 0x00
Spent:
  0x00 0x00
Reclaimed:
  0x00 0x00
OuterResult:
  0x00
InnerResult:
  0x00

; Two places a Stack can live, sixty four bytes each. The label is on the last byte of
; each, because a Stack grows downward from wherever it is set.
OuterStack:
  #Reserve 0d63
OuterTop:
  0x00
InnerStack:
  #Reserve 0d63
InnerTop:
  0x00

#Vectors

  Boot  start
