; A device refuses, and nothing is installed to deal with it.
;
; The machine has to stop where it stands and say which port refused and where. Letting
; execution carry on would mean the program continues as though the access had worked,
; which is the failure the fault trap exists to prevent.
;
; Correct output is:
;   O
;   a fault naming port 17, and a non zero exit.

#Program

start:
  INIA 0d79         ; 'O', so it is clear how far it got.
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00

  INIA 0d1
  OUTA 0x11         ; The device refuses, and no handler is installed.

  ; Never reached.
  INIA 0d88         ; 'X'
  OUTA 0x00
  HALT
