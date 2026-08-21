; The SplitBit assembler, running on SplitBit.
;
;   > load Asm.sbx
;   > run hello.asm
;
; Loading and running are separate commands in this shell, so the file to assemble is the
; argument to run rather than a second name after the program's.
;
; Reads assembly source off the disk and writes a binary back to it, with no host involved
; anywhere. The output has to be byte for byte what the C assembler produces from the same
; source, which is the only honest test of it and the one the suite runs.
;
; ---- Two passes over a file that is never held ----
;
; The C assembler reads every token of every file into one array and works on that. It
; cannot be done that way here and never could: cosmos.asm alone is 56,047 bytes of source
; against 64K of Data Memory, and the token array for it would be several times that. So
; the source is streamed through a 256 byte window, twice, and the only thing kept between
; the passes is the label table.
;
; TWO PASSES ARE ENOUGH BECAUSE EVERY LENGTH IS KNOWN WITHOUT RESOLVING ANYTHING. How many
; bytes a token comes to falls out of what the token is - an instruction's from its shape,
; a value's is one, a string's is its characters and a zero - and never from the value of
; anything named. So the first pass can work out exactly where every label lands, and the
; second never needs a fixup list or a second look. A forward reference stops being a
; problem and becomes the reason there are two passes at all.
;
; ---- What this one does not do yet ----
;
; #Include, #Base, #Align, #Reserve and #Vectors are refused by name rather than ignored.
; An assembler that quietly skipped a directive would produce a file that looked right and
; was the wrong length, which is the worst thing it could do.
;
; Written by Anachronaut

#Include services.asm

#Program

  #Base 0x2000

start:
  SETD.0 Argument
  INIB 0d23
  SWI osArgument
  SETD.0 Argument
  LDA.0
  BRA sayUsage

  CALL deriveName

  SETD.0 Argument
  CALL srcOpen
  BNQ noSource

  CALL passOne
  BNQ stopped
  CALL layOutImage
  BNQ stopped
  CALL passTwo
  BNQ stopped
  CALL writeImage
  BNQ stopped

  CALL report
  SWI osExit

stopped:
  SETD.0 StoppedText
  SWI osPrintString
  SWI osExit

sayUsage:
  SETD.0 UsageText
  SWI osPrintString
  SWI osExit

noSource:
  SETD.0 NoSourceText
  SWI osPrintString
  SETD.0 Argument
  SWI osPrintString
  SETD.0 NewLine
  SWI osPrintString
  SWI osExit

; ---- The first pass: how long everything is, and where every label lands ----

passOne:
  CALL labReset
  CALL beginPass

oneLoop:
  CALL tokNext
  BNQ oneDone
  CALL clsToken
  BNQ passFailed

  SETD.0 ClsType
  LDA.0
  INIB 0d0
  XOR
  BRQ oneKeyword
  SETD.0 ClsType
  LDA.0
  INIB 0d4
  XOR
  BRQ oneDefinition
  CALL checkPlacement
  BNQ passFailed
  BRI oneAdvance

oneKeyword:
  CALL doKeyword
  BNQ passFailed
  BRI oneLoop               ; A keyword is no bytes, so there is nothing to advance.

oneDefinition:
  ; The colon is not part of the name. Writing a zero over it here means a definition and
  ; a use of the same name compare equal without either side knowing which it is.
  CALL dropColon
  SETD.0 Status
  LDA.0
  BRA labelNowhere

  SETD.0 ProgAt
  SETD.2 Status
  LDA.2
  INIB 0d1
  XOR
  BRQ oneDefineHere
  SETD.0 DataAt
oneDefineHere:
  LDA.0
  INCD.0
  LDB.0
  SETD.0 TokText
  CALL labAdd
  BNQ passFailed
  BRI oneLoop               ; A definition is a name for a place, not a byte in it.

oneAdvance:
  CALL stepCursor
  BRI oneLoop

oneDone:
  RSTA
  RSTB
  CCF
  ADD
  RET

labelNowhere:
  SETD.0 LabelNowhereText
  CALL clsComplain
passFailed:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; ---- The second pass: the bytes themselves ----

passTwo:
  CALL srcRewind
  BNQ passFailed
  CALL beginStatus          ; The cursors are NOT reset. They are the first pass's answer,
                            ; the second pass writes through pointers of its own, and the
                            ; report at the end still has to say how long the segments are.

twoLoop:
  CALL tokNext
  BNQ twoDone
  CALL clsToken
  BNQ passFailed

  SETD.0 ClsType
  LDA.0
  SETD.0 EmitKind
  STA.0

  INIB 0d0
  XOR
  BRQ twoKeyword
  SETD.0 EmitKind
  LDA.0
  INIB 0d1
  XOR
  BRQ twoInstruction
  SETD.0 EmitKind
  LDA.0
  INIB 0d2
  XOR
  BRQ twoValue
  SETD.0 EmitKind
  LDA.0
  INIB 0d3
  XOR
  BRQ twoString
  SETD.0 EmitKind
  LDA.0
  INIB 0d4
  XOR
  BRQ twoLoop               ; A definition emits nothing; the first pass took its address.
  BRI twoReference

twoKeyword:
  CALL doKeyword
  BNQ passFailed
  BRI twoLoop

twoInstruction:
  SETD.0 ClsOpcode
  LDA.0
  CALL emitByte

  ; The selectors follow the opcode, and they are written whether or not the programmer
  ; wrote them: leaving one off means Data Pointer 0 rather than no pointer at all.
  RSTA
  SETD.0 EmitLeft
  STA.0
twoSelectorLoop:
  SETD.0 EmitLeft
  LDA.0
  SETD.2 ClsWanted
  LDB.2
  CCF
  SUB
  BRQ twoLoop
  SETD.0 ClsSelectorValue
  SETD.2 EmitLeft
  LDA.2
  CALL byteAt
  SETD.0 ClsByte
  LDA.0
  CALL emitByte
  SETD.0 EmitLeft
  LDA.0
  INCA
  STA.0
  BRI twoSelectorLoop

twoValue:
  SETD.0 ClsValue
  LDA.0
  CALL emitByte
  BRI twoLoop

twoString:
  SETD.0 TokText
  SETD.1 EmitWalk
  STD.0.1
twoStringLoop:
  SETD.1 EmitWalk
  LDD.0.1
  LDA.0
  CALL emitByte
  SETD.0 EmitWalk
  CALL numStep
  SETD.1 EmitWalk
  LDD.0.1
  DPDN.0 0d01
  LDA.0
  BNA twoStringLoop         ; The zero goes out with the rest and then stops the loop.
  BRI twoLoop

twoReference:
  SETD.0 TokText
  CALL labFind
  BNQ twoUnknown
  SETD.0 LabAddress
  LDA.0
  CALL emitByte
  SETD.0 LabAddress
  INCD.0
  LDA.0
  CALL emitByte
  BRI twoLoop

twoUnknown:
  SETD.0 UnknownText
  CALL clsComplain
  BRI passFailed

twoDone:
  RSTA
  RSTB
  CCF
  ADD
  RET

; ---- What both passes have in common ----

beginPass:
  CALL beginStatus
  SETD.0 ProgAt
  CALL numZero
  SETD.0 DataAt
  CALL numZero
  RET

; No segment is open until a #Program or #Data says so, at the start of either pass.
beginStatus:
  RSTA
  SETD.0 Status
  STA.0
  RET

; Moves the cursor of whichever segment is open along by what this token comes to.
stepCursor:
  SETD.0 Status
  LDA.0
  INIB 0d1
  XOR
  BRQ stepProgram
  SETD.0 DataAt
  BRI stepBy
stepProgram:
  SETD.0 ProgAt
stepBy:
  SETD.2 ClsLength
  LDA.2
  CALL numAddByte
  RET

; Is this token allowed where it is? The rules are the C assembler's, and they exist
; because each of these has a way of going wrong quietly.
checkPlacement:
  SETD.0 ClsType
  LDA.0
  INIB 0d1
  XOR
  BRQ placeInstruction
  SETD.0 ClsType
  LDA.0
  INIB 0d3
  XOR
  BRQ placeString
  ; A value or a name, which needs somewhere to go but does not care which.
  SETD.0 Status
  LDA.0
  BRA placeNowhere
  BRI placeYes

placeInstruction:
  SETD.0 Status
  LDA.0
  INIB 0d1
  XOR
  BNQ placeNotProgram
  BRI placeYes

placeString:
  ; A string in Program Memory could not be read by the program holding it: instructions
  ; reach Data Memory only. It would assemble and then be unreachable.
  SETD.0 Status
  LDA.0
  INIB 0d1
  XOR
  BRQ placeStringInProgram
  SETD.0 Status
  LDA.0
  BRA placeNowhere

placeYes:
  RSTA
  RSTB
  CCF
  ADD
  RET

placeNowhere:
  SETD.0 NowhereText
  CALL clsComplain
  BRI placeNo
placeNotProgram:
  SETD.0 NotProgramText
  CALL clsComplain
  BRI placeNo
placeStringInProgram:
  SETD.0 StringInProgramText
  CALL clsComplain
placeNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; #Program and #Data change which segment is open. Everything else the C assembler
; understands is refused by name, because an assembler that skipped a directive would
; produce a file that looked right and was the wrong length.
doKeyword:
  SETD.0 TokText
  SETD.1 WordProgram
  CALL labSame
  BRQ keywordProgram
  SETD.0 TokText
  SETD.1 WordData
  CALL labSame
  BRQ keywordData
  SETD.0 NotYetText
  CALL clsComplain
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

keywordProgram:
  INIA 0d1
  BRI keywordSet
keywordData:
  INIA 0d2
keywordSet:
  SETD.0 Status
  STA.0
  RSTA
  RSTB
  CCF
  ADD
  RET

; Writes a zero over the colon on the end of a label definition.
dropColon:
  SETD.0 TokLength
  LDA.0
  BRA dropColonDone
  DECA
  SETD.0 TokLength
  STA.0
  SETD.0 TokText
  SETD.1 DropWalk
  STD.0.1
  SETD.0 DropWalk
  SETD.2 TokLength
  LDA.2
  CALL numAddByte
  SETD.1 DropWalk
  LDD.0.1
  RSTA
  STA.0
dropColonDone:
  RET

; ---- The output image ----

; Where each segment's bytes will go, and the header in front of them. Both lengths are
; known now, which is the whole reason the first pass exists.
layOutImage:
  ; Nineteen bytes of format: the magic, a version, four feature flags, and a marker and
  ; a length for each of the two segments.
  SETD.0 ImgTotal
  SETD.2 ProgAt
  CALL numSet
  SETD.0 ImgTotal
  SETD.2 DataAt
  CALL numAdd
  INIA 0d19
  SETD.0 ImgTotal
  CALL numAddByte

  SETD.0 ImgRoom
  SETD.2 ImgTotal
  CALL numCompare
  BRC imageTooBig

  SETD.0 Image
  SETD.1 ProgPut
  STD.0.1
  SETD.0 ProgPut
  INIA 0d14
  CALL numAddByte

  SETD.0 ImgWalk
  SETD.2 ProgAt
  CALL numSet
  INIA 0d19
  SETD.0 ImgWalk
  CALL numAddByte
  SETD.0 Image
  SETD.1 DataPut
  STD.0.1
  SETD.0 DataPut
  SETD.2 ImgWalk
  CALL numAdd

  ; The header, written straight into the front of the image.
  SETD.0 Image
  SETD.1 ImgWalk
  STD.0.1
  SETD.0 MagicSPBT
  INIA 0d4
  CALL putBytes
  INIA 0d1
  CALL putByte              ; The format version.
  RSTA
  CALL putByte
  CALL putByte
  CALL putByte
  CALL putByte              ; Four bytes of feature flags, none of them asked for.
  SETD.0 MagicPRG
  INIA 0d3
  CALL putBytes
  SETD.0 ProgAt
  CALL putWord

  ; And the marker between the segments, which sits after the program bytes.
  SETD.0 Image
  SETD.1 ImgWalk
  STD.0.1
  SETD.0 ImgWalk
  INIA 0d14
  CALL numAddByte
  SETD.0 ImgWalk
  SETD.2 ProgAt
  CALL numAdd
  SETD.0 MagicDAT
  INIA 0d3
  CALL putBytes
  SETD.0 DataAt
  CALL putWord

  RSTA
  RSTB
  CCF
  ADD
  RET

imageTooBig:
  SETD.0 TooBigText
  SWI osPrintString
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Puts A down at ImgWalk and steps it.
putByte:
  SETD.0 ImgHold
  STA.0
  SETD.1 ImgWalk
  LDD.0.1
  SETD.2 ImgHold
  LDA.2
  STA.0
  INCD.0
  STD.0.1
  RET

; Puts A bytes from DP0 down at ImgWalk.
putBytes:
  SETD.1 ImgCount
  STA.1
  SETD.1 ImgFrom
  STD.0.1
putBytesLoop:
  SETD.0 ImgCount
  LDA.0
  BRA putBytesDone
  DECA
  STA.0
  SETD.1 ImgFrom
  LDD.0.1
  LDA.0
  CALL putByte
  SETD.0 ImgFrom
  CALL numStep
  BRI putBytesLoop
putBytesDone:
  RET

; Puts the two byte number at DP0 down at ImgWalk, most significant first, the way every
; number in this format is stored.
putWord:
  SETD.1 ImgFrom
  STD.0.1
  LDA.0
  CALL putByte
  SETD.1 ImgFrom
  LDD.0.1
  INCD.0
  LDA.0
  CALL putByte
  RET

; Puts A into whichever segment is open, and steps that segment's pointer.
emitByte:
  SETD.0 EmitHold
  STA.0
  SETD.0 Status
  LDA.0
  INIB 0d1
  XOR
  BRQ emitToProgram
  SETD.1 DataPut
  BRI emitPut
emitToProgram:
  SETD.1 ProgPut
emitPut:
  LDD.0.1
  SETD.2 EmitHold
  LDA.2
  STA.0
  INCD.0
  STD.0.1
  RET

; The byte at DP0 offset by A, into ClsByte. The classifier has one of these; this is the
; assembler's, because a routine over there answers into a variable over there.
byteAt:
  PSHA
  PSHD.0
  POPB
  POPA
  SETD.0 EmitWalk
  STA.0
  INCD.0
  STB.0
  POPA
  SETD.0 EmitWalk
  CALL numAddByte
  SETD.1 EmitWalk
  LDD.0.1
  LDA.0
  SETD.0 ClsByte
  STA.0
  RET

writeImage:
  SETD.0 OutName
  SETD.1 Image
  SETD.2 ImgTotal
  LDA.2
  INCD.2
  LDB.2
  SWI osFileSave
  BNQ writeFailed
  RSTA
  RSTB
  CCF
  ADD
  RET

writeFailed:
  SETD.0 NoWriteText
  SWI osPrintString
  SETD.0 OutName
  SWI osPrintString
  SETD.0 NewLine
  SWI osPrintString
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; What the source file is called with its extension replaced, so that hello.asm becomes
; hello.bin without anybody having to say so twice.
deriveName:
  SETD.0 Argument
  SETD.1 OutName
  CALL copyName
  SETD.0 OutName
  SETD.1 DotAt
  STD.0.1
  SETD.0 DotFound
  CALL numZero

  SETD.0 OutName
  SETD.1 NameWalk
  STD.0.1
deriveLoop:
  SETD.1 NameWalk
  LDD.0.1
  LDA.0
  BRA deriveEnd
  INIB 0x2E                 ; '.'
  XOR
  BNQ deriveStep
  SETD.0 DotAt
  SETD.2 NameWalk
  CALL numSet
  INIA 0d1
  SETD.0 DotFound
  STA.0
deriveStep:
  SETD.0 NameWalk
  CALL numStep
  BRI deriveLoop

deriveEnd:
  SETD.0 DotFound
  LDA.0
  BNA deriveAtDot
  SETD.0 DotAt
  SETD.2 NameWalk
  CALL numSet               ; No extension at all, so the new one goes on the end.
deriveAtDot:
  SETD.1 DotAt
  LDD.1.1
  SETD.0 Extension
deriveCopy:
  LDA.0
  STA.1
  BRA deriveDone
  INCD.0
  INCD.1
  BRI deriveCopy
deriveDone:
  RET

; Copies the string at DP0 to DP1, up to 22 characters and the zero after them.
copyName:
  INIA 0d22
  SETD.2 NameLeft
  STA.2
copyNameLoop:
  LDA.0
  BRA copyNameEnd
  STA.1
  INCD.0
  INCD.1
  SETD.2 NameLeft
  LDA.2
  DECA
  STA.2
  BNA copyNameLoop
copyNameEnd:
  RSTA
  STA.1
  RET

report:
  SETD.0 WroteText
  SWI osPrintString
  SETD.0 OutName
  SWI osPrintString
  SETD.0 ProgramText
  SWI osPrintString
  SETD.0 ProgAt
  LDA.0
  INCD.0
  LDB.0
  SWI osPrintNumber
  SETD.0 DataText
  SWI osPrintString
  SETD.0 DataAt
  LDA.0
  INCD.0
  LDB.0
  SWI osPrintNumber
  SETD.0 LabelsText
  SWI osPrintString
  SETD.0 LabCount
  LDA.0
  INCD.0
  LDB.0
  SWI osPrintNumber
  SETD.0 LabelsEnd
  SWI osPrintString
  RET

#Data

  #Base 0x1000

Argument:
  #Reserve 0d23
OutName:
  #Reserve 0d27
NameWalk:
  0x00 0x00
NameLeft:
  0x00
DotAt:
  0x00 0x00
DotFound:
  0x00 0x00

Status:
  0x00
ProgAt:
  0x00 0x00
DataAt:
  0x00 0x00

ProgPut:
  0x00 0x00
DataPut:
  0x00 0x00
EmitHold:
  0x00
EmitKind:
  0x00
EmitLeft:
  0x00
EmitWalk:
  0x00 0x00

ImgTotal:
  0x00 0x00
ImgWalk:
  0x00 0x00
ImgFrom:
  0x00 0x00
ImgCount:
  0x00
ImgHold:
  0x00
DropWalk:
  0x00 0x00

; How big a binary this can build. Everything the assembler makes has to fit here at once,
; because a file is written in one call and there is nowhere to put half of one.
ImgRoom:
  0x10 0x00

MagicSPBT:
"SPBT"
MagicPRG:
"PRG"
MagicDAT:
"DAT"
Extension:
".bin"

WordProgram:
"#Program"
WordData:
"#Data"

UsageText:
"say which file to assemble, as in: run hello.asm
"
NoSourceText:
"no such file: "
NewLine:
"
"
NowhereText:
"that has to be inside a segment, and no #Program or #Data has opened one"
NotProgramText:
"an instruction outside the Program Segment"
StringInProgramText:
"a string cannot go in the Program Segment, because an instruction cannot read it there"
LabelNowhereText:
"a label defined outside a segment, so there is nowhere for it to point"
UnknownText:
"no label of that name is defined anywhere in this program"
NotYetText:
"this assembler does not understand that directive yet"
TooBigText:
"the binary would be bigger than this assembler has room to build
"
NoWriteText:
"it would not write "
StoppedText:
"nothing was written
"
WroteText:
"wrote "
ProgramText:
": program "
DataText:
", data "
LabelsText:
", labels "
LabelsEnd:
"
"

Image:
  #Reserve 0d4096

#Include numbers.asm
#Include source.asm
#Include token.asm
#Include classify.asm
#Include labels.asm
#Include table.asm
