; Asks the bus registry what this machine is made of.
;
; Writing a port number to the registry selects the port being asked about. Reading
; gives that port's record a byte at a time: its device class, then its flags, then
; zeroes once the record has run out. Nothing here touches the device being asked
; about, which is the whole point: reading port 0x00 to find out what it is would take
; a character off standard input and wait for one that never comes.
;
; Port 0x05 has nothing on it, and reads as class 0. That is the same answer a machine
; with no registry at all would give, so software finds out whether it can enumerate by
; enumerating.
;
; Correct output is:
;   00 02 00      the console, class 2, no flags
;   10 10 00      the test device, class 0x10, no flags
;   FF 01 00      the registry itself, class 1, no flags
;   05 00 00      nothing there

#Include print.asm

#Program

start:
  INIA 0x00
  CALL reportPort
  INIA 0x10
  CALL reportPort
  INIA 0xFF
  CALL reportPort
  INIA 0x05
  CALL reportPort
  HALT

; Prints the port number, then the two bytes of its record. A is the port to ask about.
reportPort:
  PSHA
  CALL printByteHex       ; The port we are asking about.
  CALL blankSpace

  POPA
  OUTA 0xFF               ; Select it. This is the only write the registry accepts.

  INA 0xFF                ; The device class.
  CALL printByteHex
  CALL blankSpace

  INA 0xFF                ; The flags.
  CALL printByteHex
  CALL lineFeed
  RET
