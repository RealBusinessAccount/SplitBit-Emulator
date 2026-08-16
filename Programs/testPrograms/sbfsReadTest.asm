; Reading the SplitBit Filesystem.
;
; The disk this reads was made by SplitDisk, which is the other implementation of the same
; format. That is what makes this worth running: the library is being checked against
; something written by different code working from the same written specification, rather
; than against itself. If the two ever drift, this is where it shows.
;
; The cases here are the ones most likely to be wrong. across.txt is longer than a block,
; so reading it has to carry on from one to the next. Its entry, and the two after it, are
; in the second directory block, so finding it has to walk past the end of the first.
; aName22CharactersLong! fills the name field exactly, so there is no zero on the end of
; it to stop a comparison. empty.txt has no blocks at all.
;
; Correct output is:
;   greeting.txt 0000 11 hello from a file
;   across.txt 0002 BC ABCDEFGH...
;   aName22CharactersLong! 0000 16 exactly twenty two!!!!
;   empty.txt 0000 00
;   absent.txt missing

#Include print.asm
#Include sbfs.asm

#Program

start:
  CALL sbfsMount
  BRQ mounted
  SETD.0 NoMount
  CALL printString
  CALL lineFeed
  HALT

mounted:
  SETD.0 WantGreeting
  CALL showFile
  SETD.0 WantAcross
  CALL showFile
  SETD.0 WantLongName
  CALL showFile
  SETD.0 WantEmpty
  CALL showFile
  SETD.0 WantAbsent
  CALL showFile
  HALT

; DP0 names a file. Prints its name, what the directory says about it, and then the file
; itself. DP3 keeps the name across the calls, because it is the pointer a CALL does not
; put back.
showFile:
  PSHD.0
  POPD.3
  CALL printString
  CALL blankSpace

  PSHD.3
  POPD.0
  CALL sbfsFind
  BRQ showFound
  SETD.0 Missing
  CALL printString
  CALL lineFeed
  RET

showFound:
  SETD.0 SbfsFileBlocks
  LDA.0
  CALL printByteHex
  INCD.0
  LDA.0
  CALL printByteHex
  CALL blankSpace
  SETD.0 SbfsFileTail
  LDA.0
  CALL printByteHex
  CALL blankSpace

  SETD.1 Landing
  CALL sbfsRead
  BRQ showContents
  SETD.0 Failed
  CALL printString
  CALL lineFeed
  RET

; Writes out exactly as many bytes as the file has, and no more. The length is the block
; count and the tail side by side: blocks times 256 plus the tail is the same as putting
; the count in the high byte and the tail in the low one.
showContents:
  SETD.0 Landing
  SETD.1 SbfsFileBlocks
  DPUP.1 0d01
  LDA.1
  SETD.1 LeftHigh
  STA.1
  SETD.1 SbfsFileTail
  LDA.1
  SETD.1 LeftLow
  STA.1

showLoop:
  SETD.1 LeftHigh
  LDA.1
  SETD.2 LeftLow
  LDB.2
  OR
  BRQ showEnd           ; Nothing left of it.

  LDA.0
  OUTA 0x00
  INCD.0

  SETD.1 LeftLow
  LDA.1
  DECA
  STA.1
  BRC showBorrow        ; It went under, so the high byte owes one.
  BRI showLoop
showBorrow:
  SETD.1 LeftHigh
  LDA.1
  DECA
  STA.1
  BRI showLoop

showEnd:
  CALL lineFeed
  RET

#Data

WantGreeting:
"greeting.txt"
WantAcross:
"across.txt"
WantLongName:
"aName22CharactersLong!"
WantEmpty:
"empty.txt"
WantAbsent:
"absent.txt"

NoMount:
"no mount"
Missing:
"missing"
Failed:
"failed"

LeftHigh:
  0x00
LeftLow:
  0x00

Landing:
  #Reserve 0d1024
