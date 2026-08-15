; Tests a hardware interrupt delivered to a handler named in the Vector Segment.
;
; A device is named by the port it is plugged into, because that is what decides which
; vector it arrives through. The test device on port 0x10 puts its line up when anything
; is written to it.
;
; The device is asked for attention while the Interrupt Flag is down, so the line waits.
; SIF lets it through, and the handler runs before the next instruction does.
;
; Correct output is:
;   O         printed with the line up and the flag down
;   K         printed by the handler
;   !         printed after RETI came back

#Program

start:
  CIF               ; Hold devices off.
  INIA 0d1
  OUTA 0x10         ; The device asks. Its line goes up and stays up.

  INIA 0d79         ; 'O'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00

  SIF               ; Let it through. It is answered on the very next step.

  INIA 0d33         ; '!'. Reached only because RETI came back here.
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00
  HALT

deviceHandler:
  INIA 0d75         ; 'K'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00
  RETI

#Vectors

  Device 0x10  deviceHandler
