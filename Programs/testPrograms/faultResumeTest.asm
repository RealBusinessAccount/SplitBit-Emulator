; Tests a fault handler that steps over the byte it could not decode and carries on.
;
; The frame holds the address of the offending byte rather than the one after it, so a
; handler can see exactly what failed. The cost is that returning with a bare RETI meets
; the same byte again, which is why this handler moves the saved address on by one
; first. MVSD is what lets it reach the frame at all.
;
; 0xFE is not an instruction. Writing it as a literal is the only way past the
; assembler, which is what makes a program containing one buildable.
;
; Correct output is:
;   O         printed before the byte that fails
;   K         printed after the handler stepped over it

#Program

start:
  INIA 0d79         ; 'O'
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00

  0xFE              ; Not an instruction. The handler steps over this.

  INIA 0d75         ; 'K'. Reached only because the handler moved the address on.
  OUTA 0x00
  INIA 0x0A
  OUTA 0x00
  HALT

faultHandler:
  ; The frame sits above the Stack Pointer, which points at the next free slot. The
  ; address to resume at went on first, so it is furthest up: high byte 13 above the
  ; Stack Pointer, low byte 14 above.
  MVSD.0
  DPUP.0 0d14
  LDA.0
  INCA              ; Step past the one byte that failed.
  STA.0
  BRC carried       ; The low byte wrapped, so the high byte needs the carry.
  RETI

carried:
  DPDN.0 0d01
  LDA.0
  INCA
  STA.0
  RETI

#Vectors

  BadOpcode  faultHandler
