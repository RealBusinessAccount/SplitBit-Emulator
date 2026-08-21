# CosmOS

## Overview:
CosmOS is a small, single-tasking disk operating environment for the SplitBit 8-bit
computer. It boots the machine, finds and mounts an SBFS filesystem, provides a command
line and memory monitor, loads applications from disk, and takes control back when they
finish.

CosmOS is written entirely in SplitBit assembly. It is closer in scale and purpose to a
resident monitor or an early disk operating system than to a modern multitasking OS: one
program owns the machine at a time, there is no privilege boundary, and applications are
assembled for fixed regions of memory. What it provides is a stable home from which those
programs can be found, run, and given services without each one having to boot the machine
for itself.

### Features:
- Interactive Shell: Read commands from the SplitBit console and continue until `exit` or
  the end of input.
- SBFS Filesystem: Mount, list, read, write, delete, and rename files on a SplitBit disk.
- Loadable Applications: Validate SBEX files, copy their Program and Data segments into
  the addresses for which they were assembled, and start them at their declared entry
  point.
- Resident Services: Applications can print strings and numbers, read lines, receive their
  command arguments, read and write files, and return to the shell through named software
  interrupts.
- Application Vectors: Install interrupt vectors carried by a loadable program and
  restore whatever they replaced when the program exits.
- Stack Reclamation: Save the system Stack before launching an application and take it
  back on exit, so an application need not unwind itself before returning.
- Memory Monitor: Inspect and modify Program Memory, Data Memory, and registered
  device-memory banks through the SplitBit memory controller, disassemble instructions,
  and begin execution at an address.
- Hardware Discovery: Mount the disk through the device registry rather than assuming
  that one is present at a particular controller bank.
- Native Applications: Includes demonstrations, mathematical programs, interactive
  programs, a game, and a line-oriented text editor.
- Reproducible Disk Image: The makefile assembles the system and every application, then
  constructs a fresh SBFS image containing the resulting executables.

## Building and Running:

CosmOS currently lives inside the SplitBit Emulator repository and uses its assembler,
emulator, and disk-image tool. From the repository root, build those tools first:

```sh
make
```

Then build CosmOS and all of its applications:

```sh
cd Programs
make cosmos
```

Build a fresh SBFS application disk as well:

```sh
make cosmos-disk
```

To boot CosmOS with that disk attached:

```sh
make run-cosmos
```

The generated files are kept under `Programs/build/`:

- `CosmOS/Source/cosmos.bin` is the bootable CosmOS image.
- `CosmOS/Apps/*.sbx` are loadable application images.
- `cosmos.img` is the SBFS disk containing those applications.

The disk is rebuilt from scratch when its applications change, so its contents describe
the current source tree rather than accumulating files left by older builds.

## Shell Commands:

CosmOS currently provides these built-in commands:

| Command | Description |
| -- | -- |
| `dir` | List the files on the mounted disk and their sizes. |
| `load <file>` | Read and validate an SBEX application, then place its code and data where its header requests. |
| `run [words]` | Start the loaded application and make the rest of the line available to it as an argument. |
| `delete <file>` | Remove a file from the filesystem and release its blocks. |
| `rename <file> <to>` | Give a file a different name without moving its contents. |
| `monitor` | Enter monitor mode, in which the prompt becomes `*` and the commands below are also available. |
| `help` | Show the built-in command summary. |
| `exit` | Leave monitor mode if in it, and otherwise halt the machine. |

Monitor mode adds the following. It is a mode rather than a separate program because a
loaded application occupies the one region a loaded application is given, so a monitor
which was itself an application could never examine another one. The mode persists: an
application started with `g` which returns through `osExit` arrives back at the monitor
prompt rather than at the shell.

| Command | Description |
| -- | -- |
| `x [address]` | Display 64 bytes as hexadecimal and as characters. |
| `d [address]` | Disassemble eight instructions. |
| `a <address>` | Assemble instructions into memory until a line containing only a dot. |
| `s <address> <byte>...` | Write bytes into the bank being examined, including Program Memory. |
| `b <program\|data\|bank>` | Select a memory space or a registered bank number. |
| `g <address>` | Begin execution at an address. |

`x` and `d` share a position, and each leaves it after what it displayed, so either may be
given without an address to continue from where the last one stopped.

For example:

```text
> dir
> load Snake.sbx
> run
```

Loading and running are separate operations for now. A loaded program may be run again
without being read from disk again, which is useful both as a monitor facility and as a
test that CosmOS correctly restores its Stack and vector table after every run.

CosmOS also boots without a disk. It reports that no filesystem was found, leaves the
shell and memory monitor available, and refuses commands that require a mounted disk
without stopping the machine.

## Included Applications:

`Programs/CosmOS/Apps` holds what the shell can load, and the application disk is built
from every assembly file in it. Several are old programs written for the bare machine that needed five edits each to become loadable ones - the Fibonacci and sieve programs, `greet`, and `hello`. The rest were written for the system as it is now, and each of those exists to show one thing working:

| Program | What it is for |
| --- | --- |
| Life | Conway's Game of Life, which had to be taught to stop, since a program that never ends takes the shell with it. Polls the console between generations. |
| Snake | A game. Draws a whole screen with cursor addressing and steers with single keys, asking the console once a frame and never waiting. |
| Keys | The console interrupting rather than being asked. The only one that brings a vector of its own, which is what the version two format exists for. |
| Say | Prints whatever it was told, which is the shortest thing that shows osArgument working. |
| Files | Writes a file, reads it back, renames it and deletes it, in 645 bytes, including nothing but the service names. It is what says a program does not need a filesystem inside it. |
| Break | Stops itself twice with SWI osBreak, so that the registers can be seen changing between one stop and the next. |
| Edit | A line editor. |
| Stream | Reads an 84,000 byte file through a buffer of 256, which is what says a file bigger than Data Memory can be read at all. |

### The Monitor:

The monitor is **part of the shell**, not a program the shell loads, and that is the whole reason it works. A loaded program occupies the one place a loaded program goes, so a monitor that was an application could never look at any other application: loading the thing you wanted to inspect would replace the thing doing the inspecting.

`monitor` turns it on and the prompt changes from `>` to `*`. It is **a mode, not a detour** - the shell's own commands still work, and the mode persists until you say otherwise:

```
> load Snake.sbx
> monitor
* d 2000
2000  47 00 11 00  SETD.0 1100
* b data
bank 01
* x 1000
* exit
> 
```

**A program giving the machine back lands at the prompt it was started from**, so `g` into something, letting it run, and having it exit puts you back at `*` rather than at the shell. That falls out of the mode being a variable the prompt reads rather than a second loop: every way back to the prompt goes through one place, including `osExit`. Looking at a program and running it therefore do not interrupt each other, which is the thing a monitor is for.

`exit` leaves whatever you are in - the monitor if you are in it, the machine if you are not.

| | |
| --- | --- |
| `x [addr]` | Sixty-four bytes, as hex and as characters |
| `d [addr]` | Eight instructions, disassembled |
| `a addr` | Assemble instructions, until a line that is just a dot |
| `s addr b b ...` | Put those bytes there |
| `b program\|data\|n` | Which bank to look at |
| `g addr` | Go there |

`a` writes the assembler's own syntax: a selector rides on the mnemonic as `LDA.0` or `LDD.0.1`, and leaving one off means Data Pointer 0 exactly as it does in a source file, so nothing learned at the monitor has to be unlearned when writing a program. Case does not matter, and the whole line is refused before anything is written, so a mistyped instruction leaves no half of itself behind.

```
* b data
* s 8100 68 65 6C 6C 6F 2C 20 74 79 70 65 64 0A 00
* b program
* a 8200
8200: SETD.0 8100
8204: SWI 10
8206: SWI 12
8208: .
* g 8200
hello, typed
```

A program and its data, both entered by hand, calling a system service and returning to the prompt they were written at. Note the two banks: instructions go into Program Memory and the string into Data Memory, because that is what a Harvard machine means and the monitor will not guess for you.

**Numbers here are hexadecimal and bare.** A source file writes `0x2000` or `0d16` because it has both and must say which; the monitor has one and says so once.

**What cannot be written is a label**, and that is the whole difference between this and the assembler proper. A label is a promise to fill an address in later, and later is what a line at a time does not have. It is also why the same instruction table serves both directions here: what `a` writes, `d` reads back, and neither can drift from the other or from the assembler they were generated from.

`x` and `d` share one cursor and each leaves it past what it showed, so without an address either carries on - reading through memory is one letter at a time, and you can switch between bytes and instructions without retyping where you are. `s` deliberately does not move it.

Everything else here does something; the monitor looks at what the others did. It shows memory as hex and as characters, disassembles it, writes bytes into it, and jumps to an address - all through the memory controller, which is the only thing that can reach Program Memory.

That is why a monitor is worth more on this machine than on most. Data Memory a program can already read for itself with a Data Pointer. The half it cannot see is Program Memory, and that is the half its bugs are in.

**Its instruction table is generated from the assembler's**, by `Tests/instructiontable.py`, and checked against it by `Tests/docs.sh` - along with a second check that the lengths that table implies are the ones the manual's own Bytes column prints. Both matter for the same reason: a disassembler that disagreed about how long an instruction is would not print one line wrong, it would lose its place and print everything after it wrong. Which is what a disassembler does anyway when it starts in the middle of an instruction, and is worth seeing once so it is recognised later.

**Where to put something you typed in yourself** is a question the monitor answers, because the answer moves every time the monitor is rebuilt. `m` says where its own two segments end, and those are the first free addresses:

```
> m
code from 2000, free from 2607
data from 1000, free from 1367 up to the stack
```

Which is what makes the monitor's real trick possible - a program that no assembler ever saw:

```
> s 8000 26 48 D1 00 26 49 D1 00 26 0A D1 00 18 12
> d 8000
8000  26 48        INIA 48
8002  D1 00        OUTA 00
8004  26 49        INIA 49
...
800C  18 12        SWI 12
> g 8000
HI
```

Typed in as bytes, checked by disassembling it back, and run. It ends with `SWI osExit`, which is how it gives the machine to the shell rather than to nothing.

There are no breakpoints yet, and `g` does not come back. The machinery for both already exists and nothing has used it: SplitBit has 192 undecodable bytes, and an invalid opcode dispatches through the `BadOpcode` vector carrying **the address of the offending byte**. A breakpoint is a spare byte written over an instruction and a handler waiting for it.

### The Editor:

`Edit` is the first program on this machine that makes a file a person typed - every byte on every disk before it was put there by the host tool. It is line oriented in the manner of `ed`: `l` lists, `a` adds at the end, `i` and `c` and `d` take a line number, `w` writes and `q` stops.

It includes nothing but `services.asm` and `text.asm`: the filesystem and the console are the system's, asked for rather than carried. That is what took it from 4,941 bytes to 1,983 without a line of its own logic changing - and the way that was checked is worth knowing, because the recorded output of the `cosmosEdit` test did not move by a single byte across the rewrite.

It keeps the document as a **linked list of lines** rather than one buffer with newlines in it. Each line says where the next one is, how long it is, and then its bytes. Inserting is two pointers changed and nothing moved; with a flat buffer it would mean shifting every byte after the edit, on a machine whose only block move is a device asked politely. The price is that deleted lines are not reused, so a heavy session uses more room than the document needs and writing it out is what tidies up.

Saving goes through `sbfsSaveFile`, so a document that has grown is written somewhere else and the original is only let go of once the new one is safely down. That is the whole reason the editor was written: not because the machine needed an editor, but because every tool that produces a file needs the same four operations, and building them for one imaginary tool is how they end up wrong.

These are ordinary SBEX files on SBFS. None of them is built into the operating system, and
a disk can be filled from either side: the host tool puts files on, and so does the machine,
which assembles its own now.

## The Application Model:

CosmOS divides the two SplitBit address spaces by convention:

| Memory | CosmOS | Loaded application |
| -- | -- | -- |
| Program Memory | `0x0000` through `0x1FFF` | `0x2000` and above |
| Data Memory | `0x0000` through `0x0FFF` | `0x1000` and above |

Applications state their actual Program and Data addresses with `#Base`. The SplitBit
assembler then writes an SBEX loadable image containing those addresses, the entry point,
the segment lengths, and any vectors the application needs. CosmOS does not relocate
code: the addresses in the file must be the addresses for which it was assembled.

This division is an ABI convention rather than protection. An application owns the
machine while it runs and may address hardware or CosmOS memory directly. The convention
keeps independently assembled software out of the system's way; it is not a security
boundary.

### System Services:

Applications include `Source/services.asm` to obtain stable names and vector numbers for
the services CosmOS provides. Neither side ever types a number: the file both of them
include is the only place any of them is written down. What each service is and what it
answers in is set out under "What A Program May Ask The System For".

The largest application CosmOS has is the assembler in `Programs/CosmOS/Assembler/`. It
travels with CosmOS rather than with the emulator, for the same reason the C assembler
travels with the emulator: it is part of the system it was written for.

A minimal CosmOS application therefore looks like this:

```asm
#Include services.asm

#Program
  #Base 0x2000

start:
  SETD.0 Message
  SWI osPrintString
  SWI osExit

#Data
  #Base 0x1000

Message:
  "Hello from CosmOS."
```

An application may also include its own libraries or access hardware ports directly.
The services are an interface offered by the system, not the only way software is allowed
to use the computer.

## What A Program May Ask The System For:

A loaded program is on its own hardware and can do anything the machine can do - it is a fence, not a wall. But the things it usually wants are things the system is already doing, and asking is both shorter and the only way to reach code that was assembled separately. `CALL` needs a label, and a label has to be in the same assembly; `SWI` needs only a number both sides agree on.

Those numbers are written down once, in `Programs/CosmOS/Source/services.asm`, which both the system and the program include. Neither side ever types a number.

| Service | Does |
| --- | --- |
| osPrintString | DP0 names a string ending in a zero byte. Prints it. |
| osReadLine | DP0 names somewhere to put a line, B says how much room there is. Reads one from the console. Q comes back holding how long it was. |
| osExit | Gives the machine back. Does not return. |
| osArgument | DP0 names somewhere to put whatever followed the run command, B says how much room there is. |
| osFileRead | DP0 names a file, DP1 says where to put it. Q is zero if it read, and DP3 comes back holding how many bytes there were. |
| osFileSave | DP0 names a file, DP1 is the bytes, A and B together are how many. Q is zero if it saved, whether or not it was there before. |
| osFileDelete | DP0 names a file. Q is zero if it went. |
| osFileRename | DP0 is the name a file has, DP1 the name it should have. Q is zero if it moved. |
| osFileInfo | DP0 names a file. Q is zero if it is there, and DP3 comes back holding how many blocks it occupies. |
| osFileBlock | DP0 names a file, DP1 says where to put a block of it, A and B together are which block counting from zero. Q is zero if it read, and DP3 comes back holding how many of the block's bytes belong to the file. |
| osPrintNumber | A and B together are a number. Prints it in decimal, without leading zeroes. |
| osBreak | Stops the program, shows every register as it had them, waits for a key, and carries on. |

```
#Include services.asm
  ...
  SETD.0 Message
  SWI osPrintString
```

### Stopping To Look:

`SWI osBreak` is a breakpoint. It shows every register as the program had them, waits for a key, and returns as though nothing happened.

```
break at 200E
A 11 B 22 Q 00 status 00
DP0 1030 DP1 05EF DP2 039A DP3 2000 SP FFFF
press a key
```

Every value comes out of the interrupt frame rather than out of the registers, because by the time the handler runs the registers belong to the handler. The frame is what the program had and what RETI is about to give back, so what is shown is what will be resumed with. The address is two before where it resumes: the `SWI` and the vector it names.

**The Stack Pointer is the exception, because it is not in the frame** - the frame is *where* the Stack Pointer is. What the program had is fourteen bytes above the frame, that being what entering an interrupt puts down, so it is worked out rather than read. Breaking inside a subroutine shows it ten lower than breaking outside one, which is the size of a CALL frame and a quick way to see how deep you are.

The status byte is shown as a number and then as the bits that are up - `carry`, `fault`, `interrupts` - because a dump that makes you look the number up is only half a dump.

**Nothing is overwritten, and that is the whole of why it is simple.** A breakpoint poked into a running program has to replace an instruction, and putting that instruction back in order to continue is the same act as disarming the breakpoint. Firing a second time would mean stepping over the restored instruction and putting the breakpoint back behind it, and this machine has no way to step a single instruction. Two bytes of `SWI` cost a little space and fire for ever, because there was never anything to restore.

The price is that a breakpoint is part of the program. A build with breakpoints in it has different addresses from a build without - the same bargain every machine makes that has a break instruction.

### The Disk Without A Filesystem:

A program that wants a file does not need to know what a filesystem is. Before these existed it had to include the whole of `sbfs.asm` - two and a half kilobytes of a private copy of code the system already had running - and then mount a disk that was already mounted.

There is no service to mount one, and that is not an omission. The system mounts the disk before it reads its first prompt, and there is one disk with one buffer registered as one bank; a program mounting it again was only ever an artefact of owning a second copy of the library. That call disappears rather than moving.

Sizes fit the registers exactly, in both directions. A file that can be read into Data Memory is under 64K by definition, so its length is sixteen bits: coming back it is DP3, and going out it is A and B together. Neither direction needs a record in memory whose shape both sides have to agree on.

A file of 256 blocks or more is refused by `osFileRead` rather than partly read, because 64K will not fit in Data Memory and its length will not fit in the pointer that reports it. A length that lies would be worse than a file that will not open.

### Reading A File That Will Not Fit:

`osFileRead` hands over a whole file, which settles the question for anything under 64K and settles nothing above it. CosmOS's own source is above it: the sources together are a hundred kilobytes and Data Memory is sixty four. A machine that is one day going to assemble itself has to be able to read a file bigger than its memory.

So there is a second way to ask. `osFileInfo` says how big something is and `osFileBlock` hands over one block of it, and between them a program reads a file of any size through a buffer of 256 bytes.

```
  SETD.0 Name
  SWI osFileInfo            ; DP3 is how many blocks, Q is zero if it is there.
  BNQ noSuchFile

readLoop:
  SETD.0 Name
  SETD.1 Block
  SETD.2 Index
  LDA.2
  INCD.2
  LDB.2                     ; Which block, most significant first.
  SWI osFileBlock
  BNQ readDone              ; Three when there are no more.
  ...                       ; DP3 is how many of its bytes are the file's.
```

**There is no open and no close.** Every call names the file and says which block it wants, so nothing is held between them: a program that stops halfway leaves nothing behind, and there is no handle to run out of. The system does remember where the last file it was asked about lives, so reading four hundred blocks searches the directory once rather than four hundred times - but that is a speed and not a promise, and a caller never has to know about it.

`osFileInfo` answers in **blocks rather than bytes**, and that is forced rather than chosen. A file on a sixteen megabyte disk can be twenty four bits long and a Data Pointer holds sixteen. Blocks fit; the bytes in the last one come back from `osFileBlock` when the reader gets there.

`osFileBlock` answers a count in DP3 rather than in a register for the same kind of reason: every block but a short last one holds a whole **256** bytes, and 256 does not fit in a byte. A count that reported a full block as zero would make every reader treat the end of a file as a special case.

**These two say why when the answer is no**, which the other services do not. Everywhere else the only useful thing to do about a failure is to give up, so one value is enough. These exist to be asked questions with, and the difference between the answers is the answer:

| Q | Means |
| --- | --- |
| 0 | it worked |
| 1 | there is no disk |
| 2 | there is no file of that name |
| 3 | that block is past the end of the file |
| 4 | the disk would not read it |

Running off the end is how a reader finds out it has finished, so it gets an answer of its own rather than being reported as a disk that failed.

`Programs/CosmOS/Apps/Stream.asm` reads an 84,000 byte file through a 256 byte buffer, then reads a small file both ways - whole with `osFileRead` and streamed - and checks that the two agree.

`Programs/CosmOS/Apps/Files.asm` does the whole round trip - write, read, report, rename, delete - in 645 bytes, and includes nothing but the service names.

`osArgument` is how a program is told what it is for. Everything written before it did the same thing however it was started, which is fine for a program that greets you and no use to one that edits a named document. What arrives is the whole rest of the line, spaces and all, rather than a list of words: what counts as an argument is the program's business, and handing over what was typed is the system's.

A handler is entered with the caller's registers exactly as they were, because an interrupt frame is pushed rather than cleared. That is why a service can be given a pointer in DP0 and a count in B without any of it being copied anywhere first.

### How A Service Answers:

The same thing that makes an interrupt safe makes a service mute. RETI restores every register from the frame, so whatever a handler worked out is thrown away on the way out - which is exactly right for a device interrupting at a moment nobody chose, and useless for a service that was asked a question.

A service answers by **writing into its own frame**, over the saved register, and letting RETI put it back. MVSD copies the Stack Pointer into a Data Pointer and the frame sits just above it, so returning a byte in Q is three instructions:

```
answer:
  INIA 0d42
  MVSD.1
  DPUP.1 0d02           ; The saved Q. See the frame table under Interrupts.
  STA.1
  RETI
```

**Which registers a service may answer in is the convention CALL already has: Q and DP3.** A subroutine cannot hand back A, B or Data Pointers 0 to 2 because RET puts them back; a service *could* write over any of them and should not, for exactly the reason that list exists. A caller is entitled to find what it kept still there.

**Only the handler itself can do this.** The offsets are from wherever the Stack Pointer is, and a CALL moves it by ten - so a routine called by a handler that tried the same thing would be writing into its own return address. The poke belongs inline, next to the RETI.

A service that has nothing to say does nothing, and the caller's registers arrive back untouched. That is worth knowing from the other side too: a service cannot corrupt a register by accident, only by deciding to.

## The Filesystem Library:

The disk knows blocks and nothing else, so a filesystem is software. Programs/CosmOS/Source/sbfs.asm is one.

| Routine | Does |
| --- | --- |
| sbfsMount | Registers the disk's buffer as bank 3, reads the superblock, and checks the disk is one of ours. Q is zero if it is. |
| sbfsFind | DP0 names a file, ending in a zero byte. Q is zero if it was found, and then SbfsFileStart, SbfsFileBlocks and SbfsFileTail describe it. |
| sbfsRead | Reads the file that was found into Data Memory at DP1. Q is zero if it worked. |
| sbfsFirst | Starts a walk through the directory. Q is zero if there is an entry, and then SbfsName holds its name and the SbfsFile fields describe it. |
| sbfsNext | Steps the walk to the next entry in use. Q is zero if there was one. |
| sbfsCreate | Makes a file. DP0 names it, and SbfsFileBlocks with SbfsFileTail say how big it is. Q is zero if it was made, and then SbfsFileStart says where it went. |
| sbfsWriteFile | Writes the file that was made, from Data Memory at DP1. |
| sbfsDelete | DP0 names a file. Frees its entry and its blocks. Q is zero if it went. |
| sbfsRename | DP0 is the name a file has, DP1 the name it should have. Q is zero if it was renamed. Refused if something already answers to the new name. |
| sbfsSaveFile | DP0 names the file, DP1 is the data, and SbfsFileBlocks with SbfsFileTail say how big it now is. Writes it whether or not it was there before, and whatever size it used to be. |

Finding a file and listing what is there are different jobs. sbfsFind searches for one name; sbfsFirst and sbfsNext walk the whole directory, stopping on each entry that is in use and stepping over the free ones. A walk keeps a directory block in SbfsBuffer between calls, so anything else that goes to the disk in the middle of one ends it: take what is wanted out of an entry before asking the disk for anything else.

A file's size is settled when it is made, because nothing can grow one afterwards. Files are laid down contiguously, so the block after a file usually belongs to somebody else. A program that does not know how much it will write has to guess high and accept the slack, or build its output elsewhere and make the file once the size is known.

### Saving Something Twice:

Which is why saving a document is not the same as writing a file, and why sbfsSaveFile exists rather than each tool doing it. A file that has grown will usually not fit where it was, so saving it means putting it somewhere else and letting go of where it was - and **the obvious order is a trap**:

```
  delete the old one
  make a new one          <- refused, and the old one is already gone
  write it
```

A create can be refused for want of a run long enough even on a disk with plenty of free blocks, because free blocks are only useful to a contiguous file when they are next to each other. Done in that order, the first fragmented disk somebody meets eats their work. sbfsSaveFile does it the other way round:

```
  make a temporary        nothing is lost if there is nowhere to put it
  write it
  delete the original     only now, once the new one is safely down
  rename the temporary
```

**That is what renaming is for.** It looks like a convenience and it is the safety mechanism: it is the only one of the three operations that moves no data - a name lives in the directory entry, so renaming writes twenty two bytes into one block - which makes it the only one that can be left until last and relied on not to fail.

Finding room is a walk through the directory rather than a lookup, because there is no allocation table. With files laid down contiguously the directory already says which blocks are spoken for, and a second copy of that would be a second thing to keep right. The free count in the superblock is kept up to date but it is a note rather than the truth: it can be worked out again from the directory, and the directory is the one to believe.

A file's length is its block count times 256 plus its tail, which is the same as putting the block count in the high byte and the tail in the low one. Nothing pads a file out, so the bytes after the end of one are whatever else happened to be in that block, and it is the reading program's business to stop where the tail says.

The other implementation of this format is SplitDisk, on the host. Nothing is shared between the two but the specification, so a change to either has to be a change to both.

### What A Subroutine Can And Cannot Hand Back:

This is the thing that catches people, including whoever wrote the last three pieces of system code, so it is worth stating once and plainly.

CALL saves **A, B, and Data Pointers 0, 1 and 2**, and RET puts all five back. So a subroutine cannot return anything in any of them: whatever it puts there is undone by its own return, silently, and the caller carries on with its old values as though the subroutine had never run.

What comes back is **Q**, which is one byte, and **Data Pointer 3**, which is two. That is the whole of it, and it is why DP3 is not preserved.

The same rule catches a loop that steps a pointer inside a subroutine. The step is thrown away every time round, so the loop reads the same byte forever and the fault is a wrong answer rather than a crash.

If two bytes have to come back and DP3 is spoken for, the honest answers are to write them into Data Memory, or to do the work in the caller rather than in a routine. A short sequence written out twice is better than a subroutine that quietly does nothing.

The same rule cuts the other way, which is easier to miss. Because DP3 is not put back, **a routine you call may leave something of its own in it**. It is where a routine hands a pointer out, so it is not a safe place to leave one of your own across a call to anything that might use it. The Stack is: push it before the call and pop it after, and it will be exactly as it was.

A label may only be defined once across a program and everything it includes, so a routine in one library cannot use a name that another has already taken.

## The Console Library:

Programs/CosmOS/Source/console.asm is the console library. It replaces print.asm, which was written for a machine with one Data Pointer and no vector table, and which is still there because the programs that include it still work.

| Routine | Does |
| --- | --- |
| newLine | Prints a line feed. |
| printString | DP0 names a string ending in a zero byte. Prints it. |
| printSpaces | A holds how many spaces to print. None is a fair answer, and prints nothing. |
| printByteHex | A holds a byte. Prints it as two hexadecimal digits. |
| printWordHex | DP0 names two bytes, most significant first. Prints them as four hexadecimal digits. |
| printHexDigit | A holds a nybble. Prints the one character that stands for it. |
| printDecimalDigit | A holds a digit from zero to nine. Prints it. |
| printByteDecimal | A holds a byte. Prints it in decimal, without leading zeroes. |
| printWordDecimal | DP0 names two bytes, most significant first. Prints them in decimal, without leading zeroes. |
| readLine | DP0 names a buffer and B says how many characters it holds. Reads a line into it. Q is how long the line turned out to be. |

Two things about it are different from the old library, and both are deliberate.

There is no branch at the top. print.asm begins with a BRI to a label called start, so that a program including it arrives at its own entry point rather than falling into the library. That was the only way to do it before the Vector Table existed, and it is why print.asm cannot be assembled on its own: the label it branches to is one only the including program defines. A program including console.asm says where it begins in its own Vector Segment instead, with a Boot line, and the library assembles by itself.

Every routine names the Data Pointer it works through rather than assuming there is only one. A pointer handed in is DP0, and nothing in the library disturbs DP3.

readLine cuts a line short if it is longer than the buffer, and then reads the rest of it and throws it away, so that what is left over does not turn up as the next line. ConsoleEndOfInput is set if the console ran out instead of ending a line, and it is cleared at the start of every call, so it always describes the last line read. That is a different thing from an empty line, and a program reading until there is no more has to be able to tell the two apart.

## Source Layout:

- `Source/cosmos.asm`: Boot process, shell, loader, monitor, system services, and
  application lifecycle.
- `Source/console.asm`: Console input, strings, hexadecimal and decimal output, and line
  handling.
- `Source/text.asm`: String comparison, splitting, and hexadecimal text conversion used
  by the shell.
- `Source/sbfs.asm`: Target-side implementation of the SplitBit filesystem.
- `Source/services.asm`: The shared names and stable vector numbers used by CosmOS and
  separately assembled applications.
- `Apps/`: Loadable programs packaged onto the CosmOS disk image.

## Tests:

CosmOS is exercised as part of the SplitBit repository's normal test suite:

```sh
make test
```

The tests boot the system with and without a disk and drive the shell through recorded
console input. They cover directory traversal, every loader refusal, repeated application
runs, memory inspection, vector installation and restoration, command arguments,
filesystem deletion and renaming, interactive applications, and editing a file followed
by reading the saved result back in a second editor session.

Individual CosmOS tests can be run from the repository root, for example:

```sh
./Tests/run.sh cosmos cosmosRun cosmosEdit
```

Test disks are constructed with the host-side `SplitDisk` tool. CosmOS is therefore
reading filesystems written by an independent implementation of the same format rather
than merely checking its filesystem code against itself.

## Current Scope:

CosmOS is early software for an experimental computer. It runs one application at a
time, has no privilege levels or process isolation, does not relocate applications, and
provides a line assembler but not yet a native assembler for source files, nor a linker. Its present purpose is to make
SplitBit usable from inside the machine: inspect it, manage persistent files, load
programs, provide common services, and return reliably to a command prompt.

The intended long-term milestone is self-hosting: editing SplitBit assembly source under
CosmOS, assembling and linking it natively, and eventually rebuilding CosmOS and its own
development tools on the machine.

## Additional Information:

The SplitBit Programming Manual describes the machine underneath: the CPU, the vector
table and interrupt model, devices, the memory controller, the console, and storage as a
block device. The SplitBit Assembler Manual documents the assembly language, the segment
bases and vector declarations, and the SBEX loadable program format.

What a program may ask CosmOS for is documented here rather than in either of those,
because the services are this system's and not the machine's.

## License:

CosmOS is part of the SplitBit Emulator project and is licensed under the Apache License,
Version 2.0. See the repository's top-level `LICENSE` file for the full license text.
