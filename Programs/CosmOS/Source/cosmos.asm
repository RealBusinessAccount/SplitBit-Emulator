; cosmos.asm
; CosmOS, and the shell that is most of it.
;
; The machine boots into this. It registers what the hardware brought, mounts whatever
; disk is attached, and then reads lines and does what they say until there is no more
; typing to be had.
;
; ---- Where things live ----
;
; The system keeps to the bottom of both memories, and everything above is for whatever
; it is running:
;
;   Program Memory  0x0000 - 0x1FFF  the system
;                   0x2000 -         a loaded program's code
;   Data Memory     0x0000 - 0x0FFF  the system
;                   0x1000 -         a loaded program's data
;
; Nothing enforces that. Nothing can: the fence guards a range, and this is a convention
; about which range belongs to whom rather than a rule about what may be touched. The
; assembler prints both segment sizes, and they are what to watch.
;
; A program is staged at 0x8000 while it is being loaded, which is inside the region a
; loaded program will own. That is safe because nothing is running during a load, and it
; is where a big program can be read without the system reserving the room for good.
;
; ---- What it can do ----
;
;   dir     List what is on the disk.
;   load    Read a program off the disk and put it where it asks to go.
;   run     Start the program that was loaded.
;   help    Say what these are.
;   exit    Stop.
;
; dump is next. The dispatch below is a chain of comparisons, which is the right shape for
; five commands and the wrong shape for twenty; when it grows, the table that
; dispatchTest.asm demonstrates is where it should go.
;
; Written by Anachronaut

#Include console.asm
#Include text.asm
#Include sbfs.asm
#Include services.asm

#Program

boot:
  SETD.0 Banner
  CALL printString
  CALL newLine

  ; Find out whether there is a filesystem to talk to. Doing this once at boot rather than
  ; once per command means a disk swapped underneath us is not noticed, which is honest
  ; for a machine whose disk is a file named on the command line.
  CALL sbfsMount
  SETD.0 DiskReady
  BNQ bootNoDisk
  INIA 0x01
  STA.0
  BRI prompt
bootNoDisk:
  RSTA
  STA.0
  SETD.0 NoDisk
  CALL printString
  CALL newLine

; ---- The loop ----

prompt:
  SETD.0 PromptText
  CALL printString

  SETD.0 CommandLine
  INIB 0d63
  CALL readLine

  ; Running out of typing is how this ends. It is not the same as an empty line, which is
  ; just somebody pressing return, and the shell should sit there when that happens.
  SETD.0 ConsoleEndOfInput
  LDA.0
  BNA quitRanOut

  SETD.0 CommandLine
  CALL textSplit

  ; An empty line asks for nothing.
  SETD.0 CommandLine
  LDA.0
  BRA prompt

  SETD.0 CommandLine
  SETD.1 DirName
  CALL textSame
  BRQ doDir

  SETD.0 CommandLine
  SETD.1 LoadName
  CALL textSame
  BRQ doLoad

  SETD.0 CommandLine
  SETD.1 RunName
  CALL textSame
  BRQ doRun

  SETD.0 CommandLine
  SETD.1 DumpName
  CALL textSame
  BRQ doDump

  SETD.0 CommandLine
  SETD.1 HelpName
  CALL textSame
  BRQ doHelp

  SETD.0 CommandLine
  SETD.1 ExitName
  CALL textSame
  BRQ quit

  ; Nothing matched. Saying which word was not understood is worth the four instructions:
  ; it tells somebody who mistyped what they actually typed.
  SETD.0 Unknown
  CALL printString
  SETD.0 CommandLine
  CALL printString
  CALL newLine
  BRI prompt

; Running out of console leaves the cursor part way along a line, because there was no
; return at the end to move it on. Somebody who typed "exit" has already pressed one, and
; a second would only leave a blank line behind.
quitRanOut:
  CALL newLine
quit:
  SETD.0 Farewell
  CALL printString
  CALL newLine
  HALT

; ---- dir ----
;
; Walks the directory and prints what is in it. A free entry in the middle of a directory
; is stepped over by the walk, so what comes out is the files and nothing else.

doDir:
  SETD.0 DiskReady
  LDA.0
  BRA dirNoDisk

  RSTA
  SETD.0 DirSeen
  STA.0

  CALL sbfsFirst
  BRI dirCheck
dirStep:
  CALL sbfsNext
dirCheck:
  BNQ dirDone

  SETD.0 DirSeen
  LDA.0
  INCA
  STA.0

  SETD.0 SbfsName
  CALL printString

  SETD.0 SbfsName
  CALL nameWidth
  MVQA
  CALL printSpaces

  ; A file's length is its block count times 256 plus its tail, which is the block count
  ; in the high byte and the tail in the low one. Nothing has to multiply anything.
  SETD.0 SbfsFileBlocks
  DPUP.0 0d01
  LDA.0
  SETD.1 DirSize
  STA.1
  SETD.0 SbfsFileTail
  LDA.0
  SETD.1 DirSize
  INCD.1
  STA.1

  SETD.0 DirSize
  CALL printWordDecimal
  CALL newLine
  BRI dirStep

dirDone:
  SETD.0 DirSeen
  LDA.0
  CALL printByteDecimal
  SETD.0 FilesText
  CALL printString
  CALL newLine
  BRI prompt

dirNoDisk:
  SETD.0 NoDisk
  CALL printString
  CALL newLine
  BRI prompt

; DP0 names a string. Q is how many spaces pad it out to twenty four columns. A name
; already that long gets one space, so that it cannot run into the number after it.
nameWidth:
  INIA 0d24
  SETD.1 WidthLeft
  STA.1
widthLoop:
  LDA.0
  BRA widthDone
  SETD.1 WidthLeft
  LDA.1
  DECA
  STA.1
  BRA widthFloor
  INCD.0
  BRI widthLoop
widthFloor:
  INIA 0d1
  SETD.1 WidthLeft
  STA.1
widthDone:
  SETD.1 WidthLeft
  LDA.1
  RSTB
  CCF
  ADD
  RET

; ---- load ----
;
; Reads a program off the disk and puts it where its header asks to go. Nothing relocates
; anything: the addresses in the header are the ones the program was built for, and it
; would not work anywhere else.
;
; The whole file is staged at 0x8000 first and then blitted into place, because where the
; pieces belong is not known until the header has been read, and the header is in the file.

doLoad:
  SETD.0 DiskReady
  LDA.0
  BRA loadNoDisk

  SETD.1 TextRest
  LDD.0.1
  LDA.0
  BRA loadNothingNamed

  CALL sbfsFind
  BNQ loadMissing

  SETD.1 0x80 0x00
  CALL sbfsRead
  BNQ loadUnreadable

  ; "SBEX", or this is not a program. Without this, loading a text file would put nonsense
  ; into Program Memory and then jump into the middle of it.
  SETD.0 0x80 0x00
  SETD.2 ExecMagic
  INIA 0d4
  SETD.1 LoadCount
  STA.1
loadMagicLoop:
  LDA.0
  LDB.2
  XOR
  BNQ loadNotProgram
  INCD.0
  INCD.2
  LDA.1
  DECA
  STA.1
  BNA loadMagicLoop

  SETD.0 0x80 0x00
  DPUP.0 0d04
  LDA.0
  INIB 0d1
  XOR
  BNQ loadWrongVersion

  ; The code. It comes from the staging area just past the sixteen byte header, and goes
  ; wherever the header says, in Program Memory, which the instruction set cannot write
  ; and the controller can.
  INIA 0d1
  OUTA 0xE0             ; SourceBank: Data Memory, where the file was staged.
  INIA 0x80
  OUTA 0xE1
  INIA 0d16
  OUTA 0xE2             ; 0x8010, the first byte after the header.

  RSTA
  OUTA 0xE3             ; DestBank: Program Memory.
  SETD.0 0x80 0x00
  DPUP.0 0d06
  LDA.0
  OUTA 0xE4
  INCD.0
  LDA.0
  OUTA 0xE5

  SETD.0 0x80 0x00
  DPUP.0 0d10
  LDA.0
  OUTA 0xE6
  INCD.0
  LDA.0
  OUTA 0xE7

  INIA 0x01
  OUTA 0xE8             ; Blit.

  ; Then the data. A blit leaves its addresses past whatever it touched, so the source is
  ; already sitting on the first byte of the data and only the destination changes.
  INIA 0d1
  OUTA 0xE3             ; DestBank: Data Memory.
  SETD.0 0x80 0x00
  DPUP.0 0d12
  LDA.0
  OUTA 0xE4
  INCD.0
  LDA.0
  OUTA 0xE5

  SETD.0 0x80 0x00
  DPUP.0 0d14
  LDA.0
  OUTA 0xE6
  INCD.0
  LDA.0
  OUTA 0xE7

  INIA 0x01
  OUTA 0xE8             ; Blit.

  ; Where it starts. Written out by hand rather than through a routine, because a routine
  ; could not hand two bytes back: CALL puts A, B and the first three pointers back the
  ; way it found them.
  SETD.0 0x80 0x00
  DPUP.0 0d08
  LDA.0
  SETD.1 LoadedEntry
  STA.1
  INCD.0
  INCD.1
  LDA.0
  STA.1

  INIA 0x01
  SETD.0 LoadedOk
  STA.0

  SETD.0 LoadedText
  CALL printString
  SETD.0 LoadedEntry
  CALL printWordHex
  CALL newLine
  BRI prompt

loadNoDisk:
  SETD.0 NoDisk
  BRI loadComplain
loadNothingNamed:
  SETD.0 LoadWhat
  BRI loadComplain
loadMissing:
  SETD.0 NoSuchFile
  BRI loadComplain
loadUnreadable:
  SETD.0 Unreadable
  BRI loadComplain
loadNotProgram:
  SETD.0 NotProgram
  BRI loadComplain
loadWrongVersion:
  SETD.0 WrongVersion
loadComplain:
  CALL printString
  CALL newLine
  BRI prompt

; ---- run ----
;
; Hands the machine to whatever was loaded. Where the Stack is now is written down first,
; because the program is not going to unwind anything it pushes and the exit handler has
; to be able to put the Stack back.

doRun:
  SETD.0 LoadedOk
  LDA.0
  BRA runNothing

  MVSD.0
  SETD.1 SystemStack
  STD.0.1

  ; The entry address is a number until BRD makes it a place. DP3 is the one to build it
  ; in, because it is the pointer nothing puts back.
  SETD.1 LoadedEntry
  LDD.3.1
  BRD.3

runNothing:
  SETD.0 NothingLoaded
  CALL printString
  CALL newLine
  BRI prompt

; ---- The services ----
;
; These are what a loaded program is allowed to ask for. The names and their numbers come
; from services.asm, which the programs include as well, so neither side writes a number
; down and the two cannot disagree about them.
;
; A handler arrives with the caller's registers exactly as they were: an interrupt frame
; is pushed, not cleared. So the pointer a program put in DP0 is still there to be used.

handlePrintString:
  CALL printString
  RETI

handleReadLine:
  CALL readLine
  RETI

; Giving the machine back. This is the one place MVDS earns its keep. The program's Stack,
; and the frame this very interrupt arrived on, are both abandoned where they lie, because
; nothing is going to return through either of them.
;
; Which is exactly why this cannot RETI. Its return address is on the Stack it just walked
; away from, so it branches to the prompt instead.
handleExit:
  SETD.1 SystemStack
  LDD.0.1
  MVDS.0

  ; The console goes back to line mode whatever the program left it in. A program that
  ; wanted keys is expected to put it back itself, but one that stopped early, or forgot,
  ; would otherwise hand back a shell with no echo and no backspace, and the shell has no
  ; way to find out that happened. Writing line mode when it is already in line mode costs
  ; a byte out of a port and does nothing, which is the right price for not having to know.
  RSTA
  OUTA 0x02

  SETD.0 Finished
  CALL printString
  CALL newLine
  BRI prompt

; ---- dump ----
;
;   dump                  Sixty four more bytes, carrying on from the last one.
;   dump <where>          From the start of that bank.
;   dump <where> <addr>   From there.
;
; <where> is program, data, or a bank number in hexadecimal. That the CPU cannot read
; Program Memory and this can is the whole point: the instruction set has no way to look
; at itself, and the controller does, so a monitor is possible at all only through it.

doDump:
  SETD.1 TextRest
  LDD.0.1
  LDA.0
  BRA dumpGo            ; Nothing said, so carry on from where the last one stopped.

  ; Which bank. The two that always exist have names, because typing "program" is what
  ; somebody means and 0 is what the machine calls it.
  CALL textSplit
  SETD.1 ProgramWord
  CALL textSame
  BRQ dumpBankProgram
  SETD.1 DataWord
  CALL textSame
  BRQ dumpBankData

  CALL textHexWord
  BNQ dumpBadWhere
  SETD.0 TextValue
  INCD.0
  LDA.0
  BRI dumpSetBank
dumpBankProgram:
  RSTA
  BRI dumpSetBank
dumpBankData:
  INIA 0d1
dumpSetBank:
  SETD.0 DumpBank
  STA.0

  ; And where in it. Naming a bank without an address means the start of it, which is the
  ; only answer that does not depend on what was asked for last time.
  RSTA
  SETD.0 DumpAt
  STA.0
  INCD.0
  STA.0

  SETD.1 TextRest
  LDD.0.1
  LDA.0
  BRA dumpCheckBank
  CALL textHexWord
  BNQ dumpBadWhere
  SETD.0 TextValue
  LDA.0
  SETD.1 DumpAt
  STA.1
  SETD.0 TextValue
  INCD.0
  LDA.0
  SETD.1 DumpAt
  INCD.1
  STA.1

dumpCheckBank:
  ; Is there such a bank? Asking the controller for a bank that is not there is refused,
  ; and a refusal nobody catches stops the machine, which is a poor answer to a typing
  ; mistake. The bank table says what exists, and it lives in bank 2.
  ;
  ; Bank n's record starts at n times eight. A and B are a shift register sixteen bits
  ; wide, so putting the number in the low half and rotating left three times multiplies
  ; it by eight without anything falling off the top: the most it can reach is 2040.
  RSTA
  SETD.0 DumpBank
  LDB.0
  SHL SHL SHL
  SETD.0 DumpRecord
  STA.0
  INCD.0
  STB.0

  INIA 0d2
  OUTA 0xE0             ; SourceBank: the controller's own memory.
  SETD.0 DumpRecord
  LDA.0
  OUTA 0xE1
  INCD.0
  LDA.0
  OUTA 0xE2
  INA 0xE9              ; The flags byte of that bank's record.
  INIB 0x01
  AND
  BRQ dumpNoBank        ; The present bit is down, so nothing is there.

dumpGo:
  INIA 0d4
  SETD.0 DumpRows
  STA.0

dumpRow:
  SETD.0 DumpAt
  CALL printWordHex
  INIA 0d2
  CALL printSpaces

  ; Point the controller at the row. Reading the Data port takes a byte and steps the
  ; source on, so the whole row is one instruction repeated.
  SETD.0 DumpBank
  LDA.0
  OUTA 0xE0
  SETD.0 DumpAt
  LDA.0
  OUTA 0xE1
  INCD.0
  LDA.0
  OUTA 0xE2

  ; Sixteen bytes, kept as they go past so that they can be shown twice.
  INIA 0d16
  SETD.0 DumpCount
  STA.0
  SETD.1 DumpBytes
dumpByte:
  INA 0xE9
  STA.1
  CALL printByteHex
  INIA 0x20
  OUTA 0x00
  INCD.1
  SETD.0 DumpCount
  LDA.0
  DECA
  STA.0
  BNA dumpByte

  ; The same sixteen again, as characters. Anything that is not printable shows as a dot,
  ; because a control character sent to the console would move the cursor and ruin the
  ; shape of the dump.
  INIA 0x20
  OUTA 0x00
  INIA 0d16
  SETD.0 DumpCount
  STA.0
  SETD.1 DumpBytes
dumpChar:
  LDA.1
  INIB 0x20
  CCF
  SUB
  BRC dumpDot           ; Below a space.
  INIB 0x7F
  CCF
  SUB
  BNC dumpDot           ; Delete, or above it.
  OUTA 0x00
  BRI dumpCharNext
dumpDot:
  INIA 0x2E
  OUTA 0x00
dumpCharNext:
  INCD.1
  SETD.0 DumpCount
  LDA.0
  DECA
  STA.0
  BNA dumpChar
  CALL newLine

  ; Sixteen further along, carrying into the high byte if the low one wrapped.
  SETD.0 DumpAt
  INCD.0
  LDA.0
  INIB 0d16
  CCF
  ADD
  STQ.0
  BNC dumpRowNext
  SETD.0 DumpAt
  LDA.0
  INCA
  STA.0
dumpRowNext:
  SETD.0 DumpRows
  LDA.0
  DECA
  STA.0
  BNA dumpRow
  BRI prompt

dumpBadWhere:
  SETD.0 DumpUsage
  CALL printString
  CALL newLine
  BRI prompt
dumpNoBank:
  SETD.0 NoSuchBank
  CALL printString
  CALL newLine
  BRI prompt

; ---- help ----

doHelp:
  SETD.0 HelpText
  CALL printString
  CALL newLine
  SETD.0 HelpMoreText
  CALL printString
  CALL newLine
  BRI prompt

#Data

Banner:
"CosmOS"
PromptText:
"> "
NoDisk:
"no filesystem on the disk"
Unknown:
"I do not know: "
Farewell:
"halted"
FilesText:
" files"

; Two strings rather than one, because a string literal stops at 255 characters and each
; one carries its own zero byte, so they are printed in turn rather than joined.
HelpText:
"dir          list what is on the disk
load <file>  read a program off the disk
run          start what was loaded"
HelpMoreText:
"dump         sixty four bytes of memory, and again for more
             dump <program|data|bank> <address>
help         this
exit         stop"

DumpUsage:
"dump <program|data|bank> <address>"
NoSuchBank:
"there is no such bank"
ProgramWord:
"program"
DataWord:
"data"
DumpName:
"dump"

ExecMagic:
"SBEX"
LoadWhat:
"load what?"
NoSuchFile:
"no such file"
Unreadable:
"could not read it"
NotProgram:
"not a program"
WrongVersion:
"a version I do not know"
LoadedText:
"loaded, starting at "
NothingLoaded:
"nothing is loaded"
Finished:
"finished"

DirName:
"dir"
LoadName:
"load"
RunName:
"run"
HelpName:
"help"
ExitName:
"exit"

DiskReady:
  0x00
LoadedOk:
  0x00
LoadedEntry:
  0x00 0x00
LoadCount:
  0x00

; Where the monitor is looking, so that a bare 'dump' can carry on from it.
DumpBank:
  0x00
DumpAt:
  0x00 0x00
DumpRows:
  0x00
DumpCount:
  0x00
DumpRecord:
  0x00 0x00
DumpBytes:
  #Reserve 0d16

; Where the system's Stack was when it handed the machine to a program. Kept below the
; region a program owns, so that a program has to go looking to break it.
SystemStack:
  0x00 0x00
DirSeen:
  0x00
DirSize:
  0x00 0x00
WidthLeft:
  0x00

; Sixty three characters and the zero byte that ends them.
CommandLine:
  #Reserve 0d64

#Vectors

  Boot           boot
  osPrintString  handlePrintString
  osReadLine     handleReadLine
  osExit         handleExit
