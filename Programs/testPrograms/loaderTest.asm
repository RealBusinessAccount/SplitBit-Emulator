; A program that loads a program.
;
; This is what the memory controller was built for. The bytes of a small routine sit in
; the Data Segment the way a program read off a disk would. The loader blits them into
; Program Memory, writes their address into a software vector, and calls it. Nothing
; about that routine was known to the assembler as code: to the loader it is data, and it
; becomes code only because it was put somewhere the CPU fetches from.
;
; Installing the vector at run time is the part worth watching. The argument that started
; the whole controller design was that a vector table nothing can write is not really a
; vector table. Vector 20 is empty when this program starts and holds a real handler by
; the time it is called, and nothing but the controller could have put it there.
;
; WHAT THIS DOES NOT SOLVE:
;
; The payload works at whatever address it lands at only because it contains no
; addresses. It is INIA and OUTA and a RETI, and none of those name a place. The moment a
; loaded routine contains a branch, a CALL, or a SETD, it holds an address that was fixed
; when it was assembled, and it will be wrong everywhere except where it was assembled
; for. SplitBit has no answer to that yet. Loading works; relocating does not exist.
;
; Correct output is:
;   before            the vector is still empty here
;   loaded            printed by code that was data a moment ago
;   back              and RETI came home

#Include print.asm

#Program

start:
  SETD.0 Before
  CALL say

  ; ---- Put the payload into Program Memory. ----
  SETD.0 Payload
  CALL aimSourceData
  SETD.0 LandingZone
  CALL aimDestProgram
  INIA 0d29
  CALL setLength
  INIA 0x01
  OUTA 0xE8             ; Blit: Data Memory into Program Memory.

  ; ---- Write its address into software vector 20. ----
  ; The table is at 0xFC00 and entries are two bytes, so vector 20 is at 0xFC28.
  RSTA
  OUTA 0xE3             ; DestBank = 0, Program Memory.
  INIA 0xFC
  OUTA 0xE4
  INIA 0x28
  OUTA 0xE5
  SETD.0 LandingZone
  PSHD.0
  POPA
  POPB
  OUTB 0xE9             ; High byte of the handler's address.
  OUTA 0xE9             ; Low byte. The Data port steps on by itself.

  ; ---- Call it. ----
  SWI 0d20

  SETD.0 Back
  CALL say
  HALT

; DP0 holds the address to aim at.
aimSourceData:
  INIA 0d1
  OUTA 0xE0
  PSHD.0
  POPA
  POPB
  OUTB 0xE1
  OUTA 0xE2
  RET

aimDestProgram:
  RSTA
  OUTA 0xE3
  PSHD.0
  POPA
  POPB
  OUTB 0xE4
  OUTA 0xE5
  RET

setLength:
  PSHA
  RSTA
  OUTA 0xE6
  POPA
  OUTA 0xE7
  RET

say:
  CALL printString
  CALL lineFeed
  RET

; Where the payload lands. Reserving it means the assembler knows the room is spoken for,
; so nothing else is ever placed here.
LandingZone:
  #Reserve 0d48

#Data

Before:
"before"
Back:
"back"

; The payload, as bytes rather than as code. It prints "loaded" and returns. Written out
; by hand because SplitBit has no linker: to this program it is just so much data.
;
;   INIA 'l'  OUTA 0    INIA 'o'  OUTA 0   ... and so on, then RETI
Payload:
  0x26 0x6C 0xD1 0x00
  0x26 0x6F 0xD1 0x00
  0x26 0x61 0xD1 0x00
  0x26 0x64 0xD1 0x00
  0x26 0x65 0xD1 0x00
  0x26 0x64 0xD1 0x00
  0x26 0x0A 0xD1 0x00
  0x19
