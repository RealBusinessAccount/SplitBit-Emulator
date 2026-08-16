; The negative sense branches.
;
; A quarter of every conditional branch in the corpus used to be a branch over an
; unconditional one, because only "branch if zero" existed. Each of those needed a label
; invented purely to be jumped past, which is a cost in names as much as in bytes.
;
; These test the register directly, the way the positive ones do. A branch on this machine
; never depends on which instruction ran last, except for the two that read the Carry Flag
; and say so in their names.
;
; Each case is checked both ways round, so a branch that always went the same way would
; be caught rather than looking correct half the time.
;
; Correct output is:
;   QAB C qab c
;   9876543210

#Include print.asm

#Program

start:
  ; ---- Each one taken when it should be. ----
  RSTA
  INIB 0d1
  CCF
  ADD                   ; Q is 1, so not zero.
  BNQ qTaken
  BRI wrong
qTaken:
  INIA 0d81             ; 'Q'
  OUTA 0x00

  INIA 0d5
  BNA aTaken
  BRI wrong
aTaken:
  INIA 0d65             ; 'A'
  OUTA 0x00

  INIB 0d5
  BNB bTaken
  BRI wrong
bTaken:
  INIA 0d66             ; 'B'
  OUTA 0x00

  CCF
  BNC cTaken
  BRI wrong
cTaken:
  CALL blankSpace
  INIA 0d67             ; 'C'
  OUTA 0x00
  CALL blankSpace

  ; ---- And each one not taken when it should not be. ----
  RSTA
  RSTB
  CCF
  ADD                   ; Q is zero.
  BNQ wrong
  INIA 0d113            ; 'q'
  OUTA 0x00

  RSTA
  BNA wrong
  INIA 0d97             ; 'a'
  OUTA 0x00

  RSTB
  BNB wrong
  INIA 0d98             ; 'b'
  OUTA 0x00

  ; Set the carry by overflowing, then check BNC does not take it.
  INIA 0xFF
  INIB 0x01
  CCF
  ADD
  BNC wrong
  CALL blankSpace
  INIA 0d99             ; 'c'
  OUTA 0x00
  CALL lineFeed

  ; ---- A countdown, which is what the missing sense was mostly wanted for. ----
  ; Before these existed this loop needed a label to jump over, and now it does not.
  INIA 0d10
  SETD.0 Count
  STA.0
countLoop:
  LDA.0
  DECA                  ; Ten down to one becomes nine down to zero.
  INIB 0d48             ; '0'
  CCF
  ADD
  MVQA
  OUTA 0x00
  LDA.0
  DECA
  STA.0
  BNA countLoop         ; One instruction where it used to take two and a label.
  CALL lineFeed
  HALT

wrong:
  SETD.0 Wrong
  CALL printString
  CALL lineFeed
  HALT

#Data
Wrong:
"a branch went the wrong way"
Count:
  0x00
