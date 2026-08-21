; The source reader: characters out of a file of any size.
;
; Everything else in the assembler sits on this, so it is the first thing built and the
; thing most worth getting right. It hands out one character at a time and keeps a line
; number, which is what lets an error say where it happened rather than only what it was.
;
; A FILE IS NEVER HELD WHOLE. It arrives a block at a time through osFileBlock, into one
; buffer of 256 bytes, and is fetched again when the buffer runs out. That is why the
; assembler can read a source file bigger than the memory it runs in - which cosmos.asm,
; at 56,047 bytes, already is.
;
; The file is read TWICE, once per pass, and srcRewind is how the second pass starts over.
; Nothing is kept between the passes but the label table.
;
; Written by Anachronaut

#Program

; Opens the file DP0 names. Q is zero if it is there.
;
; The name is copied rather than pointed at, because the caller's copy is in the caller's
; memory and every later block read has to name the file again - there being no such thing
; as an open file to hold on to.
srcOpen:
  SETD.1 SrcName
  CALL srcKeepName
  CALL srcRewind
  RET

; Back to the first character, for the second pass.
srcRewind:
  SETD.0 SrcIndex
  CALL numZero
  SETD.0 SrcAt
  CALL numZero
  SETD.0 SrcCount
  CALL numZero
  RSTA
  SETD.0 SrcEnded
  STA.0

  ; The line number counts from one, the way an editor does.
  SETD.0 SrcLine
  CALL numZero
  SETD.0 SrcLine
  CALL numStep

  ; Ask how big it is, which is both the answer to "is it there" and the thing that says
  ; when to stop asking for blocks.
  SETD.0 SrcName
  SWI osFileInfo
  BNQ srcRewindNo
  PSHD.3
  POPB
  POPA
  SETD.0 SrcBlocks
  STA.0
  INCD.0
  STB.0
  RSTA
  RSTB
  CCF
  ADD                       ; Q is zero: it is there.
  RET

srcRewindNo:
  INIA 0d1
  SETD.0 SrcEnded
  STA.0
  RSTA
  INIB 0d1
  CCF
  ADD                       ; Q is not zero: it is not.
  RET

; The next character of the file, into SrcChar. Q is zero if there was one, and something
; else at the end of the file.
srcNext:
  SETD.0 SrcEnded
  LDA.0
  BNA srcAtEnd

  ; Is the buffer used up? SrcAt counts how far into it we have read and SrcCount how many
  ; of its bytes are the file's, which is 256 for every block but a short last one.
  SETD.0 SrcAt
  SETD.2 SrcCount
  CALL numCompare
  BNQ srcHaveByte
  CALL srcLoad
  BNQ srcAtEnd

srcHaveByte:
  SETD.1 SrcPointer
  LDD.0.1
  LDA.0
  INCD.0
  STD.0.1
  SETD.0 SrcChar
  STA.0
  SETD.0 SrcAt
  CALL numStep

  ; A newline is what makes the next character part of the next line. Counting it here,
  ; as it is handed out, means the line number always describes the character just given.
  SETD.0 SrcChar
  LDA.0
  INIB 0x0A
  XOR
  BNQ srcNextDone
  SETD.0 SrcLine
  CALL numStep

srcNextDone:
  RSTA
  RSTB
  CCF
  ADD                       ; Q is zero: there was a character.
  RET

srcAtEnd:
  INIA 0d1
  SETD.0 SrcEnded
  STA.0
  RSTA
  INIB 0d1
  CCF
  ADD                       ; Q is not zero: the file is finished.
  RET

; Fetches the block SrcIndex names, and steps SrcIndex past it. Q is zero if there was one.
;
; Running off the end is not a failure here: osFileBlock answers three for a block past the
; end of the file, which is how a reader finds out it has finished. Any other refusal is a
; real one, and both come back the same way because there is nothing useful to do about
; either except stop.
srcLoad:
  SETD.0 SrcName
  SETD.1 SrcBuffer
  SETD.2 SrcIndex
  LDA.2
  INCD.2
  LDB.2
  SWI osFileBlock
  BNQ srcLoadNo

  ; DP3 says how many of the block's bytes belong to the file: a whole 256 except in a
  ; short last one, which is why it comes back in a pointer and not a register.
  PSHD.3
  POPB
  POPA
  SETD.0 SrcCount
  STA.0
  INCD.0
  STB.0

  SETD.0 SrcAt
  CALL numZero
  SETD.0 SrcIndex
  CALL numStep

  ; The walking pointer starts at the front of the buffer again.
  SETD.0 SrcBuffer
  SETD.1 SrcPointer
  STD.0.1

  RSTA
  RSTB
  CCF
  ADD
  RET

srcLoadNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Copies the name at DP0 into DP1, up to 22 characters of it and the zero after them,
; which is as long as a name on this filesystem may be.
srcKeepName:
  INIA 0d22
  SETD.2 SrcLeft
  STA.2
srcKeepLoop:
  LDA.0
  BRA srcKeepEnd
  STA.1
  INCD.0
  INCD.1
  LDA.2
  DECA
  STA.2
  BNA srcKeepLoop
srcKeepEnd:
  RSTA
  STA.1                     ; The zero that makes it a string.
  RET

#Data

SrcName:
  #Reserve 0d23
SrcBlocks:
  0x00 0x00
SrcIndex:
  0x00 0x00
SrcCount:
  0x00 0x00
SrcAt:
  0x00 0x00
SrcLine:
  0x00 0x00
SrcPointer:
  0x00 0x00
SrcEnded:
  0x00
SrcChar:
  0x00
SrcLeft:
  0x00

; One block, which is the whole of what a source file costs in memory however big it is.
SrcBuffer:
  #Reserve 0d256
