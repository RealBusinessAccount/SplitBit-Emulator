; The names in the Vector Segment, and what numbers they have.
;
; A vector name is not a label and the two are kept deliberately apart, so a program may
; call a routine `announce` and name a vector `announce` without either shadowing the
; other. They are looked up in different places because they mean different things: a label
; is an address and a vector is a number.
;
; FIXED FIELDS HERE, unlike the label table's arena. There are at most a couple of hundred
; of these against several hundred labels, and the names are short, so packing them would
; cost more code than it saved. Twenty four bytes an entry: a name of up to twenty two with
; its zero, and the number.
;
; Numbers come from two places. A pinned one is written down in the source, and that is how
; anything two separately assembled programs must agree about is fixed - the system's
; services are all pinned. Everything else is numbered automatically from 64 up, out of a
; range nothing outside one program can name, so what number it gets cannot matter.
;
; Written by Anachronaut

#Program

vecReset:
  SETD.0 VecCount
  CALL numZero
  INIA 0d64
  SETD.0 VecNextAuto
  STA.0
  RET

; Declares the name at DP0 with the number in A. Q is zero if it went in.
vecDeclare:
  SETD.2 VecPutNumber
  STA.2
  SETD.2 VecSubject
  STD.0.2

  CALL vecFind
  BNQ vecDeclareFresh
  SETD.0 VecTwice
  CALL clsComplain
  BRI vecDeclareNo

vecDeclareFresh:
  SETD.0 VecCount
  SETD.2 VecLimit
  CALL numCompare
  BNC vecDeclareFull

  SETD.0 VecWhich
  SETD.2 VecCount
  CALL numSet
  CALL vecSlotAt

  SETD.1 VecSubject
  LDD.0.1
  SETD.1 VecSlot
  LDD.1.1
  CALL srcKeepName
  SETD.1 VecSlot
  LDD.0.1
  INIA 0d23
  SETD.0 VecSlot
  CALL numAddByte
  SETD.1 VecSlot
  LDD.0.1
  SETD.2 VecPutNumber
  LDA.2
  STA.0

  SETD.0 VecCount
  CALL numStep
  RSTA
  RSTB
  CCF
  ADD
  RET

vecDeclareFull:
  SETD.0 VecFull
  CALL clsComplain
vecDeclareNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; The next number nothing has taken, into VecPutNumber. These start at 64, above everything
; that may be pinned, so a name a program made up for itself can never land on a system
; service.
;
; Into memory rather than into A, because a CALL puts A back as it found it.
vecTakeAuto:
  SETD.0 VecNextAuto
  LDA.0
  SETD.0 VecPutNumber
  STA.0
  SETD.0 VecNextAuto
  LDA.0
  INCA
  STA.0
  RET

; Looks up the name at DP0. Q is zero if it is there, and then VecNumber is its number.
vecFind:
  SETD.2 VecSought
  STD.0.2
  SETD.0 VecWhich
  CALL numZero

vecFindLoop:
  SETD.0 VecWhich
  SETD.2 VecCount
  CALL numCompare
  BNC vecFindMissing

  CALL vecSlotAt
  SETD.1 VecSlot
  LDD.0.1
  SETD.1 VecSought
  LDD.1.1
  CALL sameText
  BRQ vecFindGot

  SETD.0 VecWhich
  CALL numStep
  BRI vecFindLoop

vecFindGot:
  SETD.1 VecSlot
  LDD.0.1
  INIA 0d23
  SETD.0 VecSlot
  CALL numAddByte
  SETD.1 VecSlot
  LDD.0.1
  LDA.0
  SETD.0 VecNumber
  STA.0
  RSTA
  RSTB
  CCF
  ADD
  RET

vecFindMissing:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Where entry number VecWhich sits, into VecSlot. Twenty four bytes an entry.
vecSlotAt:
  SETD.0 VecNames
  SETD.1 VecSlot
  STD.0.1
  SETD.0 VecSlotLeft
  SETD.2 VecWhich
  CALL numSet
vecSlotLoop:
  SETD.0 VecSlotLeft
  LDA.0
  INCD.0
  LDB.0
  OR
  BRQ vecSlotDone
  INIA 0d24
  SETD.0 VecSlot
  CALL numAddByte
  SETD.0 VecSlotLeft
  SETD.2 VecOne
  CALL numTake
  BRI vecSlotLoop
vecSlotDone:
  RET

#Data

VecCount:
  0x00 0x00
VecWhich:
  0x00 0x00
VecSlot:
  0x00 0x00
VecSlotLeft:
  0x00 0x00
VecSought:
  0x00 0x00
VecSubject:
  0x00 0x00
VecNumber:
  0x00
VecPutNumber:
  0x00
VecNextAuto:
  0x00
VecOne:
  0x00 0x01

; Sixty four names, which is every number a program may name for itself.
VecLimit:
  0x00 0x40

VecTwice:
"that vector name is declared twice"
VecFull:
"too many vector names"

VecName:
  #Reserve 0d23

VecNames:
  #Reserve 0d1536
