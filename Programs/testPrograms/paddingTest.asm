; Tests #Align and #Reserve by printing the addresses they produce.
;
; Both directives only move the cursor along, so what they do is entirely visible in
; where the labels after them land. The program pushes each pointer and prints the two
; bytes of its address, which is the only way a SplitBit program can look at one.
;
; Aligned is asked for on a page boundary, so its low byte has to be 0x00. Reserved
; follows one byte of data and a reservation of 0x30, so it lands 0x31 further on.
;
; Correct output is:
;   00 31

#Include print.asm

#Program

start:
  ; The aligned label. Only the low byte is interesting: a page boundary means zero.
  SETD.0 Aligned
  PSHD.0            ; High byte, then low, so the low byte comes off first.
  POPA
  POPB
  CALL printByteHex
  CALL blankSpace

  ; The reserved region. Reserved sits one byte of data plus 0x30 reserved bytes past
  ; Aligned, so its low byte says how far the reservation moved the cursor.
  SETD.0 Reserved
  PSHD.0
  POPA
  POPB
  CALL printByteHex
  CALL lineFeed
  HALT

#Data

  #Align 0x100
Aligned:
  0x41              ; One byte of real data, so the cursor is one past the boundary.
  #Reserve 0x30
Reserved:
  0x42
