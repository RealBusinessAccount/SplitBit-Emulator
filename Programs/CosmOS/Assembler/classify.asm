; What a token is.
;
; THE ORDER OF THESE TESTS IS THE LANGUAGE, and it is copied deliberately from the C
; assembler rather than reinvented, because the two have to produce the same bytes from
; the same source. A token is a keyword, then an instruction, then a literal value, then a
; string, then a label - and what a thing means depends on which of those it reaches first.
;
;   ClsType   0 keyword   1 instruction   2 value   3 string
;             4 label definition          5 label reference
;
; A STRING IS NEVER ANYTHING ELSE. The quotes are gone by the time a token is looked at, so
; without that guard a string whose text reads "ADD" assembles as an instruction and one
; that begins with a zero is rejected as a malformed literal. Both have happened; the C
; assembler carries the same guard in two places and this carries it in four, because the
; keyword test needs it too and over there it does not have it.
;
; Written by Anachronaut

#Program

; Works out what TokText is. Q is zero if it is something the assembler understands.
clsToken:
  RSTA
  SETD.0 ClsLength
  STA.0

  SETD.0 TokString
  LDA.0
  BNA clsIsString

  ; ---- A keyword ----
  SETD.0 TokText
  LDA.0
  INIB 0x23                 ; '#'
  XOR
  BNQ clsTryInstruction
  INIA 0d0
  SETD.0 ClsType
  STA.0
  BRI clsYes

clsTryInstruction:
  CALL clsInstruction
  BNQ clsTryValue
  INIA 0d1
  SETD.0 ClsType
  STA.0
  BRI clsYes

clsTryValue:
  ; A leading zero means a literal was meant, so anything malformed after it is an error
  ; rather than a label. Falling through to the label test would quietly emit two bytes
  ; where one was wanted and shift everything after it.
  SETD.0 TokText
  LDA.0
  INIB 0x30                 ; '0'
  XOR
  BNQ clsTryLabel
  CALL clsValue
  BNQ clsNo
  INIA 0d2
  SETD.0 ClsType
  STA.0
  INIA 0d1
  SETD.0 ClsLength
  STA.0
  BRI clsYes

clsIsString:
  INIA 0d3
  SETD.0 ClsType
  STA.0
  ; A string is its characters and the zero byte after them, which is why two strings
  ; written in a row are two strings rather than one long one.
  SETD.0 TokLength
  LDA.0
  INCA
  SETD.0 ClsLength
  STA.0
  BRI clsYes

clsTryLabel:
  ; A colon on the end makes it a definition. Everything else is a use of a name, which
  ; is two bytes of address wherever it appears.
  CALL clsLastCharacter
  SETD.0 ClsByte
  LDA.0
  INIB 0x3A                 ; ':'
  XOR
  BNQ clsUse
  INIA 0d4
  SETD.0 ClsType
  STA.0
  BRI clsYes

clsUse:
  INIA 0d5
  SETD.0 ClsType
  STA.0
  INIA 0d2
  SETD.0 ClsLength
  STA.0

clsYes:
  RSTA
  RSTB
  CCF
  ADD
  RET

clsNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; The last character of the token, into ClsByte. Zero if the token is empty.
;
; INTO MEMORY, not into A, and that is not a style choice: a CALL saves and restores A, B
; and Data Pointers 0 to 2, so a routine that leaves its answer in one of those has the
; answer undone by its own return. Only Q, DP3 and memory survive.
clsLastCharacter:
  SETD.0 TokLength
  LDA.0
  BRA clsLastNone
  SETD.0 TokText
  SETD.1 ClsWalk
  STD.0.1
  SETD.0 TokLength
  LDA.0
  DECA
  SETD.0 ClsWalk
  CALL numAddByte
  SETD.1 ClsWalk
  LDD.0.1
  LDA.0
  SETD.0 ClsByte
  STA.0
  RET
clsLastNone:
  RSTA
  SETD.0 ClsByte
  STA.0
  RET

; ---- Instructions ----

; Is TokText an instruction? Q is zero if it is, and then ClsOpcode, ClsShape, ClsLength
; and ClsSelectorValue describe it.
;
; The name is folded to upper case and the selectors are split off before anything is
; looked up, because SETD.2 is the instruction SETD naming Data Pointer 2 rather than a
; name of its own.
clsInstruction:
  CALL clsSplitName
  BNQ clsInstructionNo      ; Longer than any mnemonic, so it is not one.
  CALL clsFindName
  BNQ clsInstructionNo

  ; How many selectors this shape wants. They are emitted whether or not they were
  ; written, so the length is fixed by the instruction and leaving one off means zero.
  SETD.0 ClsShape
  LDA.0
  SETD.0 AsmShapeSelectors
  CALL clsIndexByte
  SETD.0 ClsByte
  LDA.0
  SETD.0 ClsWanted
  STA.0

  ; More selectors than the instruction has pointers to name is a mistake worth catching:
  ; it means the programmer thinks it does something it does not.
  SETD.0 ClsGiven
  LDA.0
  SETD.2 ClsWanted
  LDB.2
  CCF
  SUB
  BRQ clsSelectorsFit
  BRC clsSelectorsFit       ; Fewer than wanted is allowed and means zero.
  SETD.0 TooManySelectors
  CALL clsComplain
  BRI clsInstructionNo

clsSelectorsFit:
  SETD.0 ClsWanted
  LDA.0
  INCA
  SETD.0 ClsLength
  STA.0                     ; The opcode and its selectors. The operand is its own token.
  RSTA
  RSTB
  CCF
  ADD
  RET

clsInstructionNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Splits TokText into an upper case mnemonic in ClsName, padded to four with spaces, and
; up to two selector digits in ClsSelectorValue. Q is zero if the name could be a mnemonic
; at all, which means four characters or fewer.
clsSplitName:
  INIA 0x20
  SETD.0 ClsName
  STA.0
  INCD.0
  STA.0
  INCD.0
  STA.0
  INCD.0
  STA.0
  INCD.0
  RSTA
  STA.0                     ; Four spaces and a zero, so a short name still compares.

  RSTA
  SETD.0 ClsGiven
  STA.0
  SETD.0 ClsSelectorValue
  STA.0
  INCD.0
  STA.0

  SETD.0 ClsNameLength
  RSTA
  STA.0

  SETD.0 TokText
  SETD.1 ClsWalk
  STD.0.1

clsNameLoop:
  SETD.1 ClsWalk
  LDD.0.1
  LDA.0
  BRA clsSplitDone
  INIB 0x2E                 ; '.'
  XOR
  BRQ clsSelectorPart

  SETD.0 ClsNameLength
  LDA.0
  INIB 0d4
  CCF
  SUB
  BNC clsSplitTooLong       ; A fifth character, so this is not a mnemonic.

  SETD.1 ClsWalk
  LDD.0.1
  LDA.0
  CALL clsUpper
  SETD.0 ClsByte
  LDA.0
  SETD.0 ClsName
  SETD.2 ClsNameLength
  CALL clsPutIndexed
  SETD.0 ClsNameLength
  LDA.0
  INCA
  STA.0

clsNameStep:
  SETD.0 ClsWalk
  CALL numStep
  BRI clsNameLoop

clsSelectorPart:
  ; The character after the dot is which Data Pointer, in decimal.
  SETD.0 ClsWalk
  CALL numStep
  SETD.1 ClsWalk
  LDD.0.1
  LDA.0
  BRA clsSplitDone
  INIB 0x30
  CCF
  SUB
  MVQA                      ; The digit as a number.
  SETD.0 ClsDigitHold
  STA.0

  ; There are four Data Pointers, so anything above three does not name one.
  INIB 0d4
  CCF
  SUB
  BNC clsSelectorRange

  SETD.0 ClsGiven
  LDA.0
  INIB 0d2
  CCF
  SUB
  BNC clsSelectorSpare      ; Already two, so anything more is counted and discarded;
                            ; the count is what the caller complains about.
  SETD.0 ClsDigitHold
  LDA.0
  SETD.0 ClsSelectorValue
  SETD.2 ClsGiven
  CALL clsPutIndexed
clsSelectorSpare:
  SETD.0 ClsGiven
  LDA.0
  INCA
  STA.0
  BRI clsNameStep

clsSplitDone:
  SETD.0 ClsNameLength
  LDA.0
  BRA clsSplitTooLong       ; Nothing before the dot is not a mnemonic either.
  RSTA
  RSTB
  CCF
  ADD
  RET

clsSelectorRange:
  SETD.0 BadSelector
  CALL clsComplain
clsSplitTooLong:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Looks ClsName up in the instruction table. Q is zero if it is there, and then ClsOpcode
; and ClsShape say what it is.
clsFindName:
  SETD.0 AsmInstructions
  SETD.1 ClsEntry
  STD.0.1
  SETD.0 AsmInstructionCount
  LDA.0
  SETD.0 ClsLeft
  STA.0

clsFindLoop:
  SETD.1 ClsEntry
  LDD.0.1
  INCD.0
  INCD.0                    ; Past the opcode and the shape, to the name.
  SETD.1 ClsName
  CALL clsSameName
  BRQ clsFindGot

  ; Seven bytes to an entry: an opcode, a shape, and four characters with a zero.
  INIA 0d7
  SETD.0 ClsEntry
  CALL numAddByte
  SETD.0 ClsLeft
  LDA.0
  DECA
  STA.0
  BNA clsFindLoop

  RSTA
  INIB 0d1
  CCF
  ADD
  RET

clsFindGot:
  SETD.1 ClsEntry
  LDD.0.1
  LDA.0
  SETD.1 ClsOpcode
  STA.1
  SETD.1 ClsEntry
  LDD.0.1
  INCD.0
  LDA.0
  SETD.1 ClsShape
  STA.1
  RSTA
  RSTB
  CCF
  ADD
  RET

; Four characters at DP0 against four at DP1. Q is zero if they are the same.
clsSameName:
  INIA 0d4
  SETD.2 ClsLeft2
  STA.2
clsSameLoop:
  LDA.0
  LDB.1
  XOR
  BNQ clsSameDone
  INCD.0
  INCD.1
  SETD.2 ClsLeft2
  LDA.2
  DECA
  STA.2
  BNA clsSameLoop
clsSameDone:
  RET

; ---- Literal values ----

; Is TokText a well formed literal? Q is zero if it is, and ClsValue is what it comes to.
; Anything beginning with a zero has to be one, so a failure here is an error rather than
; an invitation to try the next test.
clsValue:
  SETD.0 TokText
  INCD.0
  LDA.0
  INIB 0x78                 ; 'x'
  XOR
  BRQ clsValueHex
  SETD.0 TokText
  INCD.0
  LDA.0
  INIB 0x64                 ; 'd'
  XOR
  BRQ clsValueDecimal

  SETD.0 BadPrefix
  CALL clsComplain
  BRI clsValueNo

clsValueHex:
  INIA 0d16
  SETD.0 ClsBase
  STA.0
  BRI clsValueDigits

clsValueDecimal:
  INIA 0d10
  SETD.0 ClsBase
  STA.0

clsValueDigits:
  SETD.0 TokLength
  LDA.0
  INIB 0d3
  CCF
  SUB
  BRC clsValueEmpty         ; Only the prefix, so there are no digits at all.

  RSTA
  SETD.0 ClsValue
  STA.0
  SETD.0 TokText
  INCD.0
  INCD.0
  SETD.1 ClsWalk
  STD.0.1

clsValueLoop:
  SETD.1 ClsWalk
  LDD.0.1
  LDA.0
  BRA clsValueGood
  CALL clsDigit
  BNQ clsValueBadDigit

  ; value = value * base + digit, and anything that will not fit in a byte is refused
  ; rather than wrapped, because a literal is one byte wherever it goes.
  SETD.0 ClsDigitValue
  LDA.0
  SETD.2 ClsValue
  LDB.2
  PSHA
  SETD.0 ClsBase
  LDA.0
  CALL clsMultiply
  BNQ clsValueTooBig
  POPA
  SETD.0 ClsProduct
  LDB.0
  CCF
  ADD
  BRC clsValueTooBig
  MVQA
  SETD.0 ClsValue
  STA.0

  SETD.0 ClsWalk
  CALL numStep
  BRI clsValueLoop

clsValueGood:
  RSTA
  RSTB
  CCF
  ADD
  RET

clsValueEmpty:
  SETD.0 NoDigits
  CALL clsComplain
  BRI clsValueNo
clsValueBadDigit:
  SETD.0 BadDigit
  CALL clsComplain
  BRI clsValueNo
clsValueTooBig:
  POPA
  SETD.0 TooBig
  CALL clsComplain

clsValueNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; The character in A as a digit in ClsBase, into ClsDigitValue. Q is zero if it is one.
clsDigit:
  SETD.0 ClsHold
  STA.0

  ; 0 to 9
  INIB 0x30
  CCF
  SUB
  BRC clsDigitNo
  SETD.0 ClsHold
  LDA.0
  INIB 0x3A
  CCF
  SUB
  BRC clsDigitDecimal

  ; A to F, either case, and only when the base has room for them.
  SETD.0 ClsBase
  LDA.0
  INIB 0d16
  XOR
  BNQ clsDigitNo

  SETD.0 ClsHold
  LDA.0
  CALL clsUpper
  SETD.0 ClsByte
  LDA.0
  SETD.0 ClsHold
  STA.0
  INIB 0x41
  CCF
  SUB
  BRC clsDigitNo
  SETD.0 ClsHold
  LDA.0
  INIB 0x47
  CCF
  SUB
  BNC clsDigitNo

  SETD.0 ClsHold
  LDA.0
  INIB 0x37                 ; 'A' is ten, so the offset is 0x41 less 10.
  CCF
  SUB
  MVQA
  SETD.0 ClsDigitValue
  STA.0
  BRI clsDigitYes

clsDigitDecimal:
  SETD.0 ClsHold
  LDA.0
  INIB 0x30
  CCF
  SUB
  MVQA
  SETD.0 ClsDigitValue
  STA.0
  ; A decimal digit is a hexadecimal one too, so this needs no test of the base.

clsDigitYes:
  RSTA
  RSTB
  CCF
  ADD
  RET

clsDigitNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; B times A into ClsProduct. Q is not zero if it would not fit in a byte, which is the
; only answer a literal can use: there is no wider literal to promote it to.
clsMultiply:
  SETD.0 ClsMulLeft
  STA.0
  RSTA
  SETD.0 ClsProduct
  STA.0
clsMultiplyLoop:
  SETD.0 ClsMulLeft
  LDA.0
  BRA clsMultiplyDone
  DECA
  STA.0
  SETD.0 ClsProduct
  LDA.0
  CCF
  ADD
  BRC clsMultiplyOver
  MVQA
  SETD.0 ClsProduct
  STA.0
  BRI clsMultiplyLoop
clsMultiplyDone:
  RSTA
  RSTB
  CCF
  ADD
  RET
clsMultiplyOver:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; ---- Odds and ends ----

; The character in A, folded to upper case, into ClsByte.
clsUpper:
  SETD.0 ClsHold
  STA.0
  INIB 0x61                 ; 'a'
  CCF
  SUB
  BRC clsUpperDone
  SETD.0 ClsHold
  LDA.0
  INIB 0x7B                 ; One past 'z'.
  CCF
  SUB
  BNC clsUpperDone
  SETD.0 ClsHold
  LDA.0
  INIB 0d32
  CCF
  SUB
  MVQA
  SETD.0 ClsByte
  STA.0
  RET
clsUpperDone:
  SETD.0 ClsHold
  LDA.0
  SETD.0 ClsByte
  STA.0
  RET

; The byte at DP0, offset by A, into ClsByte.
clsIndexByte:
  PSHA
  PSHD.0
  POPB
  POPA                      ; The low byte is on top, the way a pointer is pushed.
  SETD.0 ClsWalk
  STA.0
  INCD.0
  STB.0
  POPA
  SETD.0 ClsWalk
  CALL numAddByte
  SETD.1 ClsWalk
  LDD.0.1
  LDA.0
  SETD.0 ClsByte
  STA.0
  RET

; Puts A at DP0 offset by the byte at DP2.
clsPutIndexed:
  PSHA
  PSHD.0
  POPB
  POPA
  SETD.0 ClsPut
  STA.0
  INCD.0
  STB.0
  LDA.2
  SETD.0 ClsPut
  CALL numAddByte
  SETD.1 ClsPut
  LDD.0.1
  POPA
  STA.0
  RET

; Says what is wrong, with the file and the line, the way an error ought to.
clsComplain:
  SWI osPrintString
  SETD.0 InFileText
  SWI osPrintString
  SETD.0 SrcName
  SWI osPrintString
  SETD.0 AtLineText
  SWI osPrintString
  SETD.0 TokLine
  LDA.0
  INCD.0
  LDB.0
  SWI osPrintNumber
  SETD.0 SaidText
  SWI osPrintString
  SETD.0 TokText
  SWI osPrintString
  SETD.0 SaidEnd
  SWI osPrintString
  RET

#Data

ClsType:
  0x00
ClsLength:
  0x00
ClsOpcode:
  0x00
ClsShape:
  0x00
ClsSelectorValue:
  0x00 0x00
ClsGiven:
  0x00
ClsWanted:
  0x00
ClsNameLength:
  0x00
ClsName:
  #Reserve 0d5
ClsValue:
  0x00
ClsBase:
  0x00
ClsDigitValue:
  0x00
ClsProduct:
  0x00
ClsMulLeft:
  0x00
ClsHold:
  0x00
ClsDigitHold:
  0x00
ClsByte:
  0x00
ClsLeft:
  0x00
ClsLeft2:
  0x00
ClsWalk:
  0x00 0x00
ClsEntry:
  0x00 0x00
ClsPut:
  0x00 0x00

InFileText:
" in "
AtLineText:
" at line "
SaidText:
"
  it said: "
SaidEnd:
"
"
BadPrefix:
"a literal needs 0x for hexadecimal or 0d for decimal"
NoDigits:
"a literal with no digits after its prefix"
BadDigit:
"that is not a digit in the base the prefix asked for"
TooBig:
"a literal too large to fit in one byte"
TooManySelectors:
"more Data Pointer selectors than that instruction has pointers to name"
BadSelector:
"that does not name a Data Pointer, which run from 0 to 3"
