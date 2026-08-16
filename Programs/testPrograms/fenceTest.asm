; The fence.
;
; A guarded range is a fence rather than a wall. Any program may raise one and any
; program may lower it, so nobody is ever told no. What it stops is walking into
; something by accident, which is the failure that costs an afternoon: without it, code
; that gets walked over is found much later, when the wreckage is finally executed and
; the evidence is long gone.
;
; The handler reads the controller's destination registers to say where the refused write
; was aimed. That is the whole point of catching it at the instruction that did it: the
; address is still sitting there to be read.
;
; The addresses here are absolute rather than labels, so that this says the same thing no
; matter what else ends up in the Data Segment. Data Memory is 64K and this program uses
; a hundred bytes of it, so 0x0200 is empty ground.
;
; Correct output is:
;   outside ok        a write just below the fence went through
;   caught 0200       a write inside it was refused, and the handler says where
;   caught 01FC       a blit that merely clipped it was refused whole
;   read ok           reading inside the fence is allowed: it guards writing
;   lowered ok        after GuardOff the same write goes through
;   fenced 05         the bank table shows bank 1 present and fenced

#Include print.asm

#Program

start:
  ; Fence off 0x0200 to 0x020F in Data Memory.
  INIA 0d1
  OUTA 0xEB             ; GuardBank = 1
  INIA 0x02
  OUTA 0xEC
  RSTA
  OUTA 0xED             ; GuardStart = 0x0200
  INIA 0x02
  OUTA 0xEE
  INIA 0x0F
  OUTA 0xEF             ; GuardEnd = 0x020F
  INIA 0x10
  OUTA 0xE8             ; GuardOn

  ; Just below the fence is ordinary ground.
  INIA 0x01
  OUTA 0xE4
  INIA 0xFF
  OUTA 0xE5             ; Dest = 0x01FF
  INIA 0d1
  OUTA 0xE3             ; DestBank = 1
  INIA 0x41
  OUTA 0xE9
  SETD.0 OutsideOk
  CALL say

  ; Inside it is not.
  INIA 0x02
  OUTA 0xE4
  RSTA
  OUTA 0xE5             ; Dest = 0x0200
  INIA 0x42
  OUTA 0xE9             ; Refused.

  ; A blit from 0x01FC for eight bytes runs to 0x0203, so it clips the fence. It is
  ; refused whole rather than doing the four bytes that would have fitted.
  INIA 0x01
  OUTA 0xE4
  INIA 0xFC
  OUTA 0xE5             ; Dest = 0x01FC
  INIA 0d1
  OUTA 0xE0
  RSTA
  OUTA 0xE1
  OUTA 0xE2             ; Source = bank 1, 0x0000
  OUTA 0xE6
  INIA 0d8
  OUTA 0xE7             ; Length = 8
  INIA 0x01
  OUTA 0xE8             ; Refused.

  ; Reading inside a fence is allowed. A debugger has to be able to see what is being
  ; protected.
  INIA 0d1
  OUTA 0xE0
  INIA 0x02
  OUTA 0xE1
  RSTA
  OUTA 0xE2             ; Source = 0x0200
  INA 0xE9
  SETD.0 ReadOk
  CALL say

  ; Lower it, and the write that was refused goes through.
  INIA 0x11
  OUTA 0xE8             ; GuardOff
  INIA 0x02
  OUTA 0xE4
  RSTA
  OUTA 0xE5
  INIA 0x43
  OUTA 0xE9
  SETD.0 LoweredOk
  CALL say

  ; Raise it again, and read the flags back out of the bank table, where a fence is
  ; published along with everything else about a bank.
  INIA 0x10
  OUTA 0xE8
  INIA 0d2
  OUTA 0xE0
  RSTA
  OUTA 0xE1
  INIA 0d8
  OUTA 0xE2             ; Bank 1's record begins at 8.
  SETD.0 Fenced
  CALL printString
  CALL blankSpace
  INA 0xE9
  CALL printByteHex
  CALL lineFeed
  HALT

; Says where the refused write was aimed, by reading the controller's own registers.
guardHandler:
  SETD.0 Caught
  CALL printString
  CALL blankSpace
  INA 0xE4              ; DestHigh
  CALL printByteHex
  INA 0xE5              ; DestLow
  CALL printByteHex
  CALL lineFeed

  ; Step past the refused instruction. Every write here is an opcode and a port.
  MVSD.0
  DPUP.0 0d14
  LDA.0
  CCF
  INIB 0d2
  ADD
  MVQA
  STA.0
  BRC stepCarried
  RETI
stepCarried:
  DPDN.0 0d01
  LDA.0
  INCA
  STA.0
  RETI

say:
  CALL printString
  CALL lineFeed
  RET

#Data

OutsideOk:
"outside ok"
Caught:
"caught"
ReadOk:
"read ok"
LoweredOk:
"lowered ok"
Fenced:
"fenced"

#Vectors

  GuardViolation  guardHandler
