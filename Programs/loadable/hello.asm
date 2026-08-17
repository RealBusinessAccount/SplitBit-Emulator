; A program meant to be loaded off a disk rather than booted from.
;
; It is assembled for where it will live. Giving each segment a base says where it goes,
; so the labels inside are already right for the place the loader will put it, and the
; assembler writes it out as a loadable program rather than as a boot image. Nothing
; relocates anything: this works because the addresses here and the addresses in its
; header say the same thing.
;
; The loader keeps below both of these, which is the whole of the arrangement.

#Program

  #Base 0x2000          ; This program's code lives from 0x2000.

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

  #Base 0x1000          ; And its data from 0x1000.

HelloText:
"loaded off a disk, with a string and a loop of its own"
