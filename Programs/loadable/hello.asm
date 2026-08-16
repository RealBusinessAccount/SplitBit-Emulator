; A program meant to be loaded off a disk rather than booted from.
;
; It is assembled for where it will live. Reserving the front of each segment puts the
; first thing in it at a known address, and everything after that follows, so the labels
; inside are already right for the place the loader will put it. Nothing relocates
; anything: this works because the addresses here and the addresses in its header say the
; same thing.
;
; The loader keeps below both of these, which is the whole of the arrangement.

#Program

  #Reserve 0x2000       ; This program's code lives from 0x2000.

hello:
  SETD.0 HelloText
helloLoop:
  LDA.0
  BRA helloDone
  OUTA 0x00
  INCD.0
  BRI helloLoop
helloDone:
  INIA 0x0A
  OUTA 0x00
  HALT

#Data

  #Reserve 0x1000       ; And its data from 0x1000.

HelloText:
"loaded off a disk, with a string and a loop of its own"
