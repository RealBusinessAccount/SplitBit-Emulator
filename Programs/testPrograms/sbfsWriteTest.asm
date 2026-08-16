; Writing the SplitBit Filesystem.
;
; A file's size is settled when it is made, because nothing here can grow one afterwards:
; files are laid down contiguously, so the block after a file usually belongs to somebody
; else. That is the bargain the format makes, and it is why the size comes first.
;
; The disk already has a file on it, so the second one has to be put somewhere that does
; not tread on it. There is no allocation table to consult: with contiguous files the
; directory already says which blocks are spoken for, so finding room is a walk through
; the entries rather than a lookup.
;
; What is written is read straight back, through the same directory, so a file that went
; down in the wrong place would come back wrong rather than looking plausible.
;
; Correct output is:
;   here.txt 0002
;   first.txt 0003 written by SplitBit itself
;   second.txt 0004 and a second one after it

#Include print.asm
#Include sbfs.asm

#Program

start:
  CALL sbfsMount
  BNQ failed

  ; What was already there, and where.
  SETD.0 Existing
  CALL report
  BNQ failed

  SETD.0 FirstName
  SETD.1 FirstText
  INIA 0d26
  CALL makeAndWrite
  BNQ failed

  SETD.0 SecondName
  SETD.1 SecondText
  INIA 0d25
  CALL makeAndWrite
  BNQ failed

  ; And read both of them back off the disk.
  SETD.0 FirstName
  CALL report
  BNQ failed
  SETD.0 SecondName
  CALL report
  BNQ failed
  HALT

failed:
  SETD.0 Failed
  CALL printString
  CALL lineFeed
  HALT

; DP0 names the file, DP1 is its text, and A is how many bytes of it there are. Nothing
; here is longer than a block, so the whole size is the tail.
makeAndWrite:
  ; The text goes on the Stack, not into DP3. DP3 is the pointer a call does not put back,
  ; which cuts both ways: it is how a routine hands one out, and it is therefore not a
  ; safe place to leave anything across a call to a routine that might use it. sbfsCreate
  ; does use it.
  PSHD.1
  SETD.1 SbfsFileTail
  STA.1
  RSTA
  SETD.1 SbfsFileBlocks
  STA.1
  INCD.1
  STA.1

  CALL sbfsCreate
  POPD.1                ; Back off the Stack whether it worked or not.
  BNQ makeFailed
  CALL sbfsWriteFile
  RET

makeFailed:
  RET

; Prints a file's name, where it begins, and what is in it.
report:
  PSHD.0
  POPD.3
  CALL printString
  CALL blankSpace
  PSHD.3
  POPD.0
  CALL sbfsFind
  BNQ reportFailed

  SETD.0 SbfsFileStart
  LDA.0
  CALL printByteHex
  INCD.0
  LDA.0
  CALL printByteHex
  CALL blankSpace

  SETD.1 Landing
  CALL sbfsRead
  BNQ reportFailed

  ; Everything here fits in one block, so the tail is the whole length.
  SETD.0 Landing
  SETD.1 SbfsFileTail
  LDA.1
  SETD.1 LeftOver
  STA.1
  BRA reportEnd
reportLoop:
  LDA.0
  OUTA 0x00
  INCD.0
  SETD.1 LeftOver
  LDA.1
  DECA
  STA.1
  BNA reportLoop
reportEnd:
  CALL lineFeed
  RSTA
  RSTB
  CCF
  ADD
  RET

reportFailed:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

#Data

Existing:
"here.txt"
FirstName:
"first.txt"
SecondName:
"second.txt"
FirstText:
"written by SplitBit itself"
SecondText:
"and a second one after it"
Failed:
"failed"
LeftOver:
  0x00
Landing:
  #Reserve 0d512
