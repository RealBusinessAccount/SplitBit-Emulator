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

  SETD.0 Argument
  CALL srcOpen
  BNQ noSource

  CALL passOne
  BNQ stopped
  CALL settleFormat
  CALL deriveName           ; After the first pass: what it is called depends on whether a
                            ; #Base turned up, and that is not known until then.
  CALL layOutImage
  BNQ stopped
  CALL passTwo
  BNQ stopped
  CALL writeVectors
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

; ---- The passes ----
;
; ONE LOOP, WALKED TWICE. The first time it works out how long everything is and where
; every label lands; the second time it does all of that again and writes the bytes as
; well. Emitting is the only difference between them.
;
; That is deliberate. The two passes have to agree about the length of every single token,
; and the way they stop agreeing is by being two pieces of code that drifted apart - which
; is exactly the shape of the bug this assembler found in the C one. Sharing the body means
; there is nothing to drift. What is left is checked anyway at the end of the second pass.

passOne:
  CALL labReset
  CALL vecReset
  RSTA
  SETD.0 Emitting
  STA.0
  CALL runPass
  BNQ passFailed
  CALL checkSegmentBases
  RET

passTwo:
  INIA 0d1
  SETD.0 Emitting
  STA.0
  CALL runPass
  BNQ passFailed

  ; The two passes must have counted the same, and if they did not, everything after the
  ; first disagreement is in the wrong place. Better to say so than to write the file.
  SETD.0 ProgAt
  SETD.2 ProgBase
  CALL numTake
  SETD.0 ProgAt
  SETD.2 ImgProgLen
  CALL numCompare
  BNQ passesDisagree
  SETD.0 DataAt
  SETD.2 DataBase
  CALL numTake
  SETD.0 DataAt
  SETD.2 ImgDataLen
  CALL numCompare
  BNQ passesDisagree
  RSTA
  RSTB
  CCF
  ADD
  RET

passesDisagree:
  SETD.0 DisagreeText
  SWI osPrintString
passFailed:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

runPass:
  CALL srcRestart
  BNQ passFailed
  CALL beginPass

passLoop:
  CALL tokNext
  BNQ passDone
  CALL clsToken
  BNQ passFailed

  ; ---- The Vector Segment, where nothing becomes a byte ----
  SETD.0 Status
  LDA.0
  INIB 0d3
  XOR
  BNQ passNotVectors
  SETD.0 ClsType
  LDA.0
  BNA passVectorLine        ; A keyword here is still a keyword.

passNotVectors:
  ; ---- A name after SWI is a vector, not an address ----
  ;
  ; One byte instead of two, and it is settled by what the name FOLLOWS rather than by
  ; anything about the name. That matters: the Vector Segment may not have been read yet,
  ; since it can live in a file included further down.
  SETD.0 ClsType
  LDA.0
  INIB 0d5
  XOR
  BNQ passNotVectorName
  SETD.0 AfterSwi
  LDA.0
  BRA passNotVectorName
  INIA 0d6
  SETD.0 ClsType
  STA.0
  INIA 0d1
  CALL clsSetLength

passNotVectorName:
  ; Whether the NEXT name is one of those depends on this token, so it is written down
  ; before this one is dealt with.
  RSTA
  SETD.0 AfterSwi
  STA.0
  SETD.0 ClsType
  LDA.0
  INIB 0d1
  XOR
  BNQ passNotSwi
  SETD.0 ClsOpcode
  LDA.0
  INIB 0x18
  XOR
  BNQ passNotSwi
  INIA 0d1
  SETD.0 AfterSwi
  STA.0

passNotSwi:
  SETD.0 ClsType
  LDA.0
  BNA passNotKeyword
  CALL doKeyword
  BNQ passFailed
  BRI passLoop              ; A keyword is no bytes, so there is nothing to move over.

passNotKeyword:
  SETD.0 ClsType
  LDA.0
  INIB 0d4
  XOR
  BNQ passNotDefinition
  CALL doDefinition
  BNQ passFailed
  BRI passLoop              ; A definition names a place; it does not take one up.

passNotDefinition:
  CALL checkPlacement
  BNQ passFailed
  CALL markSegmentUsed
  SETD.0 Emitting
  LDA.0
  BRA passMove
  CALL emitToken
  BNQ passFailed
passMove:
  SETD.2 ClsLength
  CALL moveCursor
  BRI passLoop

passVectorLine:
  CALL doVectorLine
  BNQ passFailed
  BRI passLoop

passDone:
  RSTA
  RSTB
  CCF
  ADD
  RET

; A label definition. The colon is not part of the name: writing a zero over it means a
; definition and a use of the same name compare equal without either side knowing which it
; is looking at.
doDefinition:
  CALL dropColon
  SETD.0 Status
  LDA.0
  BRA labelNowhere
  INIB 0d3
  XOR
  BRQ labelNowhere          ; The Vector Segment has no addresses to name.

  SETD.0 Emitting
  LDA.0
  BNA definitionDone        ; The first pass took its address; the second only re-reads it.

  SETD.0 ProgAt
  SETD.2 Status
  LDA.2
  INIB 0d1
  XOR
  BRQ definitionHere
  SETD.0 DataAt
definitionHere:
  LDA.0
  INCD.0
  LDB.0
  SETD.0 TokText
  CALL labAdd
  RET

definitionDone:
  RSTA
  RSTB
  CCF
  ADD
  RET

labelNowhere:
  SETD.0 LabelNowhereText
  CALL clsComplain
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; ---- A line of the Vector Segment ----
;
; Four shapes, and which one it is cannot be known without looking ahead:
;
;   name                      declared, and the assembler gives it a number
;   name 0dNN                 declared with a number both sides have agreed
;   name handler              this program implements it
;   name 0dNN handler         both at once
;   Device 0xNN handler       named by the port, because that is what decides it
;
; A LINE is what tells them apart. Two names on one line are a name and its handler; two
; names on two lines are two declarations. So the next token is read and handed back if it
; turns out to belong to the following entry.
;
; THE FIRST PASS DECLARES AND THE SECOND IMPLEMENTS. Handlers are addresses and no address
; is known until every label has been placed, so the second pass is the earliest a handler
; can be resolved - and by then the names are all in the table waiting for one.
doVectorLine:
  RSTA
  SETD.0 VecPinnedGiven
  STA.0
  SETD.0 VecHandlerHere
  STA.0
  SETD.0 VecIsDevice
  STA.0

  SETD.0 TokText
  SETD.1 WordDevice
  CALL sameFolded
  BNQ vectorNamed
  INIA 0d1
  SETD.0 VecIsDevice
  STA.0

vectorNamed:
  SETD.0 TokText
  SETD.1 VecName
  CALL srcKeepName
  SETD.0 VecLineWas
  SETD.2 TokLine
  CALL numSet

  ; ---- Whatever else is on this line ----
  CALL vectorNextOnLine
  BNQ vectorLineEnds

  SETD.0 ClsType
  LDA.0
  INIB 0d2
  XOR
  BNQ vectorMaybeHandler

  ; A number. Between a name and any handler it PINS the vector; after Device it says
  ; which port. Nothing else can appear there, because a label may not begin with a digit.
  INIA 0d1
  SETD.0 VecPinnedGiven
  STA.0
  SETD.0 VecPinned
  SETD.2 ClsValue
  LDA.2
  STA.0
  CALL vectorNextOnLine
  BNQ vectorLineEnds

vectorMaybeHandler:
  ; A name here is the handler. Its address is wanted, and only the second pass has one.
  SETD.0 ClsType
  LDA.0
  INIB 0d5
  XOR
  BNQ vectorOddToken
  INIA 0d1
  SETD.0 VecHandlerHere
  STA.0
  SETD.0 TokText
  SETD.1 VecHandlerName
  CALL srcKeepName

  ; Anything after the handler is a line that says too much.
  CALL vectorNextOnLine
  BRQ vectorTooMuch

vectorLineEnds:
  SETD.0 Emitting
  LDA.0
  BNA vectorImplement
  BRI vectorDeclareIt

; ---- The second pass: fill in the handler ----
vectorImplement:
  SETD.0 VecHandlerHere
  LDA.0
  BRA vectorLineDone        ; Nothing to implement, so nothing to do.

  SETD.0 VecHandlerName
  CALL labFind
  BNQ vectorNoHandler
  SETD.0 VecPutHandler
  SETD.2 LabAddress
  CALL numSet

  SETD.0 VecIsDevice
  LDA.0
  BNA vectorImplementDevice

  SETD.0 VecName
  CALL vecFind
  BNQ vectorLost
  CALL vecWriteHandler
  BRI vectorLineDone

vectorImplementDevice:
  ; A device brings no name, so there is nothing to look up: the entry is made now, in the
  ; place the line sits. Nothing can refer to it, which is why it needs no name of its own.
  SETD.0 VecPinned
  LDA.0
  SETD.0 VecPutNumber
  STA.0
  INIA 0d1
  SETD.0 VecPutBase
  STA.0
  SETD.0 DeviceName
  SETD.2 VecPutNumber
  LDA.2
  CALL vecDeclare
  BNQ vectorFailed
  SETD.0 DeviceName
  CALL vecFind
  BNQ vectorLost
  CALL vecWriteHandler
  CALL vecFreshDeviceName
  BRI vectorLineDone

; ---- The first pass: give it a number ----
vectorDeclareIt:
  SETD.0 VecIsDevice
  LDA.0
  BNA vectorDeviceCheck

  SETD.0 VecName
  CALL vecFind
  BRQ vectorAlready

  ; A reserved name is where the machine looks rather than where a program says to look,
  ; so its number is not anybody's to choose.
  CALL vectorReserved
  BNQ vectorNotReserved
  SETD.0 VecPinnedGiven
  LDA.0
  BNA vectorFixedNumber
  BRI vectorSetNumber

vectorNotReserved:
  SETD.0 VecPinnedGiven
  LDA.0
  BRA vectorAutoNumber

  ; A pinned number comes from the range set aside for what two separately assembled
  ; programs have to agree about. Below it belongs to the machine and above it is handed
  ; out by the assembler, so neither can be asked for.
  SETD.0 VecPinned
  LDA.0
  INIB 0d16
  CCF
  SUB
  BRC vectorBadNumber
  SETD.0 VecPinned
  LDA.0
  INIB 0d64
  CCF
  SUB
  BNC vectorBadNumber
  BRI vectorSetNumber

vectorAutoNumber:
  CALL vecTakeAuto
  SETD.0 VecPutNumber
  LDA.0
  SETD.0 VecPinned
  STA.0

vectorSetNumber:
  SETD.0 VecPinned
  LDA.0
  SETD.0 VecPutNumber
  STA.0
  RSTA
  SETD.0 VecPutBase
  STA.0
  SETD.0 VecName
  SETD.2 VecPutNumber
  LDA.2
  CALL vecDeclare
  BNQ vectorFailed
  BRI vectorLineDone

vectorAlready:
  ; Met before. A handler now is somebody implementing what was declared earlier; nothing
  ; but a handler means the name was declared twice.
  SETD.0 VecHandlerHere
  LDA.0
  BRA vectorTwice
  SETD.0 VecPinnedGiven
  LDA.0
  BRA vectorLineDone
  SETD.0 VecPinned
  LDA.0
  SETD.2 VecNumber
  LDB.2
  XOR
  BNQ vectorDisagrees        ; The two sides name different vectors by one name.
  BRI vectorLineDone

vectorDeviceCheck:
  ; Device says which port as a number, and then where to go.
  SETD.0 VecPinnedGiven
  LDA.0
  BRA vectorDeviceBare
  SETD.0 VecHandlerHere
  LDA.0
  BRA vectorDeviceBare

vectorLineDone:
  RSTA
  RSTB
  CCF
  ADD
  RET

; The next token of this line, if there is one. Q is zero if there was, and it has been
; classified; otherwise it has been handed back for the next entry to have.
vectorNextOnLine:
  CALL tokNext
  BNQ vectorNextNone
  SETD.0 TokLine
  SETD.2 VecLineWas
  CALL numCompare
  BNQ vectorNextOther
  CALL clsToken
  BNQ vectorNextNone
  RSTA
  RSTB
  CCF
  ADD
  RET

vectorNextOther:
  CALL tokBack
vectorNextNone:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Q is zero if VecName is one of the vectors the machine itself uses, and then VecPinned
; is the number it must have. These are matched without regard to case, the way mnemonics
; are: they are part of the language rather than names somebody chose.
vectorReserved:
  RSTA
  SETD.0 ReservedLeft
  STA.0
  SETD.0 ReservedNames
  SETD.1 ReservedWalk
  STD.0.1

reservedLoop:
  SETD.0 ReservedLeft
  LDA.0
  SETD.2 ReservedCount
  LDB.2
  CCF
  SUB
  BRQ reservedNo
  SETD.1 ReservedWalk
  LDD.0.1
  SETD.1 VecName
  CALL sameFolded
  BRQ reservedYes
  INIA 0d16
  SETD.0 ReservedWalk
  CALL numAddByte
  SETD.0 ReservedLeft
  LDA.0
  INCA
  STA.0
  BRI reservedLoop

reservedYes:
  SETD.1 ReservedWalk
  LDD.0.1
  DPUP.0 0d15
  LDA.0
  SETD.0 VecPinned
  STA.0
  RSTA
  RSTB
  CCF
  ADD
  RET

reservedNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Devices have no names of their own, so they are given one nothing can type: a space
; followed by a counter. It keeps them apart in a table that refuses a repeated name.
vecFreshDeviceName:
  SETD.0 DeviceName
  INCD.0
  LDA.0
  INCA
  STA.0
  RET

vectorFixedNumber:
  SETD.0 FixedNumberText
  CALL clsComplain
  BRI vectorFailed
vectorBadNumber:
  SETD.0 BadNumberText
  CALL clsComplain
  BRI vectorFailed
vectorTwice:
  SETD.0 VecTwiceText
  CALL clsComplain
  BRI vectorFailed
vectorDisagrees:
  SETD.0 DisagreeNumberText
  CALL clsComplain
  BRI vectorFailed
vectorDeviceBare:
  SETD.0 DeviceBareText
  CALL clsComplain
  BRI vectorFailed
vectorNoHandler:
  SETD.0 NoHandlerText
  CALL clsComplain
  BRI vectorFailed
vectorLost:
  SETD.0 LostVectorText
  CALL clsComplain
  BRI vectorFailed
vectorTooMuch:
  SETD.0 TooMuchText
  CALL clsComplain
  BRI vectorFailed
vectorOddToken:
  SETD.0 VectorOddText
  CALL clsComplain
vectorFailed:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; ---- The bytes of one token ----

emitToken:
  SETD.0 ClsType
  LDA.0
  INIB 0d1
  XOR
  BRQ emitInstruction
  SETD.0 ClsType
  LDA.0
  INIB 0d2
  XOR
  BRQ emitValue
  SETD.0 ClsType
  LDA.0
  INIB 0d3
  XOR
  BRQ emitString
  SETD.0 ClsType
  LDA.0
  INIB 0d6
  XOR
  BRQ emitVector
  BRI emitReference

emitInstruction:
  SETD.0 ClsOpcode
  LDA.0
  CALL emitByte

  ; The selectors follow the opcode, and they go out whether or not they were written:
  ; leaving one off means Data Pointer 0 rather than no pointer at all.
  RSTA
  SETD.0 EmitLeft
  STA.0
emitSelectorLoop:
  SETD.0 EmitLeft
  LDA.0
  SETD.2 ClsWanted
  LDB.2
  CCF
  SUB
  BRQ emitDone
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
  BRI emitSelectorLoop

emitValue:
  SETD.0 ClsValue
  LDA.0
  CALL emitByte
  BRI emitDone

emitString:
  SETD.0 TokText
  SETD.1 EmitWalk
  STD.0.1
emitStringLoop:
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
  BNA emitStringLoop        ; The zero goes out with the rest and then stops the loop.
  BRI emitDone

emitVector:
  SETD.0 TokText
  CALL vecFind
  BNQ emitNoVector
  SETD.0 VecNumber
  LDA.0
  CALL emitByte
  BRI emitDone

emitReference:
  SETD.0 TokText
  CALL labFind
  BNQ emitNoLabel
  SETD.0 LabAddress
  LDA.0
  CALL emitByte
  SETD.0 LabAddress
  INCD.0
  LDA.0
  CALL emitByte

emitDone:
  RSTA
  RSTB
  CCF
  ADD
  RET

emitNoLabel:
  SETD.0 UnknownText
  CALL clsComplain
  BRI emitStopped
emitNoVector:
  SETD.0 UnknownVectorText
  CALL clsComplain
emitStopped:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; ---- What both passes have in common ----

beginPass:
  RSTA
  SETD.0 Status
  STA.0
  SETD.0 AfterSwi
  STA.0
  SETD.0 ProgUsed
  STA.0
  SETD.0 DataUsed
  STA.0
  SETD.0 ProgBased
  STA.0
  SETD.0 DataBased
  STA.0
  SETD.0 ProgBase
  CALL numZero
  SETD.0 DataBase
  CALL numZero
  SETD.0 ProgAt
  CALL numZero
  SETD.0 DataAt
  CALL numZero
  RET

; Moves the cursor of whichever segment is open along by the two byte number at DP2.
moveCursor:
  SETD.0 ProgAt
  SETD.1 Status
  LDA.1
  INIB 0d1
  XOR
  BRQ moveInProgram
  SETD.0 DataAt
moveInProgram:
  CALL numAdd
  RET

markSegmentUsed:
  SETD.0 Status
  LDA.0
  INIB 0d1
  XOR
  BRQ markInProgram
  SETD.0 DataUsed
  BRI markSet
markInProgram:
  SETD.0 ProgUsed
markSet:
  INIA 0d1
  STA.0
  RET

; Is this token allowed where it is? The rules are the C assembler's, and each of them
; exists because that mistake has a way of going wrong quietly.
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
  INIB 0d3
  XOR
  BRQ placeNowhere
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
  INIB 0d2
  XOR
  BNQ placeNowhere

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

; A program that says where one of its segments goes and leaves the other one where it
; falls is not saying anything about the second - it is forgetting. The segment lands at
; zero, on top of whatever is there, and the program runs right up until it reads it.
checkSegmentBases:
  SETD.0 ProgBased
  LDA.0
  SETD.2 DataBased
  LDB.2
  XOR
  BRQ basesAgree

  SETD.0 ProgBased
  LDA.0
  BNA basesDataMissing
  SETD.0 ProgUsed
  LDA.0
  BNA basesMismatch
  BRI basesAgree

basesDataMissing:
  SETD.0 DataUsed
  LDA.0
  BNA basesMismatch

basesAgree:
  RSTA
  RSTB
  CCF
  ADD
  RET

basesMismatch:
  SETD.0 BasesText
  SWI osPrintString
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; ---- The directives ----
;
; Which one it is, and what that does. #Vectors is understood as far as declaring names;
; a program that IMPLEMENTS a vector needs a Vector Segment in the output file, which is
; not built yet and is refused rather than skipped. An assembler that quietly ignored a
; directive would produce a file that looked right and was the wrong length.
doKeyword:
  SETD.0 TokText
  SETD.1 WordProgram
  CALL sameText
  BRQ keywordProgram
  SETD.0 TokText
  SETD.1 WordData
  CALL sameText
  BRQ keywordData
  SETD.0 TokText
  SETD.1 WordVectors
  CALL sameText
  BRQ keywordVectors
  SETD.0 TokText
  SETD.1 WordBase
  CALL sameText
  BRQ keywordBase
  SETD.0 TokText
  SETD.1 WordInclude
  CALL sameText
  BRQ keywordInclude
  SETD.0 TokText
  SETD.1 WordReserve
  CALL sameText
  BRQ keywordReserve
  SETD.0 TokText
  SETD.1 WordAlign
  CALL sameText
  BRQ keywordAlign
  SETD.0 NotYetText
  CALL clsComplain
  BRI keywordNo

keywordProgram:
  INIA 0d1
  BRI keywordSet
keywordData:
  INIA 0d2
  BRI keywordSet
keywordVectors:
  INIA 0d3
keywordSet:
  SETD.0 Status
  STA.0
  BRI keywordYes

; #Base says where this segment is loaded, which is what makes a program a loadable one
; rather than a boot image. Labels then hold the addresses they will really have, because
; nothing relocates anything: this is right at assembly time or not at all.
keywordBase:
  SETD.0 Status
  LDA.0
  BRA baseNowhere
  INIB 0d3
  XOR
  BRQ baseNowhere           ; The Vector Segment has no cursor to be the base of.

  CALL takeNumber
  BNQ keywordNo

  ; A base says where the WHOLE segment begins, so it comes before anything is in it.
  CALL segmentIsUsed
  BRQ baseTooLate

  SETD.0 Status
  LDA.0
  INIB 0d1
  XOR
  BRQ baseProgram
  SETD.0 DataBase
  SETD.2 ClsWord
  CALL numSet
  SETD.0 DataAt
  SETD.2 ClsWord
  CALL numSet
  INIA 0d1
  SETD.0 DataBased
  STA.0
  BRI keywordYes

baseProgram:
  SETD.0 ProgBase
  SETD.2 ClsWord
  CALL numSet
  SETD.0 ProgAt
  SETD.2 ClsWord
  CALL numSet
  INIA 0d1
  SETD.0 ProgBased
  STA.0
  BRI keywordYes

; #Include: the reader takes over. It puts this file aside, opens that one, and pops back
; when it ends, so nothing else in either pass knows an include happened.
keywordInclude:
  CALL tokNext
  BNQ includeBare
  CALL tokUnread            ; The character in hand belongs to the file being put aside.
  SETD.0 TokText
  CALL srcInclude
  BNQ keywordNo
  BRI keywordYes

; #Reserve: a run of zero bytes, so a label can stand for a region rather than only its
; first byte.
keywordReserve:
  SETD.0 Status
  LDA.0
  BRA reserveNowhere
  INIB 0d3
  XOR
  BRQ reserveNowhere
  CALL takeNumber
  BNQ keywordNo
  SETD.0 RunLength
  SETD.2 ClsWord
  CALL numSet
  CALL layDownRun
  BRI keywordYes

; #Align: as many zeroes as it takes to reach the next multiple of what follows. HOW MANY
; THAT IS DEPENDS ON WHERE THE CURSOR HAS REACHED, so unlike everything else it cannot be
; worked out from the token alone - which is one reason both passes keep a cursor rather
; than the second one keeping only a write pointer.
keywordAlign:
  SETD.0 Status
  LDA.0
  BRA alignNowhere
  INIB 0d3
  XOR
  BRQ alignNowhere
  CALL takeNumber
  BNQ keywordNo
  CALL howFarToAlign
  BNQ keywordNo
  CALL layDownRun

keywordYes:
  RSTA
  RSTB
  CCF
  ADD
  RET

baseNowhere:
  SETD.0 BaseNowhereText
  CALL clsComplain
  BRI keywordNo
baseTooLate:
  SETD.0 BaseLateText
  CALL clsComplain
  BRI keywordNo
includeBare:
  SETD.0 IncludeBareText
  SWI osPrintString
  BRI keywordNo
reserveNowhere:
  SETD.0 ReserveNowhereText
  CALL clsComplain
  BRI keywordNo
alignNowhere:
  SETD.0 AlignNowhereText
  CALL clsComplain
keywordNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; The number after a directive, into ClsWord. Sixteen bits, because an address and a count
; are both wider than the one byte a literal inside a segment may be.
takeNumber:
  CALL tokNext
  BNQ takeNumberBare
  SETD.0 TokString
  LDA.0
  BNA takeNumberBad
  SETD.0 TokText
  LDA.0
  INIB 0x30
  XOR
  BNQ takeNumberBad
  CALL clsWord
  RET

takeNumberBare:
  SETD.0 NumberBareText
  SWI osPrintString
  BRI takeNumberNo
takeNumberBad:
  SETD.0 NumberBadText
  CALL clsComplain
takeNumberNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Q is zero if the open segment already has something in it.
segmentIsUsed:
  SETD.0 Status
  LDA.0
  INIB 0d1
  XOR
  BRQ segmentUsedProgram
  SETD.0 DataUsed
  BRI segmentUsedTest
segmentUsedProgram:
  SETD.0 ProgUsed
segmentUsedTest:
  LDA.0
  BNA segmentUsedYes
  RSTA
  INIB 0d1
  CCF
  ADD
  RET
segmentUsedYes:
  RSTA
  RSTB
  CCF
  ADD
  RET

; How many zeroes an #Align of ClsWord comes to from here, into RunLength.
;
; The remainder by repeated subtraction, since there is no divide. Alignments are small in
; practice and a segment is at most 64K, so this is bounded and rare.
howFarToAlign:
  SETD.0 ClsWord
  LDA.0
  INCD.0
  LDB.0
  OR
  BRQ alignByZero           ; A multiple of nothing is not a thing to ask for.

  SETD.0 AlignLeft
  SETD.2 ProgAt
  SETD.1 Status
  LDA.1
  INIB 0d1
  XOR
  BRQ alignFromProgram
  SETD.2 DataAt
alignFromProgram:
  CALL numSet

alignTakeLoop:
  SETD.0 AlignLeft
  SETD.2 ClsWord
  CALL numCompare
  BRC alignRemainder        ; What is left is smaller than the step, so that is the rest.
  SETD.0 AlignLeft
  SETD.2 ClsWord
  CALL numTake
  BRI alignTakeLoop

alignRemainder:
  ; Already on a boundary means no zeroes at all, not a whole step of them.
  SETD.0 AlignLeft
  LDA.0
  INCD.0
  LDB.0
  OR
  BRQ alignNone
  SETD.0 RunLength
  SETD.2 ClsWord
  CALL numSet
  SETD.0 RunLength
  SETD.2 AlignLeft
  CALL numTake
  BRI alignDone

alignNone:
  SETD.0 RunLength
  CALL numZero

alignDone:
  RSTA
  RSTB
  CCF
  ADD
  RET

alignByZero:
  SETD.0 AlignZeroText
  CALL clsComplain
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; RunLength bytes of nothing: the cursor moves over them in either pass, and the second
; one writes them out as well.
layDownRun:
  SETD.0 RunAt
  CALL numZero
layDownLoop:
  SETD.0 RunAt
  SETD.2 RunLength
  CALL numCompare
  BNC layDownDone
  SETD.0 Emitting
  LDA.0
  BRA layDownStep
  RSTA
  CALL emitByte
layDownStep:
  SETD.2 OneWord
  CALL moveCursor
  SETD.0 RunAt
  CALL numStep
  BRI layDownLoop
layDownDone:
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
; Which of the two file formats this is, settled once and written down.
;
; A program that says where it goes is a loadable one and gets the SBEX header; one that
; says nothing is a boot image and gets SPBT. The difference is not a version but a
; question of what the file needs of whatever reads it.
;
; ONE FLAG RATHER THAN THE TEST REPEATED. It is asked in seven places - the header, the
; extension, where the vectors go, whether they carry a marker, how long the file is, and
; whether a Boot line is the entry or a handler - and written out each time it read as an
; OR of the two bases, whose sense is the opposite of what most of those places want. One
; of the seven had it backwards and put a version one header on a file carrying vectors,
; which a loader is right to refuse.
settleFormat:
  RSTA
  SETD.0 Loadable
  STA.0
  SETD.0 ProgBased
  LDA.0
  SETD.2 DataBased
  LDB.2
  OR
  BRQ settleFormatDone
  INIA 0d1
  SETD.0 Loadable
  STA.0
settleFormatDone:
  RET

layOutImage:
  ; How long each segment came out, which is where its cursor ended less where it began.
  SETD.0 ImgProgLen
  SETD.2 ProgAt
  CALL numSet
  SETD.0 ImgProgLen
  SETD.2 ProgBase
  CALL numTake
  SETD.0 ImgDataLen
  SETD.2 DataAt
  CALL numSet
  SETD.0 ImgDataLen
  SETD.2 DataBase
  CALL numTake

  SETD.0 Loadable
  LDA.0
  BNA layOutLoadable

  ; ---- A boot image ----
  ;
  ; Nineteen bytes of format: the magic, a version, four feature flags, and a marker and a
  ; length in front of each of the two segments.
  SETD.0 ImgTotal
  SETD.2 ImgProgLen
  CALL numSet
  SETD.0 ImgTotal
  SETD.2 ImgDataLen
  CALL numAdd
  INIA 0d19
  SETD.0 ImgTotal
  CALL numAddByte
  CALL checkImageRoom
  BNQ layOutNo

  SETD.0 ImgWalk
  SETD.2 ScratchImage
  CALL numSet
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
  SETD.0 ImgProgLen
  CALL putWord

  ; The program bytes go where the walk has reached, and the marker between the segments
  ; sits after them.
  SETD.0 ProgPut
  SETD.2 ImgWalk
  CALL numSet
  SETD.0 ImgWalk
  SETD.2 ImgProgLen
  CALL numAdd
  SETD.0 MagicDAT
  INIA 0d3
  CALL putBytes
  SETD.0 ImgDataLen
  CALL putWord
  SETD.0 DataPut
  SETD.2 ImgWalk
  CALL numSet
  BRI layOutYes

layOutLoadable:
  ; ---- A loadable program ----
  ;
  ; Sixteen bytes, so the code begins at a round offset and finding it is one step. Nothing
  ; here relocates anything: the addresses are where the program was built to live.
  SETD.0 ImgTotal
  SETD.2 ImgProgLen
  CALL numSet
  SETD.0 ImgTotal
  SETD.2 ImgDataLen
  CALL numAdd
  INIA 0d16
  SETD.0 ImgTotal
  CALL numAddByte
  CALL checkImageRoom
  BNQ layOutNo

  SETD.0 ImgWalk
  SETD.2 ScratchImage
  CALL numSet
  SETD.0 MagicSBEX
  INIA 0d4
  CALL putBytes
  INIA 0d1
  CALL putByte              ; Version one: it brings no vectors.
  RSTA
  CALL putByte              ; And says so again, as a count of none.
  SETD.0 ProgBase
  CALL putWord
  ; Where to start. Without a Boot line that is the first byte of the code, which is where
  ; a program with nothing to say about it begins.
  SETD.0 ProgBase
  CALL putWord
  SETD.0 ImgProgLen
  CALL putWord
  SETD.0 DataBase
  CALL putWord
  SETD.0 ImgDataLen
  CALL putWord

  SETD.0 ProgPut
  SETD.2 ImgWalk
  CALL numSet
  SETD.0 DataPut
  SETD.2 ImgWalk
  CALL numSet
  SETD.0 DataPut
  SETD.2 ImgProgLen
  CALL numAdd

layOutYes:
  RSTA
  RSTB
  CCF
  ADD
  RET

layOutNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

checkImageRoom:
  SETD.0 ImgRoom
  SETD.2 ImgTotal
  CALL numCompare
  BRC imageTooBig
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

; ---- The vectors the file carries ----
;
; Last in the file, after the code and the data, so that everything before them sits where
; a loader that knows nothing about vectors already expects to find it.
;
; Four bytes each: WHERE THE SLOT IS, then what goes in it. Saying the slot outright rather
; than the vector number means the loader does no arithmetic and does not have to know
; where either vector table begins, and one entry can name a software or a hardware vector
; without saying which it is.
writeVectors:
  SETD.0 VecInstalled
  CALL numZero
  SETD.0 EntryAddress
  SETD.2 ProgBase
  CALL numSet

  ; Counted first, because a boot image writes the length of the run before the run.
  CALL countVectors
  SETD.0 ImgWalk
  SETD.2 DataPut
  CALL numSet

  SETD.0 VecInstalled
  LDA.0
  INCD.0
  LDB.0
  OR
  BRQ writeVectorsNone

  SETD.0 Loadable
  LDA.0
  BNA writeVectorsRoom

  ; A boot image marks the run and says how long it is, the way it does for its segments.
  SETD.0 MagicVEC
  INIA 0d3
  CALL putBytes
  SETD.0 VecBytes
  CALL putWord

writeVectorsRoom:
  SETD.0 VecWhich
  CALL numZero
writeVectorLoop:
  SETD.0 VecWhich
  SETD.2 VecCount
  CALL numCompare
  BNC writeVectorsDone
  CALL vecSlotAt
  CALL vecReadFields
  SETD.0 VecHasHandler
  LDA.0
  BRA writeVectorNext
  CALL vectorIsEntry
  BRQ writeVectorNext       ; Boot in a loadable program is the entry, not a handler.

  ; Where the slot is: the table it belongs to, plus two bytes for every vector before it.
  SETD.0 SlotAt
  SETD.2 SoftwareBase
  CALL numSet
  SETD.0 VecBase
  LDA.0
  BRA writeVectorSlot
  SETD.0 SlotAt
  SETD.2 HardwareBase
  CALL numSet
writeVectorSlot:
  SETD.0 VecNumber
  LDA.0
  SETD.0 SlotAt
  CALL numAddByte
  SETD.0 VecNumber
  LDA.0
  SETD.0 SlotAt
  CALL numAddByte
  SETD.0 SlotAt
  CALL putWord
  SETD.0 VecHandler
  CALL putWord

writeVectorNext:
  SETD.0 VecWhich
  CALL numStep
  BRI writeVectorLoop

writeVectorsDone:
  SETD.0 ImgTotal
  SETD.2 VecBytes
  CALL numAdd
  SETD.0 Loadable
  LDA.0
  BNA writeVectorsHeader
  INIA 0d5
  SETD.0 ImgTotal
  CALL numAddByte           ; The marker and the length in front of them.

writeVectorsHeader:
  ; A file that brings vectors needs something of its loader a version one loader does not
  ; know how to give, so it says version two and an older one refuses it rather than
  ; running the program without its handlers.
  SETD.0 Loadable
  LDA.0
  BRA writeVectorsNone
  SETD.0 ImgWalk
  SETD.2 ScratchImage
  CALL numSet
  SETD.0 ImgWalk
  INIA 0d4
  CALL numAddByte
  INIA 0d2
  CALL putByte
  SETD.0 VecInstalled
  INCD.0
  LDA.0
  CALL putByte

writeVectorsNone:
  ; And where to start, which a Boot line fills in and everything else leaves as the first
  ; byte of the code.
  SETD.0 Loadable
  LDA.0
  BRA writeVectorsOut
  SETD.0 ImgWalk
  SETD.2 ScratchImage
  CALL numSet
  SETD.0 ImgWalk
  INIA 0d8
  CALL numAddByte
  SETD.0 EntryAddress
  CALL putWord

writeVectorsOut:
  RET

; How many vectors will be written, into VecInstalled, and how many bytes that is.
countVectors:
  SETD.0 VecWhich
  CALL numZero
countVectorLoop:
  SETD.0 VecWhich
  SETD.2 VecCount
  CALL numCompare
  BNC countVectorsDone
  CALL vecSlotAt
  CALL vecReadFields
  SETD.0 VecHasHandler
  LDA.0
  BRA countVectorNext
  CALL vectorIsEntry
  BRQ countVectorTakeEntry
  SETD.0 VecInstalled
  CALL numStep
  BRI countVectorNext
countVectorTakeEntry:
  SETD.0 EntryAddress
  SETD.2 VecHandler
  CALL numSet
countVectorNext:
  SETD.0 VecWhich
  CALL numStep
  BRI countVectorLoop

countVectorsDone:
  SETD.0 VecBytes
  SETD.2 VecInstalled
  CALL numSet
  SETD.0 VecBytes
  SETD.2 VecBytes
  CALL numAdd
  SETD.0 VecBytes
  SETD.2 VecBytes
  CALL numAdd               ; Four bytes an entry.
  RET

; Q is zero if this entry is the Boot line of a LOADABLE program, which fills the entry
; field instead of being installed. Vector zero is where the whole machine starts, and a
; program being loaded into a running system has no business saying anything about that.
; A boot image is the one thing that does, so there it is installed like any other.
vectorIsEntry:
  SETD.0 Loadable
  LDA.0
  BRA vectorNotEntry
  SETD.0 VecBase
  LDA.0
  BNA vectorNotEntry
  SETD.0 VecNumber
  LDA.0
  BNA vectorNotEntry
  RSTA
  RSTB
  CCF
  ADD
  RET
vectorNotEntry:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

writeImage:
  SETD.0 OutName
  SETD.1 ScratchImage
  LDD.1.1
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
  SETD.0 Loadable
  LDA.0
  BNA deriveLoadable
  SETD.0 ExtensionBin
  BRI deriveCopy
deriveLoadable:
  SETD.0 ExtensionSbx
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
  SETD.0 ImgProgLen
  LDA.0
  INCD.0
  LDB.0
  SWI osPrintNumber
  SETD.0 DataText
  SWI osPrintString
  SETD.0 ImgDataLen
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
AfterSwi:
  0x00
Emitting:
  0x00
ProgAt:
  0x00 0x00
DataAt:
  0x00 0x00
ProgBase:
  0x00 0x00
DataBase:
  0x00 0x00
ProgBased:
  0x00
Loadable:
  0x00
DataBased:
  0x00
ProgUsed:
  0x00
DataUsed:
  0x00
ImgProgLen:
  0x00 0x00
ImgDataLen:
  0x00 0x00
RunLength:
  0x00 0x00
RunAt:
  0x00 0x00
AlignLeft:
  0x00 0x00
OneWord:
  0x00 0x01
VecLineWas:
  0x00 0x00
VecPinned:
  0x00
VecPinnedGiven:
  0x00
VecHandlerHere:
  0x00
VecIsDevice:
  0x00
VecInstalled:
  0x00 0x00
VecBytes:
  0x00 0x00
EntryAddress:
  0x00 0x00
SlotAt:
  0x00 0x00
SoftwareBase:
  0xFC 0x00
HardwareBase:
  0xFE 0x00
ReservedLeft:
  0x00
ReservedWalk:
  0x00 0x00
ReservedCount:
  0d5
VecHandlerName:
  #Reserve 0d23

; A name nothing can type, so that devices - which have no names of their own - can live in
; a table that refuses a repeated one. A space, then a counter.
DeviceName:
  0x20 0x01 0x00
  #Reserve 0d20

; The vectors that already mean something. Sixteen bytes each: fifteen of name, then the
; number the machine fixed for it.
ReservedNames:
"Boot"
  #Reserve 0d10
  0d0
"SoftReset"
  #Reserve 0d5
  0d1
"BadOpcode"
  #Reserve 0d5
  0d2
"GuardViolation"
  0d3
"BankFault"
  #Reserve 0d5
  0d4

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
; because a file is written in one call and there is nowhere to put half of one. CosmOS
; itself comes to 9,564 bytes.
ImgRoom:
  0x34 0x00

MagicSPBT:
"SPBT"
MagicSBEX:
"SBEX"
MagicPRG:
"PRG"
MagicDAT:
"DAT"
MagicVEC:
"VEC"
ExtensionBin:
".bin"
ExtensionSbx:
".sbx"

WordProgram:
"#Program"
WordData:
"#Data"
WordVectors:
"#Vectors"
WordBase:
"#Base"
WordInclude:
"#Include"
WordReserve:
"#Reserve"
WordAlign:
"#Align"
WordDevice:
"Device"

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
BaseNowhereText:
"#Base outside a segment, so there is nothing for it to be the base of"
BaseLateText:
"#Base after something is already in the segment, and a base has to come first"
IncludeBareText:
"#Include with no file name after it
"
ReserveNowhereText:
"#Reserve outside a segment, so there is nothing there for it to move along"
AlignNowhereText:
"#Align outside a segment, so there is nothing there for it to move along"
AlignZeroText:
"#Align to a multiple of nothing"
NumberBareText:
"a directive with no number after it
"
NumberBadText:
"a directive wants a number here, written 0x.. or 0d.."
UnknownVectorText:
"no vector of that name is declared anywhere in this program"
FixedNumberText:
"that vector's number is fixed by the machine and is not anybody's to give"
BadNumberText:
"that is not a vector number that can be given: below 16 belongs to the machine, and 64
and up is handed out by the assembler"
VecTwiceText:
"that vector is declared more than once"
DisagreeNumberText:
"that vector was already given a different number, so the two sides disagree about which
vector this name means"
DeviceBareText:
"Device has to say which port, as a number, and then where to go"
NoHandlerText:
"there is no label of that name for the handler to be"
LostVectorText:
"a vector went missing between the two passes"
TooMuchText:
"there is more on that line than a vector entry can be"
VectorOddText:
"only names belong in the Vector Segment"
DisagreeText:
"the two passes disagree about how long this program is
"
BasesText:
"one segment says where it goes and the other does not. The one that says nothing lands
at zero, on top of whatever is there. Give both a #Base, or neither.
"
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


#Include scratch.asm
#Include numbers.asm
#Include source.asm
#Include token.asm
#Include classify.asm
#Include labels.asm
#Include vectors.asm
#Include table.asm
