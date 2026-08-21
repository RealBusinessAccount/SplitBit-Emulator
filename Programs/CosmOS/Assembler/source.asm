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
; ---- A stack of readers ----
;
; #Include splices another file in where it stands, so the reader is a stack: srcInclude
; puts the current file's whole state aside, opens the new one, and the end of that file
; pops the old one back and carries on where it left off. Everything above works on "the
; current file" and does not know the stack is there.
;
; THE WHOLE STATE GOES ASIDE, buffer and all, 293 bytes of it. Keeping only the position
; and re-reading the block on the way back would be cheaper in memory and would cost a disk
; read per pop; at six levels of nesting the copy costs less than the arithmetic to avoid it.
; The buffer pointer survives the trip because it points into the buffer, which is always at
; the same address - the state is saved from and restored to the same variables.
;
; A FILE IS INCLUDED ONCE. Including it twice is not an error, it just does nothing, which
; is what lets two libraries depend on a third. The names are remembered for the length of
; one pass and forgotten between them, because the second pass has to walk exactly the same
; tree the first one did.
;
; Written by Anachronaut

#Program

; Opens the file DP0 names. Q is zero if it is there.
;
; The name is copied rather than pointed at, because the caller's copy is in the caller's
; memory and every later block read has to name the file again - there being no such thing
; as an open file to hold on to.
srcOpen:
  SETD.1 SrcTopName
  CALL srcKeepName          ; Kept apart, so that each pass can open it again.
  CALL srcRestart
  RET

; Back to the top of the tree: the first file, no includes taken yet, nothing on the stack.
; This is what starts each pass.
srcRestart:
  RSTA
  SETD.0 SrcDepth
  STA.0
  SETD.0 IncCount
  STA.0
  SETD.0 SrcTopName
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
  ; This file is finished. If it was included by another, that one is not: it goes back on
  ; and the next character comes from where it left off, which is what makes an include
  ; read as though the text had been written there.
  INIA 0d1
  SETD.0 SrcEnded
  STA.0
  SETD.0 SrcDepth
  LDA.0
  BRA srcNothingLeft
  CALL srcPop
  BRI srcNext

srcNothingLeft:
  RSTA
  INIB 0d1
  CCF
  ADD                       ; Q is not zero: there is no more source anywhere.
  RET

; ---- The stack ----

; Opens the file named at DP0 as though its text were written here. Q is zero if the
; reader is now inside it, or if it had already been included and there is nothing to do.
srcInclude:
  SETD.1 IncWanted
  CALL srcKeepName
  CALL srcSeenAlready
  BRQ srcIncludeSkip

  SETD.0 SrcDepth
  LDA.0
  SETD.2 SrcDepthLimit
  LDB.2
  CCF
  SUB
  BNC srcTooDeep

  CALL srcRemember
  CALL srcPush
  SETD.0 IncWanted
  SETD.1 SrcName
  CALL srcKeepName
  CALL srcRewind
  BNQ srcIncludeGone
  RET                       ; Q is zero, out of srcRewind.

srcIncludeSkip:
  RSTA
  RSTB
  CCF
  ADD                       ; Already in, so this line does nothing at all.
  RET

srcIncludeGone:
  ; The file is not there. The stack is left as it is: the caller stops the assembly, and
  ; unwinding for the sake of tidiness would only hide where it happened.
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

srcTooDeep:
  SETD.0 TooDeepText
  SWI osPrintString
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Puts the current file aside and makes room for another.
srcPush:
  CALL srcSlot
  SETD.0 SrcState
  SETD.1 SrcSlot
  LDD.1.1
  CALL srcCopyState
  SETD.0 SrcDepth
  LDA.0
  INCA
  STA.0
  RET

; And takes it back.
srcPop:
  SETD.0 SrcDepth
  LDA.0
  DECA
  STA.0
  CALL srcSlot
  SETD.1 SrcSlot
  LDD.0.1
  SETD.1 SrcState
  CALL srcCopyState
  RET

; Puts one character back, so that the next read produces it again. The character itself
; is in A, because whether it was a newline decides whether a line goes back too.
;
; The tokenizer holds one character of lookahead, and at an #Include that character belongs
; to the file about to be put aside. Undoing the read is how it stays with that file: when
; the file is opened again the character is simply still there, and nothing has to be
; carried across the include or handed back at some moment chosen by the reader.
;
; CARRYING IT ACROSS WAS THE OBVIOUS THING AND IT WAS WRONG. A file runs out in the middle
; of whatever the tokenizer happens to be doing, so handing the character back then injects
; it into the middle of a word: `start:` came back as `s` and then `tart:`, which assembles
; into a file that looks entirely reasonable.
srcStepBack:
  INIB 0x0A
  XOR
  BNQ srcStepBackAt
  SETD.0 SrcLine
  SETD.2 SrcOne
  CALL numTake              ; A newline not yet read has not started a line either.

srcStepBackAt:
  SETD.0 SrcAt
  SETD.2 SrcOne
  CALL numTake
  SETD.0 SrcPointer
  SETD.2 SrcOne
  CALL numTake
  RET

; Where the slot for the current depth is, into SrcSlot.
srcSlot:
  SETD.0 SrcSlot
  SETD.2 ScratchSrcStack
  CALL numSet               ; WHERE the stack is, not what is in it.
  SETD.0 SrcSlotLeft
  SETD.2 SrcDepth
  LDA.2
  STA.0
srcSlotLoop:
  SETD.0 SrcSlotLeft
  LDA.0
  BRA srcSlotDone
  DECA
  STA.0
  SETD.0 SrcSlot
  SETD.2 SrcStateBytes
  CALL numAdd
  BRI srcSlotLoop
srcSlotDone:
  RET

; The whole reader state, from DP0 to DP1.
srcCopyState:
  SETD.2 SrcCopyFrom
  STD.0.2
  SETD.2 SrcCopyTo
  STD.1.2
  SETD.0 SrcCopyLeft
  SETD.2 SrcStateBytes
  CALL numSet
srcCopyLoop:
  SETD.1 SrcCopyFrom
  LDD.0.1
  LDA.0
  SETD.1 SrcCopyTo
  LDD.0.1
  STA.0
  SETD.0 SrcCopyFrom
  CALL numStep
  SETD.0 SrcCopyTo
  CALL numStep
  SETD.0 SrcCopyLeft
  SETD.2 SrcOne
  CALL numTake
  SETD.0 SrcCopyLeft
  LDA.0
  INCD.0
  LDB.0
  OR
  BNQ srcCopyLoop
  RET

; ---- Which files have been in ----

; Q is zero if IncWanted has already been included in this pass.
srcSeenAlready:
  RSTA
  SETD.0 IncLeft
  STA.0
srcSeenLoop:
  SETD.0 IncLeft
  LDA.0
  SETD.2 IncCount
  LDB.2
  CCF
  SUB
  BRQ srcSeenNo
  CALL srcSeenSlot
  SETD.1 IncSlot
  LDD.0.1
  SETD.1 IncWanted
  CALL sameText
  BRQ srcSeenYes
  SETD.0 IncLeft
  LDA.0
  INCA
  STA.0
  BRI srcSeenLoop
srcSeenYes:
  RSTA
  RSTB
  CCF
  ADD
  RET
srcSeenNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Writes IncWanted down as having been included.
srcRemember:
  SETD.0 IncLeft
  SETD.2 IncCount
  LDA.2
  STA.0
  CALL srcSeenSlot
  SETD.0 IncWanted
  SETD.1 IncSlot
  LDD.1.1
  CALL srcKeepName
  SETD.0 IncCount
  LDA.0
  INCA
  STA.0
  RET

; Where name number IncLeft sits, into IncSlot. Fixed fields of 23 bytes: there are few of
; these and they are short, so an arena would cost more code than it saved.
srcSeenSlot:
  SETD.0 IncSlot
  SETD.2 ScratchIncNames
  CALL numSet
  SETD.0 IncSlotLeft
  SETD.2 IncLeft
  LDA.2
  STA.0
srcSeenSlotLoop:
  SETD.0 IncSlotLeft
  LDA.0
  BRA srcSeenSlotDone
  DECA
  STA.0
  INIA 0d23
  SETD.0 IncSlot
  CALL numAddByte
  BRI srcSeenSlotLoop
srcSeenSlotDone:
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

; ---- The current file, as one block so that it can be put aside in one piece ----
;
SrcState:
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

; One block, which is the whole of what a source file costs in memory however big it is.
SrcBuffer:
  #Reserve 0d256

; 292 bytes: a name of 23, six numbers of two, one single byte, and the buffer. NOTHING MAY
; BE ADDED IN THE MIDDLE OF THE BLOCK ABOVE without changing this to match.
SrcStateBytes:
  0x01 0x24
SrcDepthLimit:
  0d6
SrcOne:
  0x00 0x01

SrcChar:
  0x00
SrcLeft:
  0x00
SrcDepth:
  0x00
SrcSlot:
  0x00 0x00
SrcSlotLeft:
  0x00
SrcCopyFrom:
  0x00 0x00
SrcCopyTo:
  0x00 0x00
SrcCopyLeft:
  0x00 0x00

; The file the assembly started from, so that each pass can open it again.
SrcTopName:
  #Reserve 0d23

IncWanted:
  #Reserve 0d23
IncCount:
  0x00
IncLeft:
  0x00
IncSlot:
  0x00 0x00
IncSlotLeft:
  0x00

TooDeepText:
"included files are nested deeper than this assembler will follow
"


