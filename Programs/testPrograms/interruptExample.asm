; The worked example from the SplitBit Assembler Manual, kept here so that the manual
; cannot quietly stop being true. If this test changes, the manual changes with it.
;
; Correct output is:
;   ready
;   trap
;   device

; Interrupt handling from all three directions.

#Program

start:
  CIF               ; Hold devices off while we set up.
  SETD.0 Greeting
  CALL printString

  SWI announce      ; A trap of our own, reached by name.

  INIA 0d1
  OUTA 0x10         ; Ask the test device for attention. Its line goes up.
  SIF               ; Let it through. It is answered before the next instruction.

  HALT

; A trap. It is entered with a full frame, so it may use any register it likes
; without agreeing anything with the code it interrupted.
announce:
  SETD.0 Trapped
  CALL printString
  RETI

; The device handler. Reached because the device sits on port 0x10.
deviceReady:
  SETD.0 Device
  CALL printString
  RETI

; The fault handler. It reports and stops, rather than trying to carry on.
reportFault:
  SETD.0 Broken
  CALL printString
  HALT

printString:        ; Expects DP0 to be set to the beginning of the string.
  LDA.0
  BRA printDone
  OUTA 0x00
  INCD.0
  BRI printString
 printDone:
  INIA 0x0A
  OUTA 0x00
  RET

#Data

Greeting:
"ready"
Trapped:
"trap"
Device:
"device"
Broken:
"bad opcode"

#Vectors

  Boot          start         ; Begin here rather than at the first byte.
  BadOpcode     reportFault
  announce      announce      ; A name of our own. The assembler numbers it.
  Device 0x10   deviceReady   ; Named by the port, because that is what decides it.
