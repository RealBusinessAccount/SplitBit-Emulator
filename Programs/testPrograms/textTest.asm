; Exercises text.asm, which is how CosmOS understands what was typed at it.
;
; The cases here are the ones that decide whether a shell feels right or feels broken.
; textSame has to say that "dir" and "dirty" are different words, or every command would
; match its own prefix. textSplit has to give an empty rest rather than a missing one when
; there is no argument, so that "load" with nothing after it is a question the shell can
; answer. And textHexWord has to take upper and lower case alike, refuse things that only
; look like numbers, and push digits off the top rather than refusing a fifth one.
;
; Correct output is:
;   split: [dump] [program 2000]
;   split: [dir] []
;   same: yes no no no
;   hex: 2000 00FF 00FF BEEF FFFF 0000
;   0 is a fine way to begin a string
;   no number here

#Include console.asm
#Include text.asm

#Program

start:
  ; ---- Splitting ----
  SETD.0 LineOne
  CALL textSplit
  SETD.0 SplitLabel
  CALL printString
  INIA 0x5B
  OUTA 0x00
  SETD.0 LineOne
  CALL printString
  INIA 0x5D
  OUTA 0x00
  CALL blank
  INIA 0x5B
  OUTA 0x00
  SETD.1 TextRest
  LDD.0.1
  CALL printString
  INIA 0x5D
  OUTA 0x00
  CALL newLine

  ; One word on its own. The rest has to be empty rather than absent.
  SETD.0 LineTwo
  CALL textSplit
  SETD.0 SplitLabel
  CALL printString
  INIA 0x5B
  OUTA 0x00
  SETD.0 LineTwo
  CALL printString
  INIA 0x5D
  OUTA 0x00
  CALL blank
  INIA 0x5B
  OUTA 0x00
  SETD.1 TextRest
  LDD.0.1
  CALL printString
  INIA 0x5D
  OUTA 0x00
  CALL newLine

  ; ---- Comparing ----
  ; The same, then longer, then shorter, then different. The middle two are what a
  ; comparison that stopped at the first ending would get wrong.
  SETD.0 SameLabel
  CALL printString
  SETD.0 WordDir
  SETD.1 WordDir2
  CALL textSame
  CALL sayQ
  SETD.0 WordDir
  SETD.1 WordDirty
  CALL textSame
  CALL sayQ
  SETD.0 WordDirty
  SETD.1 WordDir2
  CALL textSame
  CALL sayQ
  SETD.0 WordDir
  SETD.1 WordRun
  CALL textSame
  CALL sayQ
  CALL newLine

  ; ---- Reading numbers ----
  SETD.0 HexLabel
  CALL printString
  SETD.0 HexPlain
  CALL showHex
  SETD.0 HexUpper
  CALL showHex
  SETD.0 HexLower
  CALL showHex
  SETD.0 HexMixed
  CALL showHex
  SETD.0 HexTooMany
  CALL showHex
  SETD.0 HexStops
  CALL showHex
  CALL newLine

  ; A string may begin with anything, including a zero. The assembler strips the quotes
  ; before it decides what a token is, so a string starting with a zero looked exactly
  ; like a malformed literal and was rejected as one. This line is here so that it cannot
  ; go back to being rejected quietly.
  SETD.0 ZeroString
  CALL printString
  CALL newLine

  ; Something that is not a number at all has to be refused rather than read as zero.
  SETD.0 HexNone
  CALL textHexWord
  BRQ hexUnexpected
  SETD.0 NoNumber
  CALL printString
  CALL newLine
  HALT
hexUnexpected:
  SETD.0 Unexpected
  CALL printString
  CALL newLine
  HALT

; DP0 names text. Reads a number from it and prints what came out.
showHex:
  CALL textHexWord
  SETD.0 TextValue
  CALL printWordHex
  CALL blank
  RET

; Prints yes if Q is zero and no if it is not. Q survives a RET, which is what lets the
; answer get this far.
sayQ:
  BNQ sayNo
  SETD.0 YesText
  CALL printString
  RET
sayNo:
  SETD.0 NoText
  CALL printString
  RET

blank:
  INIA 0x20
  OUTA 0x00
  RET

#Data

SplitLabel:
"split: "
SameLabel:
"same: "
HexLabel:
"hex: "
YesText:
"yes "
NoText:
"no "
NoNumber:
"no number here"
ZeroString:
"0 is a fine way to begin a string"
Unexpected:
"a number was found where there is none"

; textSplit writes over the space it cuts at, so these are written out rather than shared.
LineOne:
"dump program 2000"
LineTwo:
"dir"

WordDir:
"dir"
WordDir2:
"dir"
WordDirty:
"dirty"
WordRun:
"run"

HexPlain:
"2000"
HexUpper:
"FF"
HexLower:
"ff"
HexMixed:
"bEeF"
HexTooMany:
"12FFFF"
HexStops:
"0 and more"
HexNone:
"zebra"

#Vectors

  Boot  start
