; Walking the directory of a SplitBit filesystem.
;
; sbfsFind answers a question about one name. This is the other thing a directory is for:
; being listed. The disk was made by SplitDisk, so the order and contents here are what
; the other implementation of the format wrote, not what this one assumed.
;
; The cases that matter are all on this disk already. There are twelve files, which is
; more than the eight an entry block holds, so the walk has to cross from the first
; directory block into the second. aName22CharactersLong! fills the name field exactly and
; so has no zero byte to end it, which is what the twenty third byte of SbfsName is for.
; empty.txt has no blocks at all.
;
; The count at the end is the proof that the walk stopped where the directory did. A walk
; that stepped its pointer only when it took an entry would loop forever on a free one,
; and one that stepped only when it skipped would hand out every eighth file.
;
; Correct output is the twelve files with their sizes, then how many there were.

#Include console.asm
#Include sbfs.asm

#Program

start:
  CALL sbfsMount
  BRQ mounted
  SETD.0 NoMount
  CALL printString
  CALL newLine
  HALT

mounted:
  ; Nothing found yet.
  RSTA
  SETD.0 Seen
  STA.0

  CALL sbfsFirst
  BRI walkCheck

walkStep:
  CALL sbfsNext
walkCheck:
  BNQ walkDone

  SETD.0 Seen
  LDA.0
  INCA
  STA.0

  SETD.0 SbfsName
  CALL printString

  ; Line the sizes up, so a name that fills the field and a short one both read cleanly.
  SETD.0 SbfsName
  CALL nameWidth
  MVQA
  CALL printSpaces

  ; A file is its blocks times 256 plus its tail, which is the block count in the high
  ; byte and the tail in the low one. Nothing has to multiply anything.
  SETD.0 SbfsFileBlocks
  DPUP.0 0d01
  LDA.0
  SETD.1 Size
  STA.1
  SETD.0 SbfsFileTail
  LDA.0
  SETD.1 Size
  INCD.1
  STA.1

  SETD.0 Size
  CALL printWordDecimal
  CALL newLine
  BRI walkStep

walkDone:
  SETD.0 Total
  CALL printString
  SETD.0 Seen
  LDA.0
  CALL printByteDecimal
  CALL newLine
  HALT

; DP0 names a string. Q is how many spaces would pad it out to twenty four characters.
; A name that is already that long gets one space, because none at all would run the
; name into the number.
nameWidth:
  INIA 0d24
  SETD.1 Padding
  STA.1
widthLoop:
  LDA.0
  BRA widthDone
  SETD.1 Padding
  LDA.1
  DECA
  STA.1
  BRA widthFloor        ; It is already too long to pad.
  INCD.0
  BRI widthLoop
widthFloor:
  INIA 0d1
  SETD.1 Padding
  STA.1
widthDone:
  SETD.1 Padding
  LDA.1
  RSTB
  CCF
  ADD
  RET

#Data

NoMount:
"no filesystem on that disk"
Total:
"files: "

Seen:
  0x00
Padding:
  0x00
Size:
  0x00 0x00

#Vectors

  Boot  start
