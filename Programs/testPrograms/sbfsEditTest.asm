; Deleting, renaming, and saving over something that is already there.
;
; Reading and writing were built first because a program had to be got onto a disk and off
; it again. What a document needs is different and it is all about the second time: a file
; that is written once is easy, and a file that is written again having grown is where this
; format's bargain shows. Files are contiguous and do not grow, so saving a longer version
; means putting it somewhere else and letting go of where it was.
;
; THE ORDER MATTERS AND THE OBVIOUS ONE IS WRONG. Delete the old, create the new, write it:
; that loses the lot when the create is refused for want of a run long enough, which is a
; thing that happens on a disk with plenty of free blocks once it is in pieces. sbfsSaveFile
; does it the other way round, and the rename at the end of that is why renaming exists.
;
; Correct output is:
;   here.txt   0002 already here
;   doc.txt    0003 first draft
;   doc.txt    0004 a second draft, which is longer than the first
;   notes.txt  0004 a second draft, which is longer than the first
;   doc.txt    gone
;   notes.txt  gone
;
; The start block moving from 0003 to 0004 is the file being put somewhere else, which is
; what saving a longer one has to do. The last two lines are a rename and a delete having
; actually happened rather than having been reported.

#Include print.asm
#Include sbfs.asm

#Program

start:
  CALL sbfsMount
  BNQ failed

  SETD.0 Existing
  CALL report
  BNQ failed

  ; Written once, the ordinary way.
  SETD.0 DocName
  SETD.1 ShortText
  INIA 0d11
  CALL makeAndWrite
  BNQ failed
  SETD.0 DocName
  CALL report
  BNQ failed

  ; And again, longer. Nothing here says where it goes; that is sbfsSaveFile's business.
  SETD.0 SbfsFileBlocks
  RSTA
  STA.0
  INCD.0
  STA.0
  SETD.0 SbfsFileTail
  INIA 0d46
  STA.0
  SETD.0 DocName
  SETD.1 LongText
  CALL sbfsSaveFile
  BNQ failed
  SETD.0 DocName
  CALL report
  BNQ failed

  ; Renaming moves nothing: the same blocks answer to a different name.
  SETD.0 DocName
  SETD.1 NewName
  CALL sbfsRename
  BNQ failed
  SETD.0 NewName
  CALL report
  BNQ failed

  ; And the old name is not there any more, which is the half of renaming that could have
  ; quietly not happened.
  SETD.0 DocName
  CALL expectGone

  SETD.0 NewName
  CALL sbfsDelete
  BNQ failed
  SETD.0 NewName
  CALL expectGone
  HALT

failed:
  SETD.0 Failed
  CALL printString
  CALL lineFeed
  HALT

; DP0 names the file, DP1 is its text, A is how long it is. Everything here fits in a
; block, so the whole length is the tail.
makeAndWrite:
  PSHD.1
  SETD.1 SbfsFileTail
  STA.1
  RSTA
  SETD.1 SbfsFileBlocks
  STA.1
  INCD.1
  STA.1
  CALL sbfsCreate
  POPD.1
  BNQ makeFailed
  CALL sbfsWriteFile
  RET
makeFailed:
  RET

; DP0 names a file that should not be there. Says so either way.
expectGone:
  PSHD.0
  POPD.3
  CALL printString
  CALL padName
  PSHD.3
  POPD.0
  CALL sbfsFind
  BRQ goneStillThere
  SETD.0 GoneText
  CALL printString
  CALL lineFeed
  RET
goneStillThere:
  SETD.0 StillText
  CALL printString
  CALL lineFeed
  RET

; Prints a file's name, where it begins, and what is in it.
report:
  PSHD.0
  POPD.3
  CALL printString
  CALL padName
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

; Names are different lengths and the columns should not be, so this pads out to eleven.
; DP3 holds the name, which is where the caller left it.
padName:
  PSHD.3
  POPD.0
  INIB 0d11
padCount:
  LDA.0
  BRA padOut
  INCD.0
  DECB
  BNB padCount
padOut:
  RSTA
padLoop:
  BRB padDone
  INIA 0x20
  OUTA 0x00
  DECB
  BRI padLoop
padDone:
  RET

#Data

Existing:
"here.txt"
DocName:
"doc.txt"
NewName:
"notes.txt"

ShortText:
"first draft"
LongText:
"a second draft, which is longer than the first"

GoneText:
"gone"
StillText:
"STILL THERE"
Failed:
"failed"

LeftOver:
  0x00

Landing:
  #Reserve 0d256
