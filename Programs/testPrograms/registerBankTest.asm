; Giving a bank number to a device's memory.
;
; This is the whole sequence an OS goes through: ask the bus registry which ports bring
; memory, give one of them a bank number, and then reach it with the controller like any
; other bank. A device's memory is unreachable until it has a number, and the controller
; is the only thing that can reach it even then.
;
; How big the bank is comes from the device rather than from this program. Capacity was
; settled when the machine was built, so software asserting it could only ever be wrong.
;
; The device on port 0x12 owns 256 bytes and fills them with whatever byte is written to
; its port, which stands in for a disk controller reading a sector.
;
; Correct output is:
;   flags 01          the registry says port 0x12 brings memory
;   01 12 01 00       bank 5's record: present, owned by port 0x12, 256 bytes
;   5A 5A             the device's memory, reached through the controller
;   refused           registering over one of the machine's own banks
;   refused           and registering memory from a port that brings none

#Include print.asm

#Program

start:
  ; Ask the registry whether port 0x12 brings memory.
  INIA 0x12
  OUTA 0xFF
  INA 0xFF              ; Class, which we do not need here.
  INA 0xFF              ; Flags: bit 0 says it brings memory.
  PSHA
  SETD.0 Flags
  CALL printString
  CALL blankSpace
  POPA
  CALL printByteHex
  CALL lineFeed

  ; Tell the device to fill its memory, the way a disk controller would be told to read.
  INIA 0x5A
  OUTA 0x12

  ; Give that memory bank number 5.
  INIA 0d5
  OUTA 0xE3             ; DestBank = 5, the number being handed out.
  INIA 0x12
  OUTA 0xE2             ; SourceLow = the port that owns it.
  INIA 0x03
  OUTA 0xE8             ; RegisterBank.

  ; Read bank 5's record out of the bank table. Eight bytes a bank, so bank 5 is at 40.
  INIA 0d2
  OUTA 0xE0
  RSTA
  OUTA 0xE1
  INIA 0d40
  OUTA 0xE2
  CALL readAndPrint     ; Flags: present.
  CALL readAndPrint     ; Owner: port 0x12.
  CALL readAndPrint     ; Capacity, high byte.
  CALL readAndPrint     ; Capacity, low byte.
  CALL lineFeed

  ; Now reach the device's memory the way any other bank is reached.
  INIA 0d5
  OUTA 0xE0
  RSTA
  OUTA 0xE1
  OUTA 0xE2
  CALL readAndPrint
  CALL readAndPrint
  CALL lineFeed

  ; Banks 0 to 2 are the machine's own and cannot be handed out.
  INIA 0d1
  OUTA 0xE3
  INIA 0x12
  OUTA 0xE2
  INIA 0x03
  OUTA 0xE8             ; Refused.

  ; Neither can memory from a port that brings none. Port 0x10 is the test device.
  INIA 0d6
  OUTA 0xE3
  INIA 0x10
  OUTA 0xE2
  INIA 0x03
  OUTA 0xE8             ; Refused.
  HALT

readAndPrint:
  INA 0xE9
  CALL printByteHex
  CALL blankSpace
  RET

; Both refusals arrive here, and they really are the same fault: a bank that cannot be
; registered, for two different reasons. Saying so twice is more honest than inventing a
; distinction the machine does not draw.
bankHandler:
  SETD.0 Refused
  CALL printString
  CALL lineFeed

  ; Step past the refused command write, which is an opcode and a port.
  MVSD.0
  DPUP.0 0d14
  LDA.0
  CCF
  INIB 0d2
  ADD
  MVQA
  STA.0
  BRC bankCarried
  RETI
bankCarried:
  DPDN.0 0d01
  LDA.0
  INCA
  STA.0
  RETI

#Data

Flags:
"flags"
Refused:
"refused"

#Vectors

  BankFault  bankHandler
