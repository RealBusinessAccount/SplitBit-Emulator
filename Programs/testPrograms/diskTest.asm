; Storage.
;
; The disk is a block device and nothing more. It knows numbered blocks of 256 bytes and
; has never heard of a file, which is deliberate: a filesystem is software this machine
; will run rather than something the host does on its behalf. A disk that understood
; filenames would be the emulator doing the work while the machine pretended it had.
;
; Its buffer is one block, and like any memory a device brings, it is unreachable until
; it is registered as a bank and gone through with the controller.
;
; Between writing and reading the buffer is scrubbed, so a stale copy of the message
; sitting in it cannot make a broken read look like a working one.
;
; The image is made fresh for every run of the suite, so block 3 is zeroes before this
; program touches it.
;
; Correct output is:
;   00                the write worked
;   from the disk     block 3 came back
;   02                a block past the end of the image is an error, not a fault

#Include print.asm

#Program

start:
  ; The disk's buffer becomes bank 5.
  INIA 0d5
  OUTA 0xE3
  INIA 0x20
  OUTA 0xE2
  INIA 0x03
  OUTA 0xE8

  ; Put the message into the buffer and write it to block 3.
  SETD.0 Message
  CALL aimSourceData
  CALL aimDestBuffer
  INIA 0d16
  CALL setLength
  INIA 0x01
  OUTA 0xE8

  CALL selectBlockThree
  INIA 0x02
  OUTA 0x22             ; Write.
  INA 0x23
  CALL printByteHex
  CALL lineFeed

  ; Scrub the buffer, so what comes back has to have come off the disk.
  CALL aimDestBuffer
  INIA 0x2D             ; '-' as the fill byte.
  OUTA 0xE2
  INIA 0d16
  CALL setLength
  INIA 0x02
  OUTA 0xE8             ; Fill.

  CALL selectBlockThree
  INIA 0x01
  OUTA 0x22             ; Read.

  ; Bring the block into Data Memory and print it.
  INIA 0d5
  OUTA 0xE0
  RSTA
  OUTA 0xE1
  OUTA 0xE2
  SETD.0 Landing
  CALL aimDestData
  INIA 0d16
  CALL setLength
  INIA 0x01
  OUTA 0xE8

  SETD.0 Landing
  CALL printString
  CALL lineFeed

  ; A block past the end of the image says so in Status rather than stopping the machine.
  ; A disk that cannot read a block is an ordinary thing that happens to working programs.
  INIA 0xFF
  OUTA 0x20
  INIA 0xFF
  OUTA 0x21
  INIA 0x01
  OUTA 0x22
  INA 0x23
  CALL printByteHex
  CALL lineFeed
  HALT

selectBlockThree:
  RSTA
  OUTA 0x20
  INIA 0d3
  OUTA 0x21
  RET

aimSourceData:
  INIA 0d1
  OUTA 0xE0
  PSHD.0
  POPA
  POPB
  OUTB 0xE1
  OUTA 0xE2
  RET

aimDestData:
  INIA 0d1
  OUTA 0xE3
  PSHD.0
  POPA
  POPB
  OUTB 0xE4
  OUTA 0xE5
  RET

aimDestBuffer:
  INIA 0d5
  OUTA 0xE3
  RSTA
  OUTA 0xE4
  OUTA 0xE5
  RET

setLength:
  PSHA
  RSTA
  OUTA 0xE6
  POPA
  OUTA 0xE7
  RET

#Data

Message:
"from the disk"

Landing:
  #Reserve 0d20
