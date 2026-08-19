; Edit, a line editor for CosmOS.
;
; The first program on this machine that makes a file a person typed. Everything on every
; disk before this one was put there by the host tool.
;
; It is line oriented, in the manner of ed, and that is a deliberate choice rather than a
; limitation of the machine - Snake already draws a whole screen and steers with single
; keys. A full screen editor wants scrolling, a redraw model and cursor arithmetic, none of
; which teaches anything about files, and files are what this exists to exercise. So it
; stays in line mode and reads whole lines, which is what the console does without being
; asked for anything.
;
;   l          list the whole thing, numbered
;   a          add lines at the end, until a line that is just a dot
;   i <n>      put lines in before line n, the same way
;   c <n>      change line n
;   d <n>      delete line n
;   w          write it back
;   q          stop without writing
;
; ---- How the text is kept ----
;
; A LINKED LIST OF LINES, not one buffer with newlines in it. Each line is a node holding
; where the next one is, how long it is, and its bytes:
;
;   0  2  where the next line is, or zero
;   2  1  how many bytes this line has
;   3     the bytes
;
; Inserting is then two pointers changed and nothing moved, and so is deleting. With one
; flat buffer both of them would mean shifting everything after the edit, which on a
; machine with no memcpy is a loop over every byte of the rest of the document, run for
; every keystroke's worth of editing.
;
; The price is that DELETED LINES ARE NOT REUSED. A new line always goes at the end of the
; arena, and an unlinked one just sits there. A session that edits heavily uses more room
; than the document needs, and writing the file out and reading it back is what tidies it
; up. That is an honest trade for a program this size, and it is written down here rather
; than left as a surprise.
;
; Two regions are used by arrangement rather than reserved, because reserving them would
; put tens of kilobytes of zeroes into the file for no reason:
;
;   0x4000   the file, on its way in or out
;   0x8000   the arena the lines live in
;
; Nothing is running but this, so both are ours. It is the same arrangement CosmOS makes
; with 0x8000 while it is loading something, for the same reason.

#Include services.asm

#Program

  #Base 0x2000

start:
  SETD.0 FileName
  INIB 0d23
  SWI osArgument
  SETD.0 FileName
  LDA.0
  BRA noName

  ; Everything is set here rather than trusted to be zero, since running a program a second
  ; time does not load it again.
  RSTA
  SETD.0 TextHead
  STA.0
  INCD.0
  STA.0
  SETD.0 ArenaFree
  INIA 0x80
  STA.0
  INCD.0
  RSTA
  STA.0

  CALL loadFile

  SETD.0 FileName
  SWI osPrintString
  SETD.0 CommaText
  SWI osPrintString
  CALL countLines
  MVQA
  CALL printByte
  ; One line is not one lines. The same care the shell's file listing takes, for the same
  ; reason: it costs four instructions and reads as carelessness without them.
  DECA
  BRA oneLine
  SETD.0 LinesText
  BRI sayLines
oneLine:
  SETD.0 LineText
sayLines:
  SWI osPrintString
  CALL newLine

commandLoop:
  SETD.0 PromptText
  SWI osPrintString
  SETD.0 Command
  INIB 0d40
  SWI osReadLine

  ; Running out of typing ends it, the same way it ends the shell.
  INA 0x01
  INIB 0x02                 ; ENDED
  AND
  BNQ quit

  SETD.0 Command
  LDA.0
  BRA commandLoop           ; An empty line asks for nothing.

  ; Whatever number follows the letter, if there is one. The spaces between the two are
  ; stepped over first: a number is what somebody typed after "d ", not after "d".
  SETD.0 Command
  INCD.0
commandSpaces:
  LDA.0
  INIB 0x20
  XOR
  BNQ commandArgument
  INCD.0
  BRI commandSpaces
commandArgument:
  CALL textNumber
  MVQA
  SETD.0 Wanted
  STA.0

  SETD.0 Command
  LDA.0

  INIB 0d108                ; l
  XOR
  BRQ doList
  INIB 0d97                 ; a
  XOR
  BRQ doAppend
  INIB 0d105                ; i
  XOR
  BRQ doInsert
  INIB 0d99                 ; c
  XOR
  BRQ doChange
  INIB 0d100                ; d
  XOR
  BRQ doDelete
  INIB 0d119                ; w
  XOR
  BRQ doWrite
  INIB 0d113                ; q
  XOR
  BRQ quit

  SETD.0 WhatText
  SWI osPrintString
  CALL newLine
  BRI commandLoop

quit:
  SWI osExit

noName:
  SETD.0 NoNameText
  SWI osPrintString
  CALL newLine
  SWI osExit


; ---- The commands ----

doList:
  CALL listLines
  BRI commandLoop

doAppend:
  CALL countLines
  MVQA
  INCA
  SETD.0 Wanted
  STA.0                     ; Adding at the end is inserting before the line after it.
  BRI insertLoop

doInsert:
  SETD.0 Wanted
  LDA.0
  BRA insertNeedsLine
insertLoop:
  SETD.0 EnteringText
  SWI osPrintString
  SETD.0 Entry
  INIB 0d80
  SWI osReadLine
  INA 0x01
  INIB 0x02                 ; ENDED
  AND
  BNQ commandLoop

  ; A line that is just a dot ends it, which is the oldest convention there is for this.
  SETD.0 Entry
  SETD.1 DotText
  CALL textSame
  BRQ commandLoop

  SETD.0 Entry
  CALL makeNode
  SETD.0 Wanted
  LDA.0
  CALL linkBefore
  SETD.0 Wanted
  LDA.0
  INCA
  STA.0                     ; The next one goes after the one just put in.
  BRI insertLoop

insertNeedsLine:
  SETD.0 NeedsLineText
  SWI osPrintString
  CALL newLine
  BRI commandLoop

doChange:
  SETD.0 Wanted
  LDA.0
  BRA insertNeedsLine
  CALL findLine
  BNQ noSuchLine

  SETD.0 EnteringText
  SWI osPrintString
  SETD.0 Entry
  INIB 0d80
  SWI osReadLine
  INA 0x01
  INIB 0x02                 ; ENDED
  AND
  BNQ commandLoop

  SETD.0 Entry
  CALL makeNode
  SETD.0 Wanted
  LDA.0
  CALL linkBefore           ; The new one goes in front of the old one,
  SETD.0 Wanted
  LDA.0
  INCA
  CALL unlinkLine           ; and the old one, now one further along, comes out.
  BRI commandLoop

doDelete:
  SETD.0 Wanted
  LDA.0
  BRA insertNeedsLine
  CALL unlinkLine
  BNQ noSuchLine
  BRI commandLoop

noSuchLine:
  SETD.0 NoLineText
  SWI osPrintString
  CALL newLine
  BRI commandLoop

doWrite:
  CALL writeFile
  BNQ writeFailed
  SETD.0 WrittenText
  SWI osPrintString
  SETD.0 WroteSize
  CALL printWord
  SETD.0 BytesText
  SWI osPrintString
  CALL newLine
  BRI commandLoop

writeFailed:
  SETD.0 NoWriteText
  SWI osPrintString
  CALL newLine
  BRI commandLoop

; ---- The list of lines ----

; DP0 is a string. Puts a node holding it at the end of the arena, and leaves DP3 on it.
makeNode:
  SETD.1 ArenaFree
  LDD.3.1

  PSHD.3
  POPD.1
  RSTA
  STA.1                     ; Nothing follows it yet.
  INCD.1
  STA.1
  INCD.1
  PSHD.1                    ; Where the length goes, once it is known.
  INCD.1
  RSTB

makeNodeLoop:
  LDA.0
  BRA makeNodeEnd
  STA.1
  INCD.0
  INCD.1
  INCB
  BRI makeNodeLoop

makeNodeEnd:
  POPD.0
  PSHB
  POPA
  STA.0                     ; How long it turned out to be.
  INIB 0d3
  CCF
  ADD
  MVQA
  SETD.0 ArenaFree
  CALL addByteToWord
  RET

; A is a line number. Leaves DP3 on that line and PrevLine on the one before it, which is
; zero when it is the first. Q is zero if there is such a line.
findLine:
  SETD.1 Wanted2
  STA.1
  INIA 0d1
  SETD.1 Counted
  STA.1
  RSTA
  SETD.1 PrevLine
  STA.1
  INCD.1
  STA.1
  SETD.1 TextHead
  LDD.3.1

findLineStep:
  PSHD.3
  POPA
  POPB
  OR
  BRQ findLineMissing

  SETD.1 Counted
  LDA.1
  SETD.1 Wanted2
  LDB.1
  XOR
  BRQ findLineFound

  PSHD.3
  SETD.1 PrevLine
  POPD.0
  STD.0.1
  PSHD.3
  POPD.0
  LDD.3.0                   ; On to whatever follows it.
  SETD.1 Counted
  LDA.1
  INCA
  STA.1
  BRI findLineStep

findLineFound:
  RSTA
  RSTB
  CCF
  ADD
  RET

findLineMissing:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; DP3 is a new node and A is the line number it should become. Puts it there.
linkBefore:
  PSHD.3
  SETD.1 NewLine
  POPD.0
  STD.0.1                   ; The new node, while the old ones are looked through.

  CALL findLine             ; Which may miss, and missing means putting it at the end.

  ; What the new node should point at is whatever was there, or nothing.
  SETD.1 NewLine
  LDD.0.1
  BNQ linkBeforeAtEnd
  PSHD.3
  POPD.1
  STD.1.0                   ; new.next = the line that was there
  BRI linkBeforeAttach

linkBeforeAtEnd:
  ; Nothing was there, so the new one ends the list and goes after whatever was last.
  RSTA
  STA.0
  INCD.0
  STA.0
  SETD.1 NewLine
  LDD.0.1

linkBeforeAttach:
  ; And whatever came before now points at the new one. Before the first line, that is
  ; the head of the list rather than a node.
  SETD.1 PrevLine
  LDD.2.1
  PSHD.2
  POPA
  POPB
  OR
  BRQ linkBeforeHead

  SETD.1 NewLine
  LDD.0.1
  SETD.1 PrevLine
  LDD.1.1
  STD.0.1
  RET

linkBeforeHead:
  SETD.1 NewLine
  LDD.0.1
  SETD.1 TextHead
  STD.0.1
  RET

; A is a line number. Takes it out of the list. Q is zero if there was such a line.
unlinkLine:
  CALL findLine
  BNQ unlinkMissing

  ; What follows the one being taken out.
  PSHD.3
  POPD.0
  LDD.0.0

  SETD.1 PrevLine
  LDD.2.1
  PSHD.2
  POPA
  POPB
  OR
  BRQ unlinkHead

  SETD.1 PrevLine
  LDD.1.1
  STD.0.1
  BRI unlinkDone

unlinkHead:
  SETD.1 TextHead
  STD.0.1

unlinkDone:
  RSTA
  RSTB
  CCF
  ADD
  RET

unlinkMissing:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Q is how many lines there are.
countLines:
  RSTA
  SETD.1 Counted
  STA.1
  SETD.1 TextHead
  LDD.3.1
countStep:
  PSHD.3
  POPA
  POPB
  OR
  BRQ countDone
  SETD.1 Counted
  LDA.1
  INCA
  STA.1
  PSHD.3
  POPD.0
  LDD.3.0
  BRI countStep
countDone:
  SETD.1 Counted
  LDA.1
  RSTB
  CCF
  ADD
  RET

listLines:
  INIA 0d1
  SETD.1 Counted
  STA.1
  SETD.1 TextHead
  LDD.3.1
listStep:
  PSHD.3
  POPA
  POPB
  OR
  BRQ listDone

  SETD.0 Counted
  LDA.0
  CALL printByte
  SETD.0 ColonText
  SWI osPrintString

  PSHD.3
  POPD.1
  DPUP.1 0d02
  LDA.1
  SETD.1 Leftover
  STA.1
  PSHD.3
  POPD.0
  DPUP.0 0d03
  SETD.1 Leftover
  LDA.1
  BRA listEmpty
listChars:
  LDA.0
  OUTA 0x00
  INCD.0
  SETD.1 Leftover
  LDA.1
  DECA
  STA.1
  BNA listChars
listEmpty:
  CALL newLine

  SETD.1 Counted
  LDA.1
  INCA
  STA.1
  PSHD.3
  POPD.0
  LDD.3.0
  BRI listStep
listDone:
  RET

; ---- The file ----

; Reads the file into lines, if there is one. A name that is not on the disk is a new
; document rather than a mistake, which is what makes this the way to start one.
loadFile:
  SETD.0 FileName
  SETD.1 0x40 0x00
  SWI osFileRead
  BNQ loadNothing

  ; How many bytes came back. The service says so in DP3, which is one of the two things a
  ; service is allowed to answer in, and a file that fits in memory has a length that fits
  ; in a pointer. A name that is not on the disk fails here, and that is a new document
  ; rather than a mistake.
  PSHD.3
  POPA                      ; The low byte is on top, the way a pointer is pushed.
  POPB
  SETD.1 ReadLeft
  STB.1
  INCD.1
  STA.1

  SETD.0 0x40 0x00
  SETD.1 Entry
  RSTA
  SETD.2 EntryLength
  STA.2

splitStep:
  ; Anything left?
  SETD.2 ReadLeft
  LDA.2
  INCD.2
  LDB.2
  OR
  BRQ splitLast

  ; How long the line is so far is kept in memory rather than in B, because comparing
  ; against a newline needs B and would quietly count the comparison instead of the line.
  LDA.0
  INIB 0d10
  XOR
  BRQ splitLine

  STA.1                     ; A is still the character; an ALU operation does not touch it.
  INCD.1
  SETD.2 EntryLength
  LDA.2
  INCA
  STA.2
  BRI splitOn

splitLine:
  RSTA
  STA.1                     ; The line ends here, so it becomes a string.
  PSHD.0                    ; How far through the file we are.
  SETD.0 Entry
  CALL makeNode
  CALL appendNode
  POPD.0
  SETD.1 Entry
  RSTA
  SETD.2 EntryLength
  STA.2

splitOn:
  INCD.0
  SETD.2 ReadLeft
  CALL takeOneOff
  BRI splitStep

splitLast:
  ; A file that does not end in a newline still has a last line in it.
  SETD.2 EntryLength
  LDA.2
  BRA loadNothing
  RSTA
  STA.1
  SETD.0 Entry
  CALL makeNode
  CALL appendNode
loadNothing:
  RET

; DP3 is a node. Puts it on the end of the list.
appendNode:
  ; The node has to be put somewhere safe first: counting the lines walks the list in DP3,
  ; which is where the node being added is being held.
  PSHD.3
  CALL countLines
  MVQA
  INCA
  POPD.3
  CALL linkBefore
  RET

; DP2 is a two byte count. Takes one off it.
takeOneOff:
  DPUP.2 0d01
  LDA.2
  DECA
  STA.2
  BNC takeOneDone           ; No borrow, so the high half is untouched.
  DPDN.2 0d01
  LDA.2
  DECA
  STA.2
  RET
takeOneDone:
  RET

; Builds the whole document at 0x4000 and saves it. Q is zero if it worked.
writeFile:
  SETD.1 0x40 0x00
  SETD.2 TextHead
  LDD.3.2

writeStep:
  PSHD.3
  POPA
  POPB
  OR
  BRQ writeOut

  PSHD.3
  POPD.0
  DPUP.0 0d02
  LDA.0
  SETD.2 Leftover
  STA.2
  INCD.0
  LDA.2
  BRA writeBreak
writeChars:
  LDA.0
  STA.1
  INCD.0
  INCD.1
  SETD.2 Leftover
  LDA.2
  DECA
  STA.2
  BNA writeChars
writeBreak:
  INIA 0d10
  STA.1
  INCD.1

  PSHD.3
  POPD.0
  LDD.3.0
  BRI writeStep

writeOut:
  ; Where the building stopped says how big it is, with no arithmetic worth the name: the
  ; buffer starts on a page boundary at 0x4000, so the high byte less 0x40 is the number of
  ; whole blocks and the low byte is the tail.
  SETD.2 WroteSize
  STD.1.2

  ; Turn where it stopped into how big it is, which is one subtraction: the high byte less
  ; 0x40 and the low byte as it stands.
  SETD.0 WroteSize
  LDA.0
  INIB 0x40
  CCF
  SUB
  MVQA
  SETD.0 WroteSize
  STA.0                     ; WroteSize is now a count of bytes, which is what gets printed.

  ; And into the two registers the service takes a size in.
  SETD.0 WroteSize
  LDA.0
  INCD.0
  LDB.0

  SETD.0 FileName
  SETD.1 0x40 0x00
  SWI osFileSave
  RET

; ---- All that is left of a console library ----
;
; Printing a string and reading a line are services now. These three are only here because
; what a service takes is not quite what the call sites have: a number arrives in two
; registers rather than one or in memory, and a line feed is a string like any other.

newLine:
  SETD.0 Break
  SWI osPrintString
  RET

; A is a byte.
printByte:
  PSHA
  POPB
  RSTA
  SWI osPrintNumber
  RET

; DP0 is a two byte number, most significant first.
printWord:
  LDA.0
  INCD.0
  LDB.0
  SWI osPrintNumber
  RET

; DP0 is a two byte number, A is a byte. Adds the one to the other.
addByteToWord:
  DPUP.0 0d01
  LDB.0
  CCF
  ADD
  STQ.0
  DPDN.0 0d01
  LDA.0
  RSTB
  ADD
  STQ.0
  RET

#Data

  #Base 0x1000

Break:
  0x0A 0x00
PromptText:
"> "
EnteringText:
": "
ColonText:
": "
CommaText:
", "
LinesText:
" lines"
LineText:
" line"
WrittenText:
"written, "
BytesText:
" bytes"
DotText:
"."
WhatText:
"l list, a add, i insert, c change, d delete, w write, q quit"
NoNameText:
"edit what? try: run edit <file>"
NoLineText:
"there is no such line"
NeedsLineText:
"which line?"
NoWriteText:
"it would not write"

FileName:
  #Reserve 0d24
Command:
  #Reserve 0d41
Entry:
  #Reserve 0d81

TextHead:
  0x00 0x00
ArenaFree:
  0x00 0x00
PrevLine:
  0x00 0x00
NewLine:
  0x00 0x00
Wanted:
  0x00
Wanted2:
  0x00
Counted:
  0x00
Leftover:
  0x00
EntryLength:
  0x00
ReadLeft:
  0x00 0x00
WroteSize:
  0x00 0x00

#Include text.asm
