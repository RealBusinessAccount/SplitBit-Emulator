; Loads a program off a disk and runs it.
;
; Everything this needs already existed: the filesystem reads the file, the controller
; writes Program Memory, and BRD jumps to an address worked out at run time. The only new
; part is the sixteen bytes on the front of a loadable program that say where it goes.
;
; Nothing relocates anything. The program is put exactly where its header asks, and that
; has to be where it was assembled for, or every branch inside it points somewhere wrong.
; This loader therefore keeps out of the way: its own code and data sit above the
; addresses the loaded program claims, which is an arrangement rather than a mechanism.
;
; Correct output is:
;   loader
;   loaded off a disk, with a string and a loop of its own

#Include print.asm
#Include sbfs.asm

#Program

; print.asm branches here at the top of the Program Segment, so this is where the machine
; arrives whether or not the Boot Vector is obeyed. Naming it in the Vector Segment as
; well says plainly where the program begins.
start:
  SETD.0 LoaderName
  CALL printString
  CALL lineFeed

  CALL sbfsMount
  BNQ loaderNoDisk

  SETD.0 ProgramName
  CALL sbfsFind
  BNQ loaderMissing

  SETD.1 Staging
  CALL sbfsRead
  BNQ loaderUnreadable

  ; "SBEX", or it is not a program at all. Loading a text file would otherwise put
  ; nonsense into Program Memory and jump into it.
  SETD.0 Staging
  SETD.2 ExecMagic
  INIA 0d4
  SETD.1 LoaderCount
  STA.1
loaderMagicLoop:
  LDA.0
  LDB.2
  XOR
  BNQ loaderNotProgram
  INCD.0
  INCD.2
  LDA.1
  DECA
  STA.1
  BNA loaderMagicLoop

  SETD.0 Staging
  DPUP.0 0d04
  LDA.0
  INIB 0d1
  XOR
  BNQ loaderWrongVersion

  ; The code first. Source is the bytes just past the header; destination is wherever the
  ; header says the code lives.
  INIA 0d1
  OUTA 0xE0             ; SourceBank: Data Memory, where the file was read to.
  SETD.0 Staging
  DPUP.0 0d16
  PSHD.0
  POPA
  POPB
  OUTB 0xE1
  OUTA 0xE2

  RSTA
  OUTA 0xE3             ; DestBank: Program Memory.
  ; Where the code goes. Read and written out a byte at a time rather than through a
  ; subroutine, because a subroutine could not hand the two bytes back: CALL preserves
  ; A and B along with the first three Data Pointers, so anything a routine puts in them
  ; is undone by its own return.
  SETD.0 Staging
  DPUP.0 0d06
  LDA.0
  OUTA 0xE4
  INCD.0
  LDA.0
  OUTA 0xE5

  ; How much of it there is.
  SETD.0 Staging
  DPUP.0 0d10
  LDA.0
  OUTA 0xE6
  INCD.0
  LDA.0
  OUTA 0xE7

  INIA 0x01
  OUTA 0xE8             ; Blit.

  ; Then the data. A blit leaves its addresses past whatever it touched, so the source is
  ; already sitting on the first byte of the data and only the destination changes.
  INIA 0d1
  OUTA 0xE3             ; DestBank: Data Memory.
  SETD.0 Staging
  DPUP.0 0d12
  LDA.0
  OUTA 0xE4
  INCD.0
  LDA.0
  OUTA 0xE5

  SETD.0 Staging
  DPUP.0 0d14
  LDA.0
  OUTA 0xE6
  INCD.0
  LDA.0
  OUTA 0xE7

  INIA 0x01
  OUTA 0xE8             ; Blit.

  ; And go. The entry address is a number until BRD makes it a place. DP3 is built from
  ; the two bytes by hand, since it is the pointer nothing puts back.
  SETD.0 Staging
  DPUP.0 0d08
  LDA.0
  INCD.0
  LDB.0
  PSHA
  PSHB
  POPD.3
  BRD.3

loaderNoDisk:
  SETD.0 NoDisk
  BRI loaderComplain
loaderMissing:
  SETD.0 NotThere
  BRI loaderComplain
loaderUnreadable:
  SETD.0 Unreadable
  BRI loaderComplain
loaderNotProgram:
  SETD.0 NotProgram
  BRI loaderComplain
loaderWrongVersion:
  SETD.0 WrongVersion
loaderComplain:
  CALL printString
  CALL lineFeed
  HALT

#Data

ExecMagic:
"SBEX"
LoaderName:
"loader"
ProgramName:
"hello.sbx"
NoDisk:
"no disk"
NotThere:
"no such program"
Unreadable:
"could not read it"
NotProgram:
"not a program"
WrongVersion:
"a version I do not know"
LoaderCount:
  0x00

Staging:
  #Reserve 0d512

#Vectors

  Boot  start
