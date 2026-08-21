; The label table: the only thing that survives between the two passes.
;
; Names are packed end to end in an arena and each index entry holds a pointer into it,
; rather than every entry carrying a field wide enough for the longest name. MEASURED on
; CosmOS, which is the biggest thing this will ever be asked to assemble: 453 labels
; averaging 11.3 characters. Packed they come to about 7,400 bytes; in 32 byte fields they
; would come to 15,400. The arena is worth the handful of extra instructions.
;
; Four bytes an index entry: two saying where the name is, two saying what it resolves to.
;
; A name is stored WITHOUT its colon, so that a definition and a use of it compare equal
; without either side having to know which it was looking at.
;
; The first pass fills this and the second only reads it. That is what makes a forward
; reference ordinary rather than special: by the time anything is emitted, every name in
; the program already has an address.
;
; Written by Anachronaut

#Program

; Empties the table.
labReset:
  SETD.0 LabCount
  CALL numZero
  SETD.0 LabUsed
  CALL numZero
  SETD.0 LabArena
  SETD.1 LabNext
  STD.0.1
  SETD.0 LabIndex
  SETD.1 LabBase
  STD.0.1
  RET

; Adds the name at DP0, meaning the address in A and B. Q is zero if it went in.
;
; A name already in the table is refused rather than replaced: one name may mean one place,
; and quietly taking the second would move everything that referred to the first.
labAdd:
  SETD.2 LabPutAddress
  STA.2
  INCD.2
  STB.2
  SETD.2 LabSubject
  STD.0.2

  CALL labFind
  BNQ labAddFresh
  SETD.0 LabTwice
  CALL labComplain
  BRI labAddNo

labAddFresh:
  SETD.0 LabCount
  SETD.2 LabLimit
  CALL numCompare
  BNC labAddFull            ; The index is as full as it goes.

  ; And the arena, counting the zero that ends the name.
  SETD.1 LabSubject
  LDD.0.1
  CALL labLength
  SETD.0 LabEnd
  SETD.2 LabUsed
  CALL numSet
  SETD.0 LabEnd
  SETD.2 LabLength
  CALL numAdd
  SETD.0 LabRoom
  SETD.2 LabEnd
  CALL numCompare
  BRC labAddCrowded         ; The arena is smaller than where this name would end.

  ; The index entry: where the name is about to go, and what it means.
  SETD.0 LabWhich
  SETD.2 LabCount
  CALL numSet
  CALL labEntryAt

  SETD.1 LabEntry
  LDD.0.1
  SETD.1 LabNext
  LDD.1.1
  PSHD.1
  POPB
  POPA                      ; The low byte is on top, the way a pointer is pushed.
  STA.0
  INCD.0
  STB.0
  INCD.0
  SETD.2 LabPutAddress
  LDA.2
  STA.0
  INCD.0
  INCD.2
  LDA.2
  STA.0

  ; And the name itself, into the arena.
  SETD.1 LabNext
  LDD.1.1
  SETD.2 LabSubject
  LDD.0.2
labAddLoop:
  LDA.0
  STA.1
  BRA labAddCopied
  INCD.0
  INCD.1
  BRI labAddLoop
labAddCopied:
  INCD.1                    ; Past the zero, which was copied with the rest.
  SETD.0 LabNext
  STD.1.0

  SETD.0 LabUsed
  SETD.2 LabLength
  CALL numAdd
  SETD.0 LabCount
  CALL numStep

  RSTA
  RSTB
  CCF
  ADD
  RET

labAddFull:
  SETD.0 LabFull
  CALL labComplain
  BRI labAddNo
labAddCrowded:
  SETD.0 LabNoRoom
  CALL labComplain
labAddNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Looks up the name at DP0. Q is zero if it is there, and then LabAddress is what it means.
;
; A straight walk from the front. With 453 labels and a few thousand uses of them that is
; the slowest thing the assembler does, and it is deliberately the simple version: sorting
; the table or bucketing it on the first character are both easy later, and neither is
; worth writing before anything has been measured.
labFind:
  SETD.2 LabSought
  STD.0.2
  SETD.0 LabWhich
  CALL numZero

labFindLoop:
  SETD.0 LabWhich
  SETD.2 LabCount
  CALL numCompare
  BNC labFindMissing        ; Walked the whole table without a match.

  CALL labEntryAt
  SETD.1 LabEntry
  LDD.0.1
  LDA.0
  INCD.0
  LDB.0
  SETD.0 LabNamePointer
  STA.0
  INCD.0
  STB.0

  SETD.1 LabNamePointer
  LDD.0.1
  SETD.1 LabSought
  LDD.1.1
  CALL labSame
  BRQ labFindGot

  SETD.0 LabWhich
  CALL numStep
  BRI labFindLoop

labFindGot:
  SETD.1 LabEntry
  LDD.0.1
  INCD.0
  INCD.0
  LDA.0
  INCD.0
  LDB.0
  SETD.0 LabAddress
  STA.0
  INCD.0
  STB.0
  RSTA
  RSTB
  CCF
  ADD
  RET

labFindMissing:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Where entry number LabWhich is, into LabEntry. Four bytes an entry, so the offset is the
; number doubled twice - there being no multiply on this machine, and none needed.
labEntryAt:
  SETD.0 LabOffset
  SETD.2 LabWhich
  CALL numSet
  SETD.0 LabOffset
  SETD.2 LabOffset
  CALL numAdd
  SETD.0 LabOffset
  SETD.2 LabOffset
  CALL numAdd
  SETD.0 LabEntry
  SETD.2 LabBase
  CALL numSet
  SETD.0 LabEntry
  SETD.2 LabOffset
  CALL numAdd
  RET

; Q is zero if the strings at DP0 and DP1 are the same, both ending in a zero byte.
labSame:
  LDA.0
  LDB.1
  CCF
  SUB
  BNQ labSameDone
  LDA.0
  BRA labSameDone           ; They ended together, so they matched all the way.
  INCD.0
  INCD.1
  BRI labSame
labSameDone:
  RET

; How long the string at DP0 is, counting the zero on the end, into LabLength.
labLength:
  SETD.1 LabLenWalk
  STD.0.1
  SETD.0 LabLength
  CALL numZero
labLengthLoop:
  SETD.0 LabLength
  CALL numStep
  SETD.1 LabLenWalk
  LDD.0.1
  LDA.0
  BRA labLengthDone
  SETD.0 LabLenWalk
  CALL numStep
  BRI labLengthLoop
labLengthDone:
  RET

labComplain:
  SWI osPrintString
  SETD.0 LabNamed
  SWI osPrintString
  SETD.0 TokText
  SWI osPrintString
  SETD.0 LabAtLine
  SWI osPrintString
  SETD.0 TokLine
  LDA.0
  INCD.0
  LDB.0
  SWI osPrintNumber
  SETD.0 LabNewLine
  SWI osPrintString
  RET

#Data

LabCount:
  0x00 0x00
LabUsed:
  0x00 0x00
LabNext:
  0x00 0x00
LabBase:
  0x00 0x00
LabAddress:
  0x00 0x00
LabPutAddress:
  0x00 0x00
LabNamePointer:
  0x00 0x00
LabSought:
  0x00 0x00
LabSubject:
  0x00 0x00
LabEntry:
  0x00 0x00
LabOffset:
  0x00 0x00
LabWhich:
  0x00 0x00
LabLength:
  0x00 0x00
LabLenWalk:
  0x00 0x00
LabEnd:
  0x00 0x00

; How many labels there may be, and how many bytes of name between them. Sized for a
; single program rather than for CosmOS: raising either is changing a number here, and
; running into one says so rather than writing past the end of the table.
LabLimit:
  0x01 0x00
LabRoom:
  0x08 0x00

LabNamed:
": "
LabAtLine:
", at line "
LabNewLine:
"
"
LabTwice:
"that label is defined twice"
LabFull:
"too many labels"
LabNoRoom:
"no room left for label names"

LabIndex:
  #Reserve 0d1024
LabArena:
  #Reserve 0d2048
