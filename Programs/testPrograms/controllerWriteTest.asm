; Writes Program Memory through the controller, and gets turned away from what it may
; not touch.
;
; Writing code is the thing SplitBit's instruction set deliberately cannot do. The
; controller can, which is what makes a loader possible. The marker below is written and
; then read back through the controller, so the change is observed rather than assumed.
;
; The two refusals are the other half. Bank 2 is the bank table and is read only, so
; writing to it is a GuardViolation. Bank 200 has nothing registered in it, so naming it
; is a BankFault. Both handlers step the saved address past the instruction that was
; refused, the way any handler carrying on past a fault has to.
;
; Correct output is:
;   AA BB            the marker after being written through the controller
;   readonly
;   nobank
;   done

#Include print.asm

#Program

start:
  ; Aim both ends of the controller at the marker.
  SETD.0 Marker
  PSHD.0
  POPA
  POPB
  PSHA
  PSHB

  RSTA
  OUTA 0xE0         ; SourceBank = 0
  OUTA 0xE3         ; DestBank   = 0
  POPB
  OUTB 0xE1         ; SourceHigh
  OUTB 0xE4         ; DestHigh
  POPA
  OUTA 0xE2         ; SourceLow
  OUTA 0xE5         ; DestLow

  ; Write two bytes over the marker. This is Program Memory being changed at run time.
  INIA 0xAA
  OUTA 0xE9
  INIA 0xBB
  OUTA 0xE9

  ; Read them back the same way, to prove they landed.
  CALL readAndPrint
  CALL readAndPrint
  CALL lineFeed

  ; Bank 2 is the bank table, and it is read only.
  INIA 0d2
  OUTA 0xE3
  RSTA
  OUTA 0xE4
  OUTA 0xE5
  INIA 0d1
  OUTA 0xE9         ; Refused: GuardViolation.

  ; Bank 200 has nothing in it.
  INIA 0d200
  OUTA 0xE3
  INIA 0d1
  OUTA 0xE9         ; Refused: BankFault.

  SETD.0 Done
  CALL printString
  CALL lineFeed
  HALT

readAndPrint:
  INA 0xE9
  CALL printByteHex
  CALL blankSpace
  RET

readOnlyHandler:
  SETD.0 ReadOnly
  CALL printString
  CALL lineFeed
  BRI stepPastRefusal

noBankHandler:
  SETD.0 NoBank
  CALL printString
  CALL lineFeed
  BRI stepPastRefusal

; Steps the saved address past the refused instruction. OUT is two bytes, an opcode and
; a port, so two is what it takes.
stepPastRefusal:
  MVSD.0
  DPUP.0 0d14
  LDA.0
  CCF
  INIB 0d2
  ADD
  MVQA
  STA.0
  BRC carried
  RETI
carried:
  DPDN.0 0d01
  LDA.0
  INCA
  STA.0
  RETI

; Never executed.
Marker:
  0x00 0x00

#Data

ReadOnly:
"readonly"
NoBank:
"nobank"
Done:
"done"

#Vectors

  GuardViolation  readOnlyHandler
  BankFault       noBankHandler
