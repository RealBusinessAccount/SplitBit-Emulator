; Reading a file the machine cannot hold.
;
; Every other program here asks for a file and is handed the whole of it, which settles the
; question for anything under 64K and settles nothing above. CosmOS's own source is above:
; the sources together are a hundred kilobytes, and Data Memory is sixty four. A machine
; that is one day going to assemble itself has to be able to read a file bigger than its
; memory, and this is the program that proves it can.
;
; It uses osFileInfo and osFileBlock, and nothing else knows how a filesystem works. There
; is no open and no close - every call names the file and says which block it wants, so a
; program that stops halfway leaves nothing behind for anybody to clean up.
;
; ---- What it checks, and why each one is here ----
;
;   1. A file of four hundred odd blocks is read from end to end, a block at a time, into a
;      buffer of one block. That is the feature.
;   2. A small file is read BOTH WAYS - whole with osFileRead, and streamed - and the two
;      have to agree. This is the real proof: it compares streaming against the path that
;      was already known to work, so a fault in the block count or the order of the blocks
;      shows up as a difference rather than as a plausible wrong answer.
;   3. Two files are read alternately. The system remembers where the last file it was
;      asked about lives, and this is the case that catches a memory that does not notice
;      the name has changed.
;   4. A rename in the middle. Same reason, from the other side: the file the system
;      remembers has moved out from under the name it remembered it by.
;   5. The three ways of being told no, each with its own number.
;
; THE CHECKSUM IS FLETCHER'S, not a sum. A plain total is the same whatever order the bytes
; arrived in, and the order is exactly what streaming has to get right; carrying a second
; accumulator that adds the first one in each time makes a block delivered out of turn
; change the answer.
;
; Written by Anachronaut

#Include services.asm

#Program

  #Base 0x2000

start:
  ; ---- 1. How big is something that will not fit ----
  ;
  ; In blocks, not bytes, and that is forced rather than chosen: a file on a sixteen
  ; megabyte disk can be twenty four bits long and a pointer holds sixteen.
  SETD.0 BigName
  SWI osFileInfo
  BNQ noBig
  SETD.0 BigIs
  SWI osPrintString
  PSHD.3
  POPB
  POPA
  SWI osPrintNumber
  SETD.0 BlocksText
  SWI osPrintString

  ; ---- 2. Read the whole of it through a hole one block wide ----
  CALL clearChecksum
  CALL clearIndex

bigLoop:
  SETD.0 BigName
  SETD.1 Block
  SETD.2 Index
  LDA.2
  INCD.2
  LDB.2                     ; Which block, most significant first.
  SWI osFileBlock
  BNQ bigDone

  CALL takeCount
  SETD.1 Block
  CALL checksum
  CALL stepIndex
  BRI bigLoop

bigDone:
  ; The loop ends because a block past the end was asked for, which is answer three. Any
  ; other answer stopped it early and would otherwise look exactly like success, so what
  ; ended it is printed rather than assumed.
  CALL keepWhy
  SETD.0 ReadText
  SWI osPrintString
  SETD.2 Index
  LDA.2
  INCD.2
  LDB.2
  SWI osPrintNumber
  SETD.0 BlocksSumText
  SWI osPrintString
  CALL printChecksum
  SETD.0 StoppedText
  SWI osPrintString
  CALL printWhy

  ; ---- 3. The same file both ways ----
  ;
  ; osFileRead is the path that already worked, so it is what streaming is measured
  ; against. If the two checksums agree, every byte arrived and they arrived in order.
  SETD.0 SmallName
  SETD.1 Whole
  SWI osFileRead
  BNQ noSmall
  CALL takeCount
  CALL clearChecksum
  SETD.1 Whole
  CALL checksum
  CALL keepChecksum

  CALL clearChecksum
  CALL clearIndex
smallLoop:
  SETD.0 SmallName
  SETD.1 Block
  SETD.2 Index
  LDA.2
  INCD.2
  LDB.2
  SWI osFileBlock
  BNQ smallDone
  CALL takeCount
  SETD.1 Block
  CALL checksum
  CALL stepIndex
  BRI smallLoop

smallDone:
  SETD.0 BothText
  SWI osPrintString
  CALL printChecksum
  SETD.0 AgainstText
  SWI osPrintString
  CALL printKept
  SETD.0 NewLine
  SWI osPrintString
  CALL sameAsKept
  BNQ differ
  SETD.0 SameText
  SWI osPrintString
  BRI interleave
differ:
  SETD.0 DifferText
  SWI osPrintString

  ; ---- 4. Two files, alternately ----
  ;
  ; Block zero of the big file, then a block of the small one, then block zero of the big
  ; file again. The two readings of the same block have to match. A system that remembered
  ; the first file and did not notice the name had changed would hand back a block of the
  ; wrong file in the middle, and then the right one again, so only the middle call would
  ; be wrong - which is why this asks for the same block twice rather than once.
interleave:
  CALL clearChecksum
  CALL readFirstBig
  CALL keepChecksum

  SETD.0 SmallName
  SETD.1 Block
  RSTA
  RSTB
  SWI osFileBlock

  CALL clearChecksum
  CALL readFirstBig
  CALL sameAsKept
  BNQ mixedUp
  SETD.0 InterleaveOk
  SWI osPrintString
  BRI moved
mixedUp:
  SETD.0 InterleaveBad
  SWI osPrintString

  ; ---- 5. A file that moves out from under the name ----
  ;
  ; The system has just been asked about the small file, so it is the one being remembered.
  ; Renaming it has to throw that away: the blocks are still there and still hold the same
  ; bytes, so a stale answer would work perfectly and be wrong.
moved:
  SETD.0 SmallName
  SETD.1 OtherName
  SWI osFileRename
  BNQ noRename
  SETD.0 MovedText
  SWI osPrintString
  SETD.0 SmallName
  SWI osFileInfo
  CALL keepWhy
  SETD.0 OldNameText
  SWI osPrintString
  CALL printWhy
  SETD.0 NewNameText
  SWI osPrintString
  SETD.0 OtherName
  SWI osFileInfo
  CALL keepWhy
  CALL printWhy

  ; ---- 6. The three ways of being told no ----
missing:
  SETD.0 MissingName
  SWI osFileInfo
  CALL keepWhy
  SETD.0 MissingText
  SWI osPrintString
  CALL printWhy

  SETD.0 OtherName
  SETD.1 Block
  INIA 0xFF
  INIB 0xFF
  SWI osFileBlock
  CALL keepWhy
  SETD.0 PastText
  SWI osPrintString
  CALL printWhy

  SWI osExit

noBig:
  CALL keepWhy
  SETD.0 NoBigText
  SWI osPrintString
  CALL printWhy
  SWI osExit
noSmall:
  SETD.0 NoSmallText
  SWI osPrintString
  SWI osExit
noRename:
  SETD.0 NoRenameText
  SWI osPrintString
  SWI osExit

; ---- Routines ----

; Block zero of the big file, into the running checksum.
readFirstBig:
  SETD.0 BigName
  SETD.1 Block
  RSTA
  RSTB
  SWI osFileBlock
  BNQ readFirstDone
  CALL takeCount
  SETD.1 Block
  CALL checksum
readFirstDone:
  RET

; What the service just answered in DP3 becomes Left, which is what the checksum counts
; down. Kept in memory rather than in a pointer because a CALL does not preserve one.
takeCount:
  PSHD.3
  POPB
  POPA
  SETD.2 Left
  STA.2
  INCD.2
  STB.2
  RET

; Adds the bytes at DP1 into the running checksum, as many of them as Left says.
;
; Two accumulators, each a byte wide, each throwing away what carries off the top. The
; first is the sum of the bytes and the second is the sum of the first, so a byte that
; arrives late counts for less than one that arrived early - which is what makes this
; notice a block delivered out of turn.
checksum:
checksumLoop:
  LDA.1
  SETD.2 Fletch1
  LDB.2
  CCF
  ADD
  MVQA
  STA.2
  SETD.2 Fletch2
  LDB.2
  CCF
  ADD
  MVQA
  STA.2
  INCD.1

  ; Left goes down by one, sixteen bits of it: a whole block is 256 bytes and a whole file
  ; is more than one block, so a byte counter would not reach.
  SETD.2 Left
  INCD.2
  LDA.2
  BNA checksumLow
  DPDN.2 0d01
  LDA.2
  DECA
  STA.2                     ; Borrow out of the high byte.
  DPUP.2 0d01
  INIA 0xFF
  STA.2
  BRI checksumTest
checksumLow:
  DECA
  STA.2
checksumTest:
  SETD.2 Left
  LDA.2
  INCD.2
  LDB.2
  OR                        ; Zero only when both halves are.
  BNQ checksumLoop
  RET

clearChecksum:
  RSTA
  SETD.2 Fletch1
  STA.2
  SETD.2 Fletch2
  STA.2
  RET

clearIndex:
  RSTA
  SETD.2 Index
  STA.2
  INCD.2
  STA.2
  RET

stepIndex:
  SETD.2 Index
  INCD.2
  LDA.2
  INCA
  STA.2
  BNC stepIndexDone
  DPDN.2 0d01
  LDA.2
  INCA
  STA.2
stepIndexDone:
  RET

; Puts the checksum aside so that a second one can be compared with it.
keepChecksum:
  SETD.2 Fletch1
  LDA.2
  SETD.2 Kept1
  STA.2
  SETD.2 Fletch2
  LDA.2
  SETD.2 Kept2
  STA.2
  RET

; Q is zero if the running checksum is the one that was put aside.
sameAsKept:
  SETD.2 Fletch1
  LDA.2
  SETD.2 Kept1
  LDB.2
  XOR
  BNQ sameAsKeptDone
  SETD.2 Fletch2
  LDA.2
  SETD.2 Kept2
  LDB.2
  XOR
sameAsKeptDone:
  RET

printChecksum:
  SETD.2 Fletch1
  LDA.2
  SETD.2 Fletch2
  LDB.2
  SWI osPrintNumber
  RET

printKept:
  SETD.2 Kept1
  LDA.2
  SETD.2 Kept2
  LDB.2
  SWI osPrintNumber
  RET

; Why the last service said no. Q survives a CALL, which is the only reason this can be a
; routine at all, but it does not survive the next SWI - so it is written down here and
; printed later, with whatever has to happen in between happening in between.
keepWhy:
  MVQA
  SETD.2 Why
  STA.2
  RET

printWhy:
  RSTA
  SETD.2 Why
  LDB.2
  SWI osPrintNumber
  SETD.0 NewLine
  SWI osPrintString
  RET

#Data

  #Base 0x1000

BigName:
"big.txt"
SmallName:
"small.txt"
OtherName:
"moved.txt"
MissingName:
"nothing.txt"

BigIs:
"big.txt is "
BlocksText:
" blocks
"
ReadText:
"read "
BlocksSumText:
" blocks, checksum "
StoppedText:
", stopped with "
BothText:
"small.txt streamed is "
AgainstText:
", read whole is "
SameText:
"the same
"
DifferText:
"DIFFERENT
"
InterleaveOk:
"the same block twice with another file between: the same
"
InterleaveBad:
"the same block twice with another file between: DIFFERENT
"
MovedText:
"renamed small.txt
"
OldNameText:
"the old name now answers "
NewNameText:
"the new name answers "
MissingText:
"a name that was never there answers "
PastText:
"a block past the end answers "

NoBigText:
"big.txt would not open, answer "
NoSmallText:
"small.txt would not read
"
NoRenameText:
"it would not rename
"
NewLine:
"
"

Index:
  0x00 0x00
Left:
  0x00 0x00
Fletch1:
  0x00
Fletch2:
  0x00
Kept1:
  0x00
Kept2:
  0x00
Why:
  0x00

; One block, which is the whole point: the big file is four hundred times this.
Block:
  #Reserve 0d256

; And room for the small one all at once, so that the two ways of reading it can be
; compared against each other.
Whole:
  #Reserve 0d1024
