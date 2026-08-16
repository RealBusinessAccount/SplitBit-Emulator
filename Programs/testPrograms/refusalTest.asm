; Tests a device refusing what it was asked to do.
;
; Interrupting is a device asking for attention later. Refusing is a device saying no to
; the instruction happening now, so it has to stop the machine where it stands instead of
; letting execution carry on past the mistake.
;
; The device on port 0x11 refuses everything, in both directions, so that this path can
; be exercised without the memory controller. A refusal names a software vector, so the
; handler knows what happened from the entry it arrived through.
;
; The handler steps the saved address past the instruction that was refused, the same way
; the fault handler steps past a byte that would not decode. Without that a bare RETI
; would meet the same refused instruction again forever.
;
; Correct output is:
;   caught      the handler caught a refused write
;   caught      and a refused read
;   done

#Include print.asm

#Program

start:
  INIA 0d1
  OUTA 0x11         ; Refused. The handler runs and steps us past this.

  INA 0x11          ; Refused as well, and reads are caught the same way.

  SETD.0 Done
  CALL printString
  CALL lineFeed
  HALT

; A refusal arrives with a full frame, so the handler may use whatever it likes.
refusalHandler:
  CALL reportRefusal

  ; Step the saved address past the instruction that was refused. Both OUT and IN are
  ; two bytes, an opcode and a port, so two is what it takes.
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

reportRefusal:
  SETD.0 Caught
  CALL printString
  CALL lineFeed
  RET

#Data

Caught:
"caught"
Done:
"done"

#Vectors

  GuardViolation  refusalHandler
