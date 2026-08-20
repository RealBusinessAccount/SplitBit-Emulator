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

; ---- The loop ----
;
; The shell has two modes and one prompt that says which. Ordinary mode runs programs;
; monitor mode also looks at memory, changes it, and jumps into it.
;
; THE MODE IS A VARIABLE RATHER THAN A SECOND LOOP, and that is what makes it persistent
; without anything having to remember it. Every way back here goes through this one place,
; INCLUDING A PROGRAM GIVING THE MACHINE BACK - so jumping to an address, letting it run,
; and having it exit puts you back at the monitor prompt you left from, rather than at the
; shell. Only saying so leaves the monitor, or a program breaking the machine badly enough
; to need starting again.
prompt:
  SETD.0 Mode
  LDA.0
  BRA promptPlain
  SETD.0 MonitorPrompt
  BRI promptSay
promptPlain:
  SETD.0 PromptText
promptSay:
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
  SETD.1 DeleteName
  CALL textSame
  BRQ doDelete

  SETD.0 CommandLine
  SETD.1 RenameName
  CALL textSame
  BRQ doRename

  SETD.0 CommandLine
  SETD.1 HelpName
  CALL textSame
  BRQ doHelp

  SETD.0 CommandLine
  SETD.1 ExitName
  CALL textSame
  BRQ doExit

  SETD.0 CommandLine
  SETD.1 MonitorName
  CALL textSame
  BRQ doMonitor

  ; The monitor's own commands, which only answer when the monitor is on. They are single
  ; letters because they are typed constantly and because the prompt has already said which
  ; mode you are in; the plain shell keeps its words and stays plain.
  SETD.0 Mode
  LDA.0
  BRA promptUnknown

  SETD.0 CommandLine
  SETD.1 ExamineName
  CALL textSame
  BRQ doExamine

  SETD.0 CommandLine
  SETD.1 DisName
  CALL textSame
  BRQ doDisassemble

  SETD.0 CommandLine
  SETD.1 SetName
  CALL textSame
  BRQ doSet

  SETD.0 CommandLine
  SETD.1 BankName
  CALL textSame
  BRQ doBank

  SETD.0 CommandLine
  SETD.1 GoName
  CALL textSame
  BRQ doGo

  SETD.0 CommandLine
  SETD.1 AsmName2
  CALL textSame
  BRQ doAssemble

promptUnknown:
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
; Leaving whatever you are in: the monitor if you are in it, and the machine if you are
; not. Two exits to stop from the monitor, which is what every nested prompt has ever asked
; for and reads the right way round.
doExit:
  SETD.0 Mode
  LDA.0
  BRA quit
  RSTA
  STA.0
  BRI prompt

doMonitor:
  INIA 0x01
  SETD.0 Mode
  STA.0
  SETD.0 MonitorHelp
  CALL printString
  CALL newLine
  BRI prompt

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
  ; One file is not one files. Cheap to get right and it reads as carelessness otherwise.
  SETD.0 DirSeen
  LDA.0
  DECA
  BRA dirOne
  SETD.0 FilesText
  BRI dirCount
dirOne:
  SETD.0 FileText
dirCount:
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

  ; Version one is code and data. Version two also brings vectors, which is a thing a
  ; loader has to know how to do rather than a detail it can skip: a program whose handlers
  ; were quietly dropped would run and then go wrong somewhere with nothing to connect it
  ; back to here. Anything else is refused.
  SETD.0 0x80 0x00
  DPUP.0 0d04
  LDA.0
  SETD.1 LoadVersion
  STA.1
  INIB 0d1
  XOR
  BRQ loadVersionKnown
  SETD.1 LoadVersion
  LDA.1
  INIB 0d2
  XOR
  BNQ loadWrongVersion
loadVersionKnown:

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

  ; ---- The vectors it brought ----
  ;
  ; Kept here rather than installed. A vector points into a program, so it has no business
  ; being in the table while that program is only loaded and not running: run puts them in
  ; and exit takes them out again, so the window they are live in is exactly the run.
  ; Keeping our own copy is also what lets a program be run more than once, since the
  ; staging area it came in on is fair game for the program's own use.
  ;
  ; Where to read them from is not worked out. The data blit left the controller's source
  ; address on the first byte after the data, which is where they are, so it is read back.
  SETD.0 VectorSource
  INA 0xE1
  STA.0
  INCD.0
  INA 0xE2
  STA.0

  SETD.0 0x80 0x00
  DPUP.0 0d05
  LDA.0
  SETD.1 LoadedVectorCount
  STA.1
  BRA loadVectorsCopied

  ; More than there is room for is refused rather than half taken. Half a program's
  ; handlers is not a smaller version of that program.
  INIB 0d17
  CCF
  SUB
  BNC loadTooManyVectors

  SETD.0 VectorSource
  LDD.2.0                   ; DP2 walks the entries where they are staged.
  SETD.3 LoadedVectors      ; DP3 walks our own copy of them.
  SETD.1 LoadedVectorCount
  LDA.1
  SETD.1 VectorsLeft
  STA.1

loadVectorCopy:
  ; Four bytes: where it goes, then what goes there. The two bytes for what was there
  ; before are left alone until something is actually put in.
  LDA.2
  STA.3
  INCD.2
  INCD.3
  LDA.2
  STA.3
  INCD.2
  INCD.3
  LDA.2
  STA.3
  INCD.2
  INCD.3
  LDA.2
  STA.3
  INCD.2
  INCD.3
  INCD.3
  INCD.3

  SETD.1 VectorsLeft
  LDA.1
  DECA
  STA.1
  BNA loadVectorCopy

loadVectorsCopied:

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
loadTooManyVectors:
  SETD.0 TooManyVectors
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

; ---- delete and rename ----
;
; The two things a disk needs that reading and writing do not provide, and the two that
; anything editing a document will want from the shell as well as from a program. Deleting
; frees an entry and its blocks; renaming changes twenty two bytes and moves nothing.

doDelete:
  SETD.0 DiskReady
  LDA.0
  BRA fileNoDisk

  SETD.1 TextRest
  LDD.0.1
  LDA.0
  BRA deleteWhat

  CALL sbfsDelete
  BNQ deleteFailed
  SETD.0 Deleted
  CALL printString
  CALL newLine
  BRI prompt

deleteWhat:
  SETD.0 DeleteWhat
  BRI fileComplain
deleteFailed:
  SETD.0 NoSuchFile
  BRI fileComplain

doRename:
  SETD.0 DiskReady
  LDA.0
  BRA fileNoDisk

  SETD.1 TextRest
  LDD.0.1
  LDA.0
  BRA renameWhat

  ; Two names, so the rest of the line is split again. textSplit writes a zero over the
  ; space it cuts at, so what was one string becomes two without anything being copied.
  SETD.1 TextRest
  LDD.0.1
  SETD.1 RenameFrom
  STD.0.1
  CALL textSplit

  SETD.1 TextRest
  LDD.1.1
  LDA.1
  BRA renameWhat            ; Only one name was given, and this needs both.

  SETD.2 RenameFrom
  LDD.0.2
  CALL sbfsRename
  BNQ renameFailed
  SETD.0 Renamed
  CALL printString
  CALL newLine
  BRI prompt

renameWhat:
  SETD.0 RenameWhat
  BRI fileComplain
renameFailed:
  ; Either there is no such file or the new name is already taken. Which of the two is not
  ; worth another message: both mean the disk does not have room for that name to move.
  SETD.0 RenameNo
  BRI fileComplain

fileNoDisk:
  SETD.0 NoDisk
fileComplain:
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

  ; Whatever followed the word "run" is kept where the program can ask for it. Copied
  ; rather than pointed at, because what it is pointing at is the line the shell typed
  ; into, and a program is entitled to outlive the shell's opinion of that.
  SETD.1 TextRest
  LDD.0.1
  SETD.1 RunArgument
  INIB 0d64
  CALL copyText

  CALL installVectors

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

; DP0 is a string, DP1 is where it should go, and B is how much room there is counting
; the zero on the end. What does not fit is left behind, and what is written is a string
; either way.
copyText:
  BRB copyTextDone          ; No room at all, so nothing is written, not even the zero.
copyTextLoop:
  DECB
  BRB copyTextEnd           ; Only room for the terminator now.
  LDA.0
  STA.1
  BRA copyTextDone
  INCD.0
  INCD.1
  BRI copyTextLoop
copyTextEnd:
  RSTA
  STA.1
copyTextDone:
  RET

; ---- Putting a program's vectors in, and taking them out again ----
;
; The vector table lives in Program Memory, which no instruction can write, so both of
; these go through the memory controller. Port 0xE9 reads a byte from the source and writes
; a byte to the destination, stepping the address on either way, so a two byte entry is two
; reads or two writes and no address arithmetic in between.
;
; What was in the slot is kept before anything replaces it, and put back afterwards, rather
; than the slot being cleared. Clearing would be wrong wherever a program has installed a
; handler over one the system was already using: the program is allowed to do that, and
; when it goes, what it covered up has to come back rather than becoming a hole.

installVectors:
  SETD.0 LoadedVectorCount
  LDA.0
  BRA installDone
  SETD.1 VectorsLeft
  STA.1
  SETD.3 LoadedVectors

installOne:
  ; DP3 walks one six byte entry: where it goes, what goes there, and room for what was
  ; there before. Reading and writing the same slot, so the controller is pointed at it
  ; from both ends at once and the address is only worked out once.
  RSTA
  OUTA 0xE0                 ; SourceBank: Program Memory.
  OUTA 0xE3                 ; DestBank: the same.
  LDA.3
  OUTA 0xE1
  OUTA 0xE4
  INCD.3
  LDA.3
  OUTA 0xE2
  OUTA 0xE5
  INCD.3                    ; On the handler.

  ; What is there now, before anything replaces it.
  INA 0xE9
  PSHA
  INA 0xE9
  PSHA

  ; And the handler in its place.
  LDA.3
  OUTA 0xE9
  INCD.3
  LDA.3
  OUTA 0xE9
  INCD.3                    ; On the two bytes kept for what was there before.

  ; The Stack gives them back in the reverse of the order they went on, so the low byte
  ; arrives first and is written to the second of the two. Getting this the natural way
  ; round instead put the low byte where the high one goes and the high byte over the
  ; handler, which the first run of a program survives - the table is already written by
  ; then - and the second run does not.
  POPA
  INCD.3
  STA.3
  DECD.3
  POPA
  STA.3
  INCD.3
  INCD.3

  SETD.1 VectorsLeft
  LDA.1
  DECA
  STA.1
  BNA installOne
installDone:
  RET

removeVectors:
  SETD.0 LoadedVectorCount
  LDA.0
  BRA removeDone
  SETD.1 VectorsLeft
  STA.1
  SETD.3 LoadedVectors

removeOne:
  RSTA
  OUTA 0xE3                 ; DestBank: Program Memory.
  LDA.3
  OUTA 0xE4
  INCD.3
  LDA.3
  OUTA 0xE5
  INCD.3
  INCD.3
  INCD.3                    ; Past the handler, to what was underneath it.
  LDA.3
  OUTA 0xE9
  INCD.3
  LDA.3
  OUTA 0xE9
  INCD.3

  SETD.1 VectorsLeft
  LDA.1
  DECA
  STA.1
  BNA removeOne
removeDone:
  RET

; ---- The services ----
;
; These are what a loaded program is allowed to ask for. The names and their numbers come
; from services.asm, which the programs include as well, so neither side writes a number
; down and the two cannot disagree about them.
;
; A handler arrives with the caller's registers exactly as they were: an interrupt frame
; is pushed, not cleared. So the pointer a program put in DP0 is still there to be used.

; The disk finishing, acknowledged and ignored.
;
; The system drives the disk by asking its status port and waiting, so it has no use for
; the line. But the disk raises one after every operation whether anybody wants it or not,
; and a line goes on waiting while the Interrupt Flag is down rather than being lost. The
; shell keeps the flag down, so the line from the last disk read was still standing when
; the first program to enable interrupts ran, and it arrived there - a fault, in a program
; that had never heard of the disk, blamed on the innocent instruction that let it through.
;
; Answering a line is what takes it down, so this is one instruction and that is the point.
diskDone:
  RETI

handlePrintString:
  CALL printString
  RETI

handleReadLine:
  CALL readLine

  ; readLine works out how long the line was, and RETI would throw that away: it restores
  ; every register from the frame, which is exactly what makes an interrupt safe to arrive
  ; unannounced and exactly what stops a service answering. So the answer is written into
  ; the frame, over the saved Q, and RETI puts it back as though the caller had computed it.
  ;
  ; This has to be here rather than in a routine, because the offset is from where the
  ; Stack Pointer is now and a CALL moves it by ten.
  MVQA
  MVSD.1
  DPUP.1 0d02
  STA.1
  RETI

; What the program was asked to work on. DP0 says where to put it and B how much room
; there is, counting the zero on the end, which is the same bargain readLine offers.
;
; Being asked for rather than left at an agreed address is deliberate. The two sides of
; this already have to agree on a vector number and nothing else, and that number is
; written down once in services.asm; an address would be a second thing to agree about, in
; a memory map that is a convention rather than anything enforced.
handleArgument:
  PSHD.0
  POPD.1
  SETD.0 RunArgument
  CALL copyText
  RETI

; ---- The disk, on a program's behalf ----
;
; A loaded program that wanted a file used to include the whole filesystem, so it carried a
; private copy of code the system already has running, and mounted a disk that was already
; mounted. These are that code, reachable through a number instead.
;
; Every one of them answers in Q, and the answer is written into the frame over the saved
; register, because RETI puts every register back and would otherwise throw it away. That
; has to be done here rather than in a routine of its own: the offsets are from where the
; Stack Pointer is, and a CALL moves it by ten.
;
; A machine with no disk answers no to all of them rather than going ahead and finding out,
; because sbfs on a disk that was never mounted is reading whatever bank 3 happens to be.

; DP0 names the file, DP1 says where to put it. Q is zero if it read, and DP3 comes back
; holding how many bytes there were.
handleFileRead:
  SETD.2 DiskReady
  LDA.2
  BRA fileReadNo

  CALL sbfsFind
  BNQ fileReadNo

  ; A file of 256 blocks is 64K, which will not fit in Data Memory and will not fit in the
  ; pointer that says how long it is either. Refused, rather than read as much of as fits:
  ; a length that lies is worse than a file that will not open.
  SETD.2 SbfsFileBlocks
  LDA.2
  BNA fileReadNo

  CALL sbfsRead
  BNQ fileReadNo

  ; How long it is: the block count is the high byte of that and the tail is the low one,
  ; which is how a size is put together everywhere on this disk.
  SETD.2 SbfsFileBlocks
  INCD.2
  LDA.2
  SETD.2 SbfsFileTail
  LDB.2

  MVSD.2
  DPUP.2 0d05               ; The saved DP3, high byte first.
  STA.2
  INCD.2
  STB.2

  MVSD.2
  DPUP.2 0d02               ; And the saved Q.
  RSTA
  STA.2
  RETI

fileReadNo:
  MVSD.2
  DPUP.2 0d02
  INIA 0d1
  STA.2
  RETI

; DP0 names the file, DP1 is the bytes, and A and B together are how many. Q is zero if it
; saved. Whether it was there before makes no difference, which is what saving means.
handleFileSave:
  SETD.2 DiskReady
  PSHA
  LDA.2
  BRA fileSaveNoDisk
  POPA

  ; Blocks are the high half of the count and the tail is the low half.
  SETD.2 SbfsFileBlocks
  PSHA
  RSTA
  STA.2                     ; A whole file's block count fits in a byte, so this is zero.
  INCD.2
  POPA
  STA.2
  SETD.2 SbfsFileTail
  STB.2

  CALL sbfsSaveFile
  MVQA
  MVSD.2
  DPUP.2 0d02
  STA.2
  RETI

fileSaveNoDisk:
  POPA
  MVSD.2
  DPUP.2 0d02
  INIA 0d1
  STA.2
  RETI

; DP0 names it. Q is zero if it went.
handleFileDelete:
  SETD.2 DiskReady
  LDA.2
  BRA serviceNoDisk
  CALL sbfsDelete
  MVQA
  MVSD.2
  DPUP.2 0d02
  STA.2
  RETI

; DP0 is the name it has, DP1 the name it should have. Q is zero if it moved.
handleFileRename:
  SETD.2 DiskReady
  LDA.2
  BRA serviceNoDisk
  CALL sbfsRename
  MVQA
  MVSD.2
  DPUP.2 0d02
  STA.2
  RETI

serviceNoDisk:
  MVSD.2
  DPUP.2 0d02
  INIA 0d1
  STA.2
  RETI

; A breakpoint. Shows every register as the interrupted program had them, waits for a key,
; and returns as though nothing happened.
;
; EVERY VALUE COMES OUT OF THE FRAME, not out of the registers, because by the time this
; runs the registers belong to the handler. The frame is what the program had, and RETI is
; going to give it all back, so what is shown is what will be resumed with.
;
; DP3 holds the frame throughout. It survives a CALL, and console.asm promises not to
; disturb it, which is what lets the printing routines be used between one field and the
; next. The Stack Pointer comes back to the same place after a balanced call, so the frame
; stays where it was found.
;
;   +1 Status  +2 Q  +3 A  +4 B  +5 DP3  +7 DP2  +9 DP1  +11 DP0  +13 where it resumes
handleBreak:
  MVSD.3

  ; Where it broke, which is two before where it resumes: the SWI and the vector it names.
  SETD.0 BreakText
  CALL printString
  PSHD.3
  POPD.0
  DPUP.0 0d13
  LDA.0
  PSHA                  ; The high half, while the low one is worked on.
  INCD.0
  LDA.0
  INIB 0d2
  CCF
  SUB                   ; Two back from where it resumes: the SWI and the vector it names.
  MVQA
  POPB
  BRC breakBorrowed     ; It borrowed, so the high half comes down by one.
  BRI breakAddress
breakBorrowed:
  DECB
breakAddress:
  PSHA                  ; low
  PSHB                  ; high
  POPA
  CALL printByteHex
  POPA
  CALL printByteHex
  CALL newLine

  SETD.0 ARegText
  PSHD.3
  POPD.1
  DPUP.1 0d3
  CALL breakByte
  SETD.0 BRegText
  PSHD.3
  POPD.1
  DPUP.1 0d4
  CALL breakByte
  SETD.0 QRegText
  PSHD.3
  POPD.1
  DPUP.1 0d2
  CALL breakByte
  SETD.0 SRegText
  PSHD.3
  POPD.1
  DPUP.1 0d1
  CALL breakByte

  ; And which bits of it those are, since a debug dump that makes you look the number up is
  ; only half of one. Halt is not among them: the machine is plainly not halted.
  PSHD.3
  POPD.1
  DPUP.1 0d1
  LDA.1
  PSHA
  INIB 0x01
  AND
  BRQ breakNoCarry
  SETD.0 CarryText
  CALL printString
breakNoCarry:
  POPA
  PSHA
  INIB 0x02
  AND
  BRQ breakNoFault
  SETD.0 FaultText
  CALL printString
breakNoFault:
  POPA
  INIB 0x04
  AND
  BRQ breakNoInts
  SETD.0 IntsText
  CALL printString
breakNoInts:
  CALL newLine

  SETD.0 DP0Text
  PSHD.3
  POPD.1
  DPUP.1 0d11
  CALL breakWord
  SETD.0 DP1Text
  PSHD.3
  POPD.1
  DPUP.1 0d9
  CALL breakWord
  SETD.0 DP2Text
  PSHD.3
  POPD.1
  DPUP.1 0d7
  CALL breakWord
  SETD.0 DP3Text
  PSHD.3
  POPD.1
  DPUP.1 0d5
  CALL breakWord

  ; The Stack Pointer is not in the frame, because the frame is where the Stack Pointer is.
  ; What the program had is fourteen bytes above this one, that being what entering an
  ; interrupt puts down.
  SETD.0 SPText
  CALL printString
  PSHD.3
  POPD.0
  DPUP.0 0d14
  PSHD.0
  POPB
  POPA
  CALL printByteHex
  PSHB
  POPA
  CALL printByteHex
  CALL newLine

  ; Anything typed carries on. Reading the data port waits however the console is set, which
  ; is one key if the program asked for key mode and a whole line if it did not - and either
  ; way it is the program's own console being borrowed for a moment.
  SETD.0 ResumeText
  CALL printString
  INA 0x00
  CALL newLine
  RETI

; DP0 names a field and DP1 points at it in the frame. The caller does the stepping, with
; DPUP and a number written into the program, because a routine cannot hand a pointer back:
; CALL saves DP0 to DP2 and RET puts them back, so a walk done in here would be undone on
; the way out. Written that way first, and every field showed the frame's first byte.
breakByte:
  CALL printString
  LDA.1
  CALL printByteHex
  INIA 0x20
  OUTA 0x00
  RET

; The same for the two byte fields, most significant first the way the frame holds them.
breakWord:
  CALL printString
  LDA.1
  CALL printByteHex
  INCD.1
  LDA.1
  CALL printByteHex
  INIA 0x20
  OUTA 0x00
  RET

; A and B together are a number. Prints it in decimal without leading zeroes, which covers
; a line number and a byte count both, so there is no need for one service each.
handlePrintNumber:
  SETD.0 PrintNumber
  STA.0
  INCD.0
  STB.0
  SETD.0 PrintNumber
  CALL printWordDecimal
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

  ; Whatever the program put in the vector table comes out again. A vector points into the
  ; program that supplied it, and the program is gone, so anything left installed would aim
  ; an interrupt at whatever those addresses hold next.
  CALL removeVectors

  ; The console goes back to how the shell wants it, whatever the program left it in: line
  ; mode, and not interrupting. A program that wanted either is expected to put it back
  ; itself, but one that stopped early, or forgot, would otherwise hand back a shell with
  ; no echo and no backspace, or one being interrupted about keys it is reading anyway.
  ; Zero is both bits, so this undoes everything the control port can be asked for, and
  ; asking for what is already the case costs a byte out of a port and does nothing. That
  ; is the right price for not having to know.
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

; b <program|data|number>
;
; The two banks that always exist have names, because "program" is what somebody means and
; 0 is only what the machine calls it. Anything else is a number, and has to be one that is
; really there.
doBank:
  SETD.1 TextRest
  LDD.0.1
  LDA.0
  BRA bankWhat

  SETD.1 ProgramWord
  CALL textSame
  BRQ bankProgram
  SETD.1 DataWord
  CALL textSame
  BRQ bankData

  CALL textHexWord
  BNQ bankWhat
  SETD.0 TextValue
  INCD.0
  LDA.0
  BRI bankSet
bankProgram:
  RSTA
  BRI bankSet
bankData:
  INIA 0d1
bankSet:
  ; The old one is kept, because asking about a bank means writing it down first - and if
  ; it turns out not to exist, being left pointed at it would fault on the very next look.
  SETD.0 DumpBank
  LDB.0
  SETD.1 BankWas
  STB.1
  SETD.0 DumpBank
  STA.0

  ; Naming a bank puts the cursor at the start of it, which is the only answer that does
  ; not depend on what was asked for last time.
  CALL bankPresent
  BRQ bankNotThere

  RSTA
  SETD.0 DumpAt
  STA.0
  INCD.0
  STA.0

  SETD.0 BankIs
  CALL printString
  SETD.0 DumpBank
  LDA.0
  CALL printByteHex
  CALL newLine
  BRI prompt

bankNotThere:
  SETD.0 BankWas
  LDA.0
  SETD.1 DumpBank
  STA.1                 ; Back where it was, which is somewhere that exists.
  SETD.0 NoSuchBank
  CALL printString
  CALL newLine
  BRI prompt

bankWhat:
  SETD.0 BankUsage
  CALL printString
  CALL newLine
  BRI prompt

; x [address] - sixty four bytes. d [address] - eight instructions. Without an address
; either carries on from where the last one stopped, so reading through memory is one
; letter at a time and the two share a place in it.
doExamine:
  RSTA
  SETD.0 ShowAsCode
  STA.0
  BRI showAt

doDisassemble:
  INIA 0x01
  SETD.0 ShowAsCode
  STA.0

showAt:
  SETD.1 TextRest
  LDD.0.1
  LDA.0
  BRA dumpGo            ; Nothing said, so carry on from where the last one stopped.
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
  CALL bankPresent
  BRQ dumpNoBank

dumpGo:
  SETD.0 ShowAsCode
  LDA.0
  BNA disassembleGo

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

disassembleGo:
  INIA 0d8
  SETD.0 DumpRows
  STA.0
disassembleOne:
  CALL showInstruction
  SETD.0 DumpRows
  LDA.0
  DECA
  STA.0
  BNA disassembleOne
  BRI prompt

dumpBadWhere:
  SETD.0 ExamineUsage
  CALL printString
  CALL newLine
  BRI prompt
dumpNoBank:
  SETD.0 NoSuchBank
  CALL printString
  CALL newLine
  BRI prompt

; s <address> <byte> <byte> ...
;
; Writes into whichever bank is being looked at, THROUGH THE CONTROLLER, so Program Memory
; can be changed as easily as Data - which no instruction on this machine can do, and which
; is most of the reason for having a monitor at all.
;
; The cursor is left alone. Somebody poking a byte is usually looking at something else, and
; having the address they were reading move underneath them would be a poor reward.
doSet:
  ; A bank can be present and still refuse to be written: the controller's own table is
  ; published read only, and writing to it is refused. A refusal nobody catches stops the
  ; machine, which is a poor answer to somebody looking around with b and then typing s.
  CALL bankPresent
  SETD.0 BankFlags
  LDA.0
  INIB 0x02                 ; The read only bit of that bank's record.
  AND
  BNQ setReadOnly

  SETD.1 TextRest
  LDD.0.1
  CALL textHexWord
  BNQ setWhat

  SETD.1 DumpBank
  LDA.1
  OUTA 0xE3
  SETD.1 TextValue
  LDA.1
  OUTA 0xE4
  INCD.1
  LDA.1
  OUTA 0xE5

  CALL stepPastNumber
  PSHD.3
  POPD.0
setByte:
  CALL textHexWord
  BNQ prompt            ; Nothing more on the line, so that was all of them.
  SETD.1 TextValue
  INCD.1
  LDA.1
  OUTA 0xE9             ; The destination steps on by itself, so a run of bytes is a loop.
  CALL stepPastNumber
  PSHD.3
  POPD.0
  BRI setByte

setReadOnly:
  SETD.0 ReadOnlyText
  CALL printString
  CALL newLine
  BRI prompt

setWhat:
  SETD.0 SetUsage
  CALL printString
  CALL newLine
  BRI prompt

; g <address>
;
; Somewhere to go. It does not come back by itself - that would want a breakpoint, which is
; a byte written over an instruction and a handler waiting for it, and neither exists yet.
; But a program that gives the machine back the ordinary way lands at the prompt it was
; started from, which is this one, still in the monitor.
doGo:
  SETD.1 TextRest
  LDD.0.1
  CALL textHexWord
  BNQ goWhat

  ; Where the Stack is now, written down before leaving, exactly as run does it. Whatever is
  ; jumped to may give the machine back through osExit, and osExit puts the Stack back to
  ; what is written here - so without this it would restore the one the LAST run left, or
  ; none at all, and the shell would come back with its Stack pointing at nothing.
  MVSD.0
  SETD.1 SystemStack
  STD.0.1

  SETD.1 TextValue
  LDD.3.1
  BRD.3

goWhat:
  SETD.0 GoUsage
  CALL printString
  CALL newLine
  BRI prompt

; DP0 names text that textHexWord has just read a number off the front of. LEAVES DP3 past
; the digits and any spaces after them, ready for the next one.
;
; DP3 rather than DP0, because a subroutine cannot hand a pointer back in DP0: CALL saves it
; and RET puts it back, so stepping it here would be undone on the way out.
stepPastNumber:
  PSHD.0
  POPD.3
  SETD.1 TextDigits
  LDB.1
stepPastDigits:
  BRB stepPastSpaces
  INCD.3
  DECB
  BRI stepPastDigits
stepPastSpaces:
  LDA.3
  BRA stepPastDone
  INIB 0x20
  XOR
  BNQ stepPastDone
  INCD.3
  BRI stepPastSpaces
stepPastDone:
  RET


; Points the controller's source at the cursor, so that reading port 0xE9 walks forwards.
aimAtDumpAt:
  SETD.0 DumpBank
  LDA.0
  OUTA 0xE0
  SETD.0 DumpAt
  LDA.0
  OUTA 0xE1
  INCD.0
  LDA.0
  OUTA 0xE2
  RET

; One byte from the cursor, and the cursor moves on.
;
; THE BYTE COMES BACK IN Q, not in A, because a subroutine cannot hand anything back in A:
; CALL saves it and RET puts it back, so an assignment here would be undone by the return.
takeByte:
  INA 0xE9
  PSHA
  SETD.0 DumpAt
  INCD.0
  LDA.0
  INCA
  STA.0
  BNC takeByteDone
  DECD.0
  LDA.0
  INCA
  STA.0
takeByteDone:
  POPA
  RSTB
  OR
  RET

; ---- Showing instructions ----
;
; The half of a monitor that a byte dump cannot do. What it needs and a dump does not
; is to know how LONG each instruction is, because getting that wrong does not print one
; line wrong - it loses the place and prints everything after it wrong.

; One instruction: where it is, the bytes it is made of, and what it says.
showInstruction:
  SETD.0 DumpAt
  LDA.0
  CALL printByteHex
  INCD.0
  LDA.0
  CALL printByteHex
  INIA 0x20
  OUTA 0x00
  INIA 0x20
  OUTA 0x00

  CALL aimAtDumpAt
  CALL takeByte
  MVQA
  SETD.0 Opcode
  STA.0

  CALL findInstruction
  BNQ showUnknown

  ; What shape it is, and from that how many bytes it runs to.
  PSHD.3
  POPD.0
  INCD.0
  LDA.0
  SETD.1 Shape
  STA.1

  SETD.0 ShapeLength
  LDB.1
shapeStep:
  BRB shapeGot
  INCD.0
  DECB
  BRI shapeStep
shapeGot:
  LDA.0
  SETD.1 Length
  STA.1

  ; The rest of its bytes. The first one is already read.
  SETD.0 InstrBytes
  SETD.1 Opcode
  LDA.1
  STA.0
  INCD.0
  SETD.1 Length
  LDB.1
  DECB
readRest:
  BRB readRestDone
  PSHB
  CALL takeByte
  POPB
  MVQA
  STA.0
  INCD.0
  DECB
  BRI readRest
readRestDone:

  ; Show them, padded out so that what follows lines up however long the instruction was.
  SETD.0 InstrBytes
  SETD.1 Length
  LDB.1
showBytes:
  PSHB
  LDA.0
  CALL printByteHex
  INIA 0x20
  OUTA 0x00
  POPB
  INCD.0
  DECB
  BNB showBytes

  INIB 0d4
  SETD.0 Length
  LDA.0
padBytes:
  CCF
  SUB
  BRQ padDone               ; As many as there are, so nothing to pad.
  PSHA
  PSHB
  INIA 0x20
  OUTA 0x00
  OUTA 0x00
  OUTA 0x00
  POPB
  POPA
  DECB
  BRI padBytes
padDone:
  INIA 0x20
  OUTA 0x00

  ; Its name, without the spaces it is padded to four with.
  PSHD.3
  POPD.0
  DPUP.0 0d02
  INIB 0d4
showName:
  LDA.0
  BRA showNameDone
  PSHB
  INIB 0x20
  XOR
  POPB
  BRQ showNameDone
  OUTA 0x00
  INCD.0
  DECB
  BNB showName
showNameDone:

  ; And whatever follows it, which depends only on the shape.
  SETD.0 Shape
  LDA.0
  BRA showOperandNone       ; 0, nothing at all

  DECA
  BRA showAddress           ; 1, an address
  DECA
  BRA showByte              ; 2, one byte
  DECA
  BRA showSelector          ; 3, a Data Pointer
  DECA
  BRA showSelectorByte      ; 4, a Data Pointer and a byte
  DECA
  BRA showSelectorAddress   ; 5, a Data Pointer and an address
  BRI showTwoSelectors      ; 6

showOperandNone:
  CALL newLine
  RET

showAddress:
  INIA 0x20
  OUTA 0x00
  SETD.0 InstrBytes
  INCD.0
  LDA.0
  CALL printByteHex
  INCD.0
  LDA.0
  CALL printByteHex
  CALL newLine
  RET

showByte:
  INIA 0x20
  OUTA 0x00
  SETD.0 InstrBytes
  INCD.0
  LDA.0
  CALL printByteHex
  CALL newLine
  RET

showSelector:
  CALL putSelectorOne
  CALL newLine
  RET

showSelectorByte:
  CALL putSelectorOne
  INIA 0x20
  OUTA 0x00
  SETD.0 InstrBytes
  DPUP.0 0d02
  LDA.0
  CALL printByteHex
  CALL newLine
  RET

showSelectorAddress:
  CALL putSelectorOne
  INIA 0x20
  OUTA 0x00
  SETD.0 InstrBytes
  DPUP.0 0d02
  LDA.0
  CALL printByteHex
  INCD.0
  LDA.0
  CALL printByteHex
  CALL newLine
  RET

showTwoSelectors:
  CALL putSelectorOne
  INIA 0d46                 ; .
  OUTA 0x00
  SETD.0 InstrBytes
  DPUP.0 0d02
  LDA.0
  CALL printDecimalDigit
  CALL newLine
  RET

; ".n" for the selector that follows the opcode.
putSelectorOne:
  INIA 0d46
  OUTA 0x00
  SETD.0 InstrBytes
  INCD.0
  LDA.0
  CALL printDecimalDigit
  RET

; A byte that decodes as nothing. Shown as it is, and the cursor moves on by one, because
; the only honest thing to do with a byte that is not an instruction is say so and carry on.
showUnknown:
  SETD.0 Opcode
  LDA.0
  CALL printByteHex
  SETD.0 UnknownText
  SWI osPrintString
  RET

; Looks the opcode up. DP3 lands on its entry and Q is zero, or Q is not zero and it is not
; an instruction at all.
findInstruction:
  SETD.3 Instructions
  SETD.0 InstructionCount
  LDB.0
findStep:
  LDA.3
  SETD.0 Opcode
  PSHB
  LDB.0
  XOR
  POPB
  BRQ findFound
  DPUP.3 0d07
  DECB
  BNB findStep
  RSTA
  INIB 0d1
  CCF
  ADD
  RET
findFound:
  RSTA
  RSTB
  CCF
  ADD
  RET


; ---- Assembling a line at a time ----
;
; a <address>, then instructions until a line that is just a dot. The syntax is the
; assembler's - a selector rides on the mnemonic as LDA.0 or LDD.0.1, and leaving one off
; means Data Pointer 0, exactly as it does in a source file - so nothing learned here has to
; be unlearned when writing a real program.
;
; NUMBERS ARE HEXADECIMAL AND BARE. A source file writes 0x2000 or 0d16 because it has both
; and must say which; a monitor has only one and says so once, in the manual, rather than on
; every line. It is the same reason x and d take bare addresses.
;
; What cannot be written here is a label, and that is the whole difference between this and
; the assembler proper: a label is a promise to fill an address in later, and later is what
; a line at a time does not have.

doAssemble:
  SETD.1 TextRest
  LDD.0.1
  CALL textHexWord
  BNQ assembleWhat
  SETD.0 TextValue
  SETD.1 DumpAt
  CALL sbfsCopyWord     ; Two bytes from DP0 to DP1, which sbfs already has.

assembleLine:
  SETD.0 DumpAt
  CALL printWordHex
  SETD.0 AsmPrompt
  CALL printString

  SETD.0 AsmLine
  INIB 0d40
  CALL readLine

  INA 0x01
  INIB 0x02                 ; ENDED, so there is nothing more to assemble.
  AND
  BNQ prompt

  SETD.0 AsmLine
  LDA.0
  BRA assembleLine          ; An empty line is somebody thinking.

  SETD.0 AsmLine
  SETD.1 DotText
  CALL textSame
  BRQ prompt

  SETD.0 AsmLine
  CALL textSplit            ; The mnemonic, and whatever follows it.
  CALL assembleOne
  BRI assembleLine

assembleWhat:
  SETD.0 AsmUsage
  CALL printString
  CALL newLine
  BRI prompt

; The mnemonic is in CommandLine's place - AsmLine - and TextRest is what followed it.
; Puts the bytes down and steps the cursor past them.
assembleOne:
  CALL takeMnemonic
  CALL findByName
  BNQ assembleUnknown

  ; WHATEVER IT NEEDS IS READ BEFORE ANYTHING IS WRITTEN. Emitting the opcode first and
  ; discovering the missing value afterwards leaves half an instruction in memory, which the
  ; next line usually covers up and the last line of a session does not.
  SETD.0 AsmShape
  LDA.0
  BRA assemblePut           ; 0, nothing to read.
  DECA
  BRA assembleWantAddress   ; 1
  DECA
  BRA assembleWantByte      ; 2
  DECA
  BRA assemblePut           ; 3, a selector and nothing else.
  DECA
  BRA assembleWantByte      ; 4
  DECA
  BRA assembleWantAddress   ; 5
  BRI assemblePut           ; 6, two selectors.

assembleWantByte:
  SETD.1 TextRest
  LDD.0.1
  CALL textHexWord
  BNQ assembleNeedsValue
  BRI assemblePut

assembleWantAddress:
  SETD.1 TextRest
  LDD.0.1
  CALL textHexWord
  BNQ assembleNeedsValue

assemblePut:
  ; Point the controller at the cursor. Every byte written steps it on by itself.
  SETD.0 DumpBank
  LDA.0
  OUTA 0xE3
  SETD.0 DumpAt
  LDA.0
  OUTA 0xE4
  INCD.0
  LDA.0
  OUTA 0xE5

  SETD.0 AsmOpcode
  LDA.0
  OUTA 0xE9

  ; What follows depends only on the shape, exactly as it does when reading one back.
  SETD.0 AsmShape
  LDA.0
  BRA assembleDone          ; 0
  DECA
  BRA assembleAddress       ; 1
  DECA
  BRA assembleByte          ; 2
  DECA
  BRA assembleSelector      ; 3
  DECA
  BRA assembleSelByte       ; 4
  DECA
  BRA assembleSelAddress    ; 5

  SETD.0 AsmSelOne
  LDA.0
  OUTA 0xE9
  SETD.0 AsmSelTwo
  LDA.0
  OUTA 0xE9
  BRI assembleDone

assembleSelector:
  SETD.0 AsmSelOne
  LDA.0
  OUTA 0xE9
  BRI assembleDone

assembleSelByte:
  SETD.0 AsmSelOne
  LDA.0
  OUTA 0xE9
  BRI assembleByte

assembleSelAddress:
  SETD.0 AsmSelOne
  LDA.0
  OUTA 0xE9
  BRI assembleAddress

assembleByte:
  SETD.0 TextValue
  INCD.0
  LDA.0
  OUTA 0xE9
  BRI assembleDone

assembleAddress:
  SETD.0 TextValue
  LDA.0
  OUTA 0xE9
  INCD.0
  LDA.0
  OUTA 0xE9

assembleDone:
  ; Past what was just written. The length is the shape's, out of the same table the
  ; disassembler reads, so the two can never disagree about how much room one takes.
  SETD.0 ShapeLength
  SETD.1 AsmShape
  LDB.1
assembleStep:
  BRB assembleStepped
  INCD.0
  DECB
  BRI assembleStep
assembleStepped:
  LDA.0
  SETD.0 DumpAt
  CALL stepCursor
  RET

assembleUnknown:
  SETD.0 NoSuchOp
  CALL printString
  CALL newLine
  RET

assembleNeedsValue:
  SETD.0 NeedsValue
  CALL printString
  CALL newLine
  RET

; DP0 is a two byte address and A is how far to move it on.
stepCursor:
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

; The typed mnemonic into four padded characters and up to two selectors, which is the shape
; the table holds. Folded to upper case, because the assembler does not care about the case
; of a mnemonic and neither should this.
;
; A selector that was not typed is Data Pointer 0, exactly as an omitted one means in a
; source file. That is worth matching rather than demanding: half the instruction set names
; a pointer, and most code only ever uses the first.
takeMnemonic:
  RSTA
  SETD.1 AsmSelOne
  STA.1
  SETD.1 AsmSelTwo
  STA.1
  INIA 0d4
  SETD.1 AsmLeft
  STA.1

  SETD.0 AsmLine
  SETD.1 AsmName

takeMnemonicChar:
  SETD.2 AsmLeft
  LDA.2
  BRA takeMnemonicPad       ; Four is as long as a mnemonic gets.
  LDA.0
  BRA takeMnemonicPad       ; The word ended.
  INIB 0d46                 ; A dot, so the selectors start here.
  XOR
  BRQ takeMnemonicPad

  ; Nothing below compares against A, so it survives all of this and is stored at the end.
  INIB 0d97                 ; a
  CCF
  SUB
  BRC takeMnemonicPut       ; It borrowed, so this is below 'a'.
  INIB 0d123                ; One past z.
  CCF
  SUB
  BNC takeMnemonicPut       ; No borrow, so it is 'z' or later.
  INIB 0x20
  CCF
  SUB
  MVQA                      ; Upper case, which is how the table holds them.

takeMnemonicPut:
  STA.1
  INCD.0
  INCD.1
  SETD.2 AsmLeft
  LDA.2
  DECA
  STA.2
  BRI takeMnemonicChar

takeMnemonicPad:
  SETD.2 AsmLeft
  LDA.2
  BRA takeMnemonicSelectors
  INIA 0x20
  STA.1
  INCD.1
  SETD.2 AsmLeft
  LDA.2
  DECA
  STA.2
  BRI takeMnemonicPad

takeMnemonicSelectors:
  RSTA
  STA.1                     ; The four are a string now, like the ones in the table.

  LDA.0
  INIB 0d46
  XOR
  BNQ takeMnemonicEnd       ; No dot, so both selectors stay at nought.
  INCD.0
  LDA.0
  INIB 0d48
  CCF
  SUB
  MVQA
  SETD.1 AsmSelOne
  STA.1

  INCD.0
  LDA.0
  INIB 0d46
  XOR
  BNQ takeMnemonicEnd
  INCD.0
  LDA.0
  INIB 0d48
  CCF
  SUB
  MVQA
  SETD.1 AsmSelTwo
  STA.1

takeMnemonicEnd:
  RET

; Looks the four characters up. AsmOpcode and AsmShape are filled in and Q is zero, or Q is
; not zero and there is no such instruction.
;
; The same table the disassembler reads, searched the other way round. That is the point of
; it being a table rather than two lists: what can be written can be read back, and what can
; be read back can be written, and neither can drift from the other.
findByName:
  SETD.3 Instructions
  SETD.0 InstructionCount
  LDA.0
  SETD.1 AsmLeft
  STA.1

findByNameStep:
  PSHD.3
  POPD.0
  DPUP.0 0d02
  SETD.2 AsmName
  INIA 0d4
  SETD.1 AsmCount
  STA.1

findByNameChar:
  LDA.0
  LDB.2
  XOR
  BNQ findByNameNext
  INCD.0
  INCD.2
  SETD.1 AsmCount
  LDA.1
  DECA
  STA.1
  BNA findByNameChar

  PSHD.3
  POPD.0
  LDA.0
  SETD.1 AsmOpcode
  STA.1
  PSHD.3
  POPD.0
  INCD.0
  LDA.0
  SETD.1 AsmShape
  STA.1
  RSTA
  RSTB
  CCF
  ADD
  RET

findByNameNext:
  DPUP.3 0d07
  SETD.1 AsmLeft
  LDA.1
  DECA
  STA.1
  BNA findByNameStep
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Is there such a bank? Q is zero if there is not.
;
; ASKING THE CONTROLLER FOR A BANK THAT IS NOT THERE IS REFUSED, and a refusal nobody
; catches stops the machine, which is a wretched answer to a mistyped number. The bank table
; says what exists, and it lives in bank 2.
;
; Bank n's record starts at n times eight. A and B are a shift register sixteen bits wide,
; so putting the number in the low half and rotating left three times multiplies it by
; eight without anything falling off the top: the most it can reach is 2040.
bankPresent:
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
  SETD.0 BankFlags
  STA.0                 ; Kept whole, since present is not the only thing it says.
  INIB 0x01
  AND
  RET

; ---- help ----

doHelp:
  SETD.0 HelpText
  CALL printString
  CALL newLine
  SETD.0 HelpMoreText
  CALL printString
  CALL newLine

  ; And what the monitor adds, but only when it is on. Listing commands that would not
  ; answer is a way of teaching somebody something untrue.
  SETD.0 Mode
  LDA.0
  BRA prompt
  SETD.0 MonitorHelp
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
FileText:
" file"

; Two strings rather than one, because a string literal stops at 255 characters and each
; one carries its own zero byte, so they are printed in turn rather than joined.
HelpText:
"dir          list what is on the disk
load <file>  read a program off the disk
run [words]  start what was loaded, and tell it those words
delete <file>        take it off the disk
rename <file> <to>   call it something else"
HelpMoreText:
"monitor      look at memory, change it, and jump into it
help         this
exit         stop, or leave the monitor if you are in it"

ExamineUsage:
"x <address>, or x on its own to carry on"
NoSuchBank:
"there is no such bank"
ProgramWord:
"program"
DataWord:
"data"

ExecMagic:
"SBEX"
LoadWhat:
"load what?"
NoSuchFile:
"no such file"
Deleted:
"gone"
Renamed:
"renamed"
DeleteWhat:
"delete what?"
RenameWhat:
"rename what to what?"
RenameNo:
"there is no such file, or that name is taken"
TooManyVectors:
"that program wants more vectors than there is room for"
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

BreakText:
"break at "
ARegText:
"A "
BRegText:
"B "
QRegText:
"Q "
SRegText:
"status "
DP0Text:
"DP0 "
DP1Text:
"DP1 "
DP2Text:
"DP2 "
DP3Text:
"DP3 "
SPText:
"SP "
CarryText:
"carry "
FaultText:
"fault "
IntsText:
"interrupts "
ResumeText:
"press a key "
MonitorPrompt:
"* "
UnknownText:
"       ?
"
MonitorName:
"monitor"
MonitorHelp:
"x examine, d disassemble, a assemble, s set, b bank, g go, exit leaves"
ExamineName:
"x"
DisName:
"d"
SetName:
"s"
BankName:
"b"
GoName:
"g"
BankUsage:
"b <program|data|number>"
BankIs:
"bank "
SetUsage:
"s <address> <byte> <byte> ..."
ReadOnlyText:
"that bank will not be written"
GoUsage:
"g <address>"
AsmName2:
"a"
AsmPrompt:
": "
DotText:
"."
AsmUsage:
"a <address>, then instructions, then a dot"
NoSuchOp:
"no such instruction"
NeedsValue:
"that one needs a value after it"
DirName:
"dir"
LoadName:
"load"
RunName:
"run"
DeleteName:
"delete"
RenameName:
"rename"
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
LoadVersion:
  0x00

; Where the first of rename's two names is, kept while the second is picked out of the
; line, since finding that needs the pointers for itself.
RenameFrom:
  0x00 0x00

; What followed "run", kept for the program to ask for.
RunArgument:
  #Reserve 0d64

; A number on its way to being printed, since the routine that prints one wants it in
; memory and a service is handed it in registers.
PrintNumber:
  0x00 0x00

; ---- The vectors a loaded program brought with it ----
;
; Six bytes each: where it goes, what goes there, and what was there before. The last two
; are filled in when the program runs and read back when it exits, so what a program covers
; up comes back rather than becoming a hole.
;
; Sixteen is a limit rather than a considered number. It is far more than anything written
; so far wants, and a program asking for more is refused at load rather than having some of
; its handlers installed and the rest dropped.
VectorSource:
  0x00 0x00
VectorsLeft:
  0x00
LoadedVectorCount:
  0x00
LoadedVectors:
  #Reserve 0d96

; Where the monitor is looking, so that a bare 'dump' can carry on from it.
DumpBank:
  0x00
DumpAt:
  0x00 0x00
DumpRows:
  0x00
Mode:
  0x00
DumpCount:
  0x00
BankWas:
  0x00
BankFlags:
  0x00
AsmSelOne:
  0x00
AsmSelTwo:
  0x00
AsmLeft:
  0x00
AsmCount:
  0x00
AsmOpcode:
  0x00
AsmShape:
  0x00
AsmName:
  #Reserve 0d5
AsmLine:
  #Reserve 0d41
ShowAsCode:
  0x00
DumpRecord:
  0x00 0x00
Opcode:
  0x00
Shape:
  0x00
Length:
  0x00
InstrBytes:
  #Reserve 0d4

; How many bytes an instruction of each shape runs to, the opcode included.
ShapeLength:
  0d1 0d3 0d2 0d2 0d3 0d4 0d3

InstructionCount:
  0d64

; ---- The instruction table ----
;
; Generated by Tests/instructiontable.py from the assembler's own list, and checked against
; it by Tests/docs.sh. Seven bytes each: the opcode, the shape, and four characters of name
; with the zero the assembler puts after a string.
Instructions:
  0x00 0d0 "ADD "
  0x01 0d0 "SUB "
  0x02 0d0 "AND "
  0x03 0d0 "OR  "
  0x04 0d0 "XOR "
  0x05 0d0 "NOTA"
  0x06 0d0 "NOTB"
  0x07 0d0 "SHL "
  0x08 0d0 "SHR "
  0x10 0d1 "BRI "
  0x11 0d1 "BRQ "
  0x12 0d1 "BRA "
  0x13 0d1 "BRB "
  0x14 0d1 "BRC "
  0x15 0d3 "BRD "
  0x1A 0d1 "BNQ "
  0x1B 0d1 "BNA "
  0x1C 0d1 "BNB "
  0x1D 0d1 "BNC "
  0x17 0d1 "CALL"
  0x18 0d2 "SWI "
  0x19 0d0 "RETI"
  0x1F 0d0 "RET "
  0x20 0d0 "RSTA"
  0x21 0d0 "RSTB"
  0x22 0d0 "INCA"
  0x23 0d0 "INCB"
  0x24 0d0 "DECA"
  0x25 0d0 "DECB"
  0x26 0d2 "INIA"
  0x27 0d2 "INIB"
  0x28 0d0 "CCF "
  0x29 0d0 "MVQA"
  0x2A 0d0 "MVQB"
  0x2B 0d0 "SIF "
  0x2C 0d0 "CIF "
  0x30 0d0 "PSHQ"
  0x31 0d0 "PSHA"
  0x32 0d0 "PSHB"
  0x33 0d3 "PSHD"
  0x34 0d0 "POPA"
  0x35 0d0 "POPB"
  0x36 0d3 "POPD"
  0x40 0d3 "INCD"
  0x41 0d3 "DECD"
  0x42 0d3 "LDA "
  0x43 0d3 "LDB "
  0x44 0d3 "STQ "
  0x45 0d3 "STA "
  0x46 0d3 "STB "
  0x47 0d5 "SETD"
  0x48 0d4 "DPUP"
  0x49 0d4 "DPDN"
  0x4A 0d6 "LDD "
  0x4B 0d6 "STD "
  0x4C 0d3 "MVSD"
  0x4D 0d3 "MVDS"
  0xD0 0d2 "OUTQ"
  0xD1 0d2 "OUTA"
  0xD2 0d2 "OUTB"
  0xE0 0d2 "INA "
  0xE1 0d2 "INB "
  0xF0 0d0 "NOP "
  0xFF 0d0 "HALT"
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
  osArgument     handleArgument
  osFileRead     handleFileRead
  osFileSave     handleFileSave
  osFileDelete   handleFileDelete
  osFileRename   handleFileRename
  osPrintNumber  handlePrintNumber
  osBreak        handleBreak
  Device 0x20    diskDone
