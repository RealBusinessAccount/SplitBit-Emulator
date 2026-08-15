; Tests that the Interrupt Flag holds a device off, and that the device is still
; waiting once the flag goes back up.
;
; The test device on port 0x10 puts its own line up when anything is written to it. A
; device on port N interrupts on N, so this one arrives on hardware vector 16.
;
; Nothing is installed at that vector, so answering it is a fault. That is the point:
; the fault is proof the line was answered, and where it appears in the output is proof
; of when. The letters are printed to mark how far the program got.
;
; Correct output is:
;   M         the device has asked, and the flag is down, so nothing has happened
;   S         still nothing, several instructions later
;   then a fault naming hardware vector 16, raised after SIF and not before.

#Program

start:
  CIF               ; Hold devices off.
  INIA 0d1
  OUTA 0x10         ; The device asks for attention. Its line goes up and stays up.

  INIA 0d77         ; 'M', printed with the line still up and the flag still down.
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00

  NOP               ; Several instructions pass and the line is still not answered.
  NOP
  NOP

  INIA 0d83         ; 'S'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00

  SIF               ; Now let it through. The line is answered on the very next step.

  ; Never reached.
  INIA 0d88         ; 'X'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00
  HALT
