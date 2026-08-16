; Running off the end of a bank.
;
; Bank 2 is the bank table: 256 banks at eight bytes each, so 2048 bytes exactly. The
; last byte is at 0x07FF and there is nothing at 0x0800. A bank knowing how big it is
; means the difference shows up as a fault at the instruction that overran, instead of
; quietly reading whatever happened to be next in the emulator's memory.
;
; Nothing is installed for BankFault here, so the machine stops.
;
; Correct output is:
;   O                the last byte of the bank was read without complaint
;   a fault naming port 233, which is the controller's Data port, and a non zero exit.

#Program

start:
  INIA 0d2
  OUTA 0xE0         ; SourceBank = 2
  INIA 0x07
  OUTA 0xE1
  INIA 0xFF
  OUTA 0xE2         ; 0x07FF, the last byte there is

  INA 0xE9          ; Fine.
  INIA 0d79         ; 'O'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00

  INIA 0x08
  OUTA 0xE1
  RSTA
  OUTA 0xE2         ; 0x0800, one past the end

  INA 0xE9          ; Refused: BankFault.

  ; Never reached.
  INIA 0d88         ; 'X'
  OUTA 0x00
  HALT
