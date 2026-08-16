; Reads Program Memory through the memory controller.
;
; Nothing on SplitBit could do this before. The CPU cannot reach its own code, which is
; what a Harvard machine is, and this is the device that can.
;
; The bytes read back are a marker written into the Program Segment after the HALT, where
; nothing executes them. The controller is aimed at it using the label's own address, so
; this checks the controller against what the source says rather than against a guess
; about where the assembler put things.
;
; The address steps on by itself, so reading a run of bytes is a loop over one
; instruction rather than four.
;
; Correct output is:
;   DE AD BE EF      the marker, read out of Program Memory
;   01 FF            bank 0's record in bank 2: present, owned by the machine
;   00 00            and its capacity, where zero means the whole 64K

#Include print.asm

#Program

start:
  ; Aim the controller at the marker, using the marker's own address.
  SETD.0 Marker
  PSHD.0            ; High byte, then low, so the low byte comes off first.
  POPA
  POPB
  PSHA              ; Keep the low byte while A is needed for something else.

  RSTA
  OUTA 0xE0         ; SourceBank = 0, which is Program Memory.
  OUTB 0xE1         ; SourceHigh
  POPA
  OUTA 0xE2         ; SourceLow

  CALL readAndPrint
  CALL readAndPrint
  CALL readAndPrint
  CALL readAndPrint
  CALL lineFeed

  ; Now the bank table, which is bank 2. Bank 0's record comes first.
  INIA 0d2
  OUTA 0xE0
  RSTA
  OUTA 0xE1
  OUTA 0xE2

  CALL readAndPrint     ; Flags: present.
  CALL readAndPrint     ; Owner: the machine itself.
  CALL lineFeed
  CALL readAndPrint     ; Capacity, high byte.
  CALL readAndPrint     ; Capacity, low byte.
  CALL lineFeed
  HALT

readAndPrint:
  INA 0xE9
  CALL printByteHex
  CALL blankSpace
  RET

; Never executed. It is here to be read rather than run.
Marker:
  0xDE 0xAD 0xBE 0xEF
