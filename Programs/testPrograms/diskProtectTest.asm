; A write protected disk.
;
; The bar is in the device, not in the filesystem. A flag in a superblock can be got
; around by writing blocks directly; this cannot be got around at all. It is the tab on
; the side of a floppy rather than a note asking politely.
;
; A disk is read only if it was attached that way, or if the host will not let its image
; be written. The machine cannot tell the two apart and does not need to.
;
; Status bit 2 says the disk is protected. Unlike the busy and error bits it describes the
; medium rather than the last operation, so it reads true before anything has been asked
; of the disk at all.
;
; Correct output is:
;   04                protected, before anything has been attempted
;   04                a read is allowed and does not disturb the bit
;   06                a write is barred: protected, and the operation failed

#Include print.asm

#Program

start:
  INA 0x23
  CALL printByteHex
  CALL lineFeed

  RSTA
  OUTA 0x20
  OUTA 0x21             ; Block 0.
  INIA 0x01
  OUTA 0x22             ; Read. Reading a protected disk is ordinary.
  INA 0x23
  CALL printByteHex
  CALL lineFeed

  INIA 0x02
  OUTA 0x22             ; Write. Barred by the device.
  INA 0x23
  CALL printByteHex
  CALL lineFeed
  HALT
