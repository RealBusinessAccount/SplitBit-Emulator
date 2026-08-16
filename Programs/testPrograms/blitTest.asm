; Blits and fills.
;
; A blit moves a run of bytes between any two banks, including from one place in a bank
; to another. A fill writes one byte across a run. Both are instantaneous: waiting
; belongs to a peripheral that has something to wait for, not to the moving of bytes.
;
; Everything a transfer will touch is checked before any of it moves, so a transfer that
; would run out of bank refuses outright rather than stopping halfway and leaving memory
; in a state nobody asked for. The last case here proves that: the blit is refused, and
; the bytes it would have written are still what they were.
;
; Correct output is:
;   blitted           copied from one place in Data Memory to another
;   ....              filled with a byte of our choosing
;   DE AD             blitted from Data Memory into Program Memory
;   untouched         a refused blit moved nothing at all
;   ABABCDEFGH        an overlapping blit slid the bytes rather than repeating one

#Include print.asm

#Program

start:
  ; ---- A blit inside Data Memory, which is what a memcpy is here. ----
  SETD.0 Message
  CALL aimSource
  SETD.0 Landing
  CALL aimDest
  INIA 0d8
  CALL setLength        ; "blitted" and its terminator.
  INIA 0x01
  OUTA 0xE8             ; Blit.

  SETD.0 Landing
  CALL printString
  CALL lineFeed

  ; ---- A fill, with a byte of our choosing rather than only zero. ----
  SETD.0 Landing
  CALL aimDest
  INIA 0x2E             ; '.', into SourceLow, which is where a fill takes its byte.
  OUTA 0xE2
  INIA 0d4
  CALL setLength
  INIA 0x02
  OUTA 0xE8             ; Fill.

  ; Terminate it so printString knows where to stop.
  SETD.0 Landing
  DPUP.0 0d04
  RSTA
  STA.0
  SETD.0 Landing
  CALL printString
  CALL lineFeed

  ; ---- Data Memory into Program Memory. This is what a loader does. ----
  SETD.0 Code
  CALL aimSource
  SETD.0 Target
  CALL aimDestProgram
  INIA 0d2
  CALL setLength
  INIA 0x01
  OUTA 0xE8             ; Blit.

  ; Read it back out of Program Memory to prove it landed.
  SETD.0 Target
  CALL aimSourceProgram
  CALL readAndPrint
  CALL readAndPrint
  CALL lineFeed

  ; ---- A blit that would run past the end of bank 2. ----
  ; Bank 2 is 2048 bytes. Starting at 2040 and asking for 16 does not fit, so the whole
  ; thing is refused and Landing keeps what it already had.
  SETD.0 Untouched
  CALL aimSource
  SETD.0 Landing
  CALL aimDest
  INIA 0d10
  CALL setLength
  INIA 0x01
  OUTA 0xE8             ; This one works, so Landing says "untouched".

  INIA 0d2
  OUTA 0xE0             ; SourceBank = 2, the bank table.
  INIA 0x07
  OUTA 0xE1
  INIA 0xF8
  OUTA 0xE2             ; 0x07F8, eight bytes from the end.
  SETD.0 Landing
  CALL aimDest
  INIA 0d16
  CALL setLength
  INIA 0x01
  OUTA 0xE8             ; Refused: it would read past the end of bank 2.

  SETD.0 Landing
  CALL printString
  CALL lineFeed

  ; ---- A blit whose source and destination overlap. ----
  ; Sliding a run of bytes along inside its own bank is an ordinary thing to want, so it
  ; works rather than quietly repeating the first byte the way a naive forward copy does.
  SETD.0 Slide
  CALL aimSource
  SETD.0 Slide
  DPUP.0 0d02
  CALL aimDest
  INIA 0d8
  CALL setLength
  INIA 0x01
  OUTA 0xE8

  SETD.0 Slide
  CALL printString
  CALL lineFeed
  HALT

; ---- Helpers. DP0 holds the address to aim at. ----

aimSource:
  INIA 0d1              ; Bank 1, Data Memory.
  OUTA 0xE0
  BRI aimSourceAddress
aimSourceProgram:
  RSTA                  ; Bank 0, Program Memory.
  OUTA 0xE0
aimSourceAddress:
  PSHD.0
  POPA
  POPB
  OUTB 0xE1
  OUTA 0xE2
  RET

aimDest:
  INIA 0d1              ; Bank 1, Data Memory.
  OUTA 0xE3
  BRI aimDestAddress
aimDestProgram:
  RSTA                  ; Bank 0, Program Memory.
  OUTA 0xE3
aimDestAddress:
  PSHD.0
  POPA
  POPB
  OUTB 0xE4
  OUTA 0xE5
  RET

; A is the length, which is never more than a byte in this program.
setLength:
  PSHA
  RSTA
  OUTA 0xE6
  POPA
  OUTA 0xE7
  RET

readAndPrint:
  INA 0xE9
  CALL printByteHex
  CALL blankSpace
  RET

; The refused blit is caught so the program can carry on and show that nothing moved.
; The command write is two bytes, an opcode and a port, so stepping by two gets past it.
refusedHandler:
  MVSD.0
  DPUP.0 0d14
  LDA.0
  CCF
  INIB 0d2
  ADD
  MVQA
  STA.0
  BRC refusedCarried
  RETI
refusedCarried:
  DPDN.0 0d01
  LDA.0
  INCA
  STA.0
  RETI

; Never executed, only written over.
Target:
  0x00 0x00

#Data

Message:
"blitted"
Untouched:
"untouched"
Code:
  0xDE 0xAD

Landing:
  #Reserve 0d16

Slide:
"ABCDEFGH"
  #Reserve 0d4

#Vectors

  BankFault  refusedHandler
