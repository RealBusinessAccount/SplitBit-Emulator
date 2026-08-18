# SplitBit Assembler Manual:

SplitBit assembly syntax is similar to many other assembler syntaxes. Whitespace at the start or end of a line is disregarded by the assembler and may be used to make programs more readable to the programmer. The Instruction Mnemonics are listed in the SplitBit Programming Manual, and the assembler is not case sensitive in regard to the mnemonics.

A semicolon, ';', denotes the start of a comment, anything beyond it on a line is disregarded by the assembler.

Special Keywords are denoted with hash marks, '#'. The Keywords are #Include, #Program, #Data, #Vectors, #Base, #Align, and #Reserve.

The first four say what kind of thing follows them. #Base says where a segment is loaded, and is described under Programs Meant To Be Loaded. #Align and #Reserve are instructions to the assembler in the middle of a segment, and are described under Moving The Cursor Along.

SplitBit programs must have a Program Segment. You define the start of a program with the #Program Keyword.
SplitBit programs may have a Data Segment. You may define the start of the data with the #Data Keyword.
SplitBit programs may have a Vector Segment. You define it with the #Vectors Keyword. See The Vector Segment below.

## Literal Values:

Literal values may be defined in a few ways. Numerical values must be within the range of a single 8 bit integer.
The assembler will accept:
- Hexadecimal values prefaced with 0x, eg. 0x00, 0x7F.
- Decimal values prefaced with 0d, eg. 0d0, 0d120, 0d255.
- Strings enclosed in double quotes, eg. "a", "Hello, World!", "It is dark, you are likely to be eaten by a grue."

Any token beginning with a '0' is read as a numerical literal, so a malformed one is an error rather than something the assembler tries to interpret as a label. This also means a label cannot begin with a '0'.

A string may be up to 255 characters. Each one is written down with a zero byte on the end, which is what lets a program find where it stops, and it means two strings written one after the other are not one longer string: there is a zero between them. A run of bytes longer than a string can hold has to be written as literals, or put there by the program itself while it runs.

**Strings belong in the Data Segment, and only there.** This is a Harvard machine: no instruction reads Program Memory, so a string put in the Program Segment could not be read by the program carrying it, and only the memory controller could reach it at all. The assembler refuses one rather than emitting bytes nothing can use. Single byte literals are a different matter and may go in either segment — a table of bytes a program branches through is a reasonable thing to want in Program Memory.

The one exception to the single byte rule is #Align and #Reserve, whose numbers are never emitted as bytes and may go up to 0xFFFF. See Moving The Cursor Along.

## Labels:

Labels may be a string of up to 32 alphanumeric characters that must end with a colon, ':'.

```
programStart:

loopStart:

errorHandler01:
```

A name may only be defined once across a program and everything it includes. Defining it twice is an error, because otherwise a reference resolves to whichever definition came first, and a typo or a name that two libraries both happen to use is very hard to track down.

A label may be referenced by name, without the colon, to place its two byte address wherever the reference appears.

In the Program Segment that is how the branch instructions and SETD are given somewhere to go. In the Data Segment it writes the address down as data, which is how a table of addresses is built for LDD to walk.

```
#Data

One:
"one"
Two:
"two"

Table:        ; Two entries, each the two byte address of a string above.
One
Two
```

## Naming a Data Pointer:

The instructions that work through a Data Pointer name which one by hanging a selector off the mnemonic, after a full stop.

```
  LDA.2       ; Load A through Data Pointer 2.
  STA.1       ; Store A through Data Pointer 1.
  INCD.2      ; Step Data Pointer 2 along.
  SETD.3 Grid ; Aim Data Pointer 3 at Grid.
```

Leave the selector off and the instruction uses Data Pointer 0, so a program that only needs one pointer never has to write one.

```
  LDA         ; Exactly the same as LDA.0
```

LDD and STD move a pointer through a pointer, so they take two selectors. The first names the pointer being moved and the second names the pointer that addresses it. Either may be left off, and again means Data Pointer 0.

```
  LDD.1.0     ; Data Pointer 1 becomes the address stored at Data Pointer 0.
  STD.1.0     ; Store Data Pointer 1 into the memory addressed by Data Pointer 0.
  LDD.2       ; Same as LDD.2.0
  LDD         ; Same as LDD.0.0, which makes DP0 follow the address it holds.
```

Writing a selector on an instruction that does not work through a Data Pointer is an error, as is naming a pointer the machine does not have, or giving an instruction more selectors than it takes.

## Instruction Operands:

Instructions that read operand bytes out of Program Memory must be followed by those operands. The branch instructions and CALL take a label; SETD takes a label or a pair of literal bytes; INIA, INIB, DPUP, DPDN, and the input and output instructions each take a single literal byte; SWI takes the name of a vector, or a literal number.

Leaving an operand off is an error rather than something the assembler works around, because the instruction would otherwise take whatever followed it as the operand and every address after that would shift.

Data Pointer selectors do not count as operands here, because they are written on the mnemonic rather than after it.

## Moving The Cursor Along:

Both segments are written from the beginning, and every label stands for wherever the cursor had reached when the assembler met it. Two directives move that cursor without you having to write zeroes by hand.

`#Align` puts down as many zero bytes as it takes to reach the next multiple of the number that follows it.

```
#Data

  #Align 0x100
Segment:              ; Guaranteed to begin at a page boundary.
```

This matters for code that does address arithmetic on a pointer's low byte and treats the carry out as reaching the end of something. Both prime sieves work that way, and both now ask for the boundary themselves. Before this existed they relied on print.asm padding its data out to a whole page, which worked but put the requirement in a different file from the code that needed it, and quietly charged every other program 253 bytes for it.

`#Reserve` puts down the number of zero bytes that follows it, so that a label can stand for a whole region rather than just its first byte.

```
#Data

Buffer:
  #Reserve 0d256      ; Anything after this begins 256 bytes further on.
Next:
```

Without it a label like Buffer is one byte as far as the assembler knows, so a later label lands inside the region and the two quietly overlap.

Both take a number written the way literals are, prefaced with 0x or 0d, but the number may go up to 0xFFFF rather than being held to a single byte. Neither number is ever emitted, so a byte's range would be the wrong limit: a page alignment needs 256, and a reservation is often much larger.

Both work in the Program Segment as well as the Data Segment, and both are an error anywhere else, because outside a segment there is no cursor to move.

## Programs Meant To Be Loaded:

A program assembled without saying anything about where it goes is a boot image. Both its segments begin at zero, which is where the machine puts them, and it is written out in the format the emulator loads.

A program that will be loaded by something else has to say where it belongs, because nothing relocates it. `#Base` says so, and it has to be the first thing in its segment:

```
#Program
  #Base 0x2000        ; This program's code lives from 0x2000.
start:
  ...

#Data
  #Base 0x1000        ; And its data from 0x1000.
Message:
"..."
```

Every label inside is then already the address it will have once the program is loaded, so a branch or a SETD written in it points at the right place. Giving either segment a base makes the whole program a loadable one, and the assembler writes it out with a header saying where its two pieces go, followed by the pieces themselves. The space below each base is not in the file: the header says where the bytes belong and the loader puts them there.

A program starts at its code base unless it says otherwise, and `Boot` in its Vector Segment is how it says otherwise:

```
#Program
  #Base 0x2000
helpers:
  ...
start:
  ...

#Vectors
  Boot  start           ; Which is where this program begins.
```

That fills in the entry point in the header. It is not installed as vector 0 of the machine, which is where everything begins at power on and no business of a program being loaded into a system that is already running.

### Vectors In A Loadable Program:

Everything else in a Vector Segment is carried in the file and installed by whatever loads the program. That is what lets a loaded program be interrupted: a handler is an address in the vector table, and until the format could carry one, a program that was not the one the machine booted from had no way to ask for it.

```
#Vectors
  Boot         start
  Device 0x00  keyHandler    ; The console, which now interrupts this program.
```

A program carrying vectors is written out as version two of the format, and the assembler says so:

```
  Vectors: 1. Version 2, so a loader that cannot install them will say so.
```

A program carrying none stays version one and loads anywhere. The difference matters because a loader that does not understand version two refuses the file rather than running a program with its handlers missing, which would work until the moment it was supposed to be interrupted and then fail somewhere with nothing pointing back at the cause.

Whoever loads the program is expected to take the vectors out again when it finishes. See the Programming Manual.

The address a program is assembled for has to be the address it is loaded at. Nothing checks that, and nothing can fix it: a program put anywhere else has every branch and every SETD inside it pointing somewhere wrong.

### Both Segments Or Neither:

Base one segment and the assembler expects a base on the other, if the other holds anything. Forgetting the second one is refused:

```
Error: The Program Segment is based at 0x2000, but the Data Segment
 has 3 bytes at 0x0000 and was never given a #Base.
 Half a program loaded at zero lands on whatever is already there.
```

This is worth refusing rather than allowing, because the result runs. The unbased half keeps the addresses it was given, which count up from zero, and the loader puts it exactly there, on top of whatever the system keeps at the bottom of memory. Nothing fails at load and nothing fails at the jump. It fails later, somewhere else, as corruption of something that never went near the program that caused it.

It is easy to do by accident. A segment can come from an included library rather than from the program itself, and a `#Data` that arrives with `#Include print.asm` is just as unbased as one you wrote, while being much harder to notice missing.

A program that genuinely wants a segment at the bottom of memory says so:

```
#Data
  #Base 0x0000        ; Meant, not forgotten.
```

`#Base` is the one directive that takes zero. `#Align` and `#Reserve` are counts, and a count of nothing is a typo, so they still require at least one.

## The Vector Segment:

A vector says where to go when something happens: the machine starting up, a program asking for a service, a device wanting attention, or the CPU meeting a byte it cannot decode. The Vector Segment says which of your routines belongs to which vector, and the assembler works out the rest.

A program does not need one. Without a Vector Segment a program starts at the beginning and behaves exactly as it always has.

Every line names a vector and then the label of the routine that handles it.

```
#Vectors

  Boot        realStart
  BadOpcode   reportFault
  openFile    openFileHandler
  Device 0x10 diskReady
```

A line with a name and nothing after it declares the name and its number without installing anything. That is what lets one file be included by both the program that provides a service and the program that calls it: the shared file names them, the provider follows it with handlers, and a program that only calls them says them by name without pretending to implement them.

```
; services.asm, included by both sides
#Vectors
  osPrint  0d16
  osExit   0d17
```

The numbers are there because this is the case where a number has to be agreed. Everything else in a Vector Segment is numbered by the assembler, which can only see one program at a time — and that is exactly the situation where it cannot help. See Numbers You Write Down below.

Five names already mean something:

| Name | Vector |
| --- | --- |
| Boot | Where the machine begins at power on. Without this a program starts at the beginning of its Program Segment. |
| SoftReset | A warm restart. SWI SoftReset is how a program asks for one. |
| BadOpcode | The CPU met a byte that is not an instruction. |
| GuardViolation | A device refused a write, because it landed inside a raised fence. |
| BankFault | A bank was named that has nothing in it, or an access ran past its end. |

Anything else you name is a software interrupt of your own. Usually you do not choose its number: the assembler allocates them in the order they appear, from vector 64 upwards. That is the same bargain as labels everywhere else in SplitBit assembly, where you name a thing and let the assembler work out where it went.

You then use the name as the operand of SWI:

```
  SWI openFile
```

A device is different, because its number is not a choice. A device interrupts on the port it is plugged into, so the Device line says which port rather than giving it a name of its own. The port is a literal value, and the routine after it handles that device.

The assembler will refuse two handlers for the same vector, a name used with SWI that no Vector Segment gives a handler to, and a handler that is not a label.

### Numbers You Write Down:

A vector number is worth arguing about in exactly one situation: when two programs that are **not assembled together** have to mean the same thing by a name. A program calling `osExit` was built long before, and separately from, whatever implements it. Nothing the assembler can see ties those two together, because it only ever sees one of them.

For that case a number may be written between the name and the handler.

```
#Vectors

  osExit  0d18  handleExit    ; pinned, and implemented here
  osPrint 0d16                ; pinned, implemented by somebody else
  openFile      openHandler   ; the assembler picks the number
```

The software vector space is divided so the two kinds cannot meet:

| Vectors | Whose |
| --- | --- |
| 0 to 2 | Boot, SoftReset and BadOpcode. The machine's, and fixed. |
| 3 to 15 | Faults. Named as each is defined; the rest are held back. |
| 16 to 63 | **Pinned.** Never handed out. A number here is written down or it is not used. |
| 64 to 255 | **Automatic.** Handed out in order. These belong to one program and nothing outside it can name them. |

You may give a number only in the pinned range. Below it belongs to the machine, and above it is where the assembler is allocating, so a number claimed there could be handed to something else in the same breath.

**Why the split exists**, because it is not obvious and the reason is a real mistake that used to be possible. When both kinds came out of one range, the numbers a program got for its own traps depended on what it had included: adding a line that included a file naming three services pushed every trap after it along by three, and a program that had *not* included that file was given the first number in the range — which was a service. Installing its own handler there would have quietly replaced one. Now numbers that must agree are written down, and numbers that need not agree come from somewhere nobody else is looking, so a program's own vectors are its own regardless of how it was built.

The assembler will refuse a number outside the pinned range, two names given the same number, a number on `Boot`, `SoftReset` or `BadOpcode`, whose numbers are the machine's, and a number that contradicts one the same name was already given.

Vectors 3 through 15 are held back for faults, most of which have not been defined yet. They have no names, so there is currently no way to write a handler for one, and none is needed: each will be given a name of its own as the fault it stands for is defined, the way GuardViolation and BankFault were. Since a number may only be written in the pinned range, there is no way to land on one of them by accident either.

## Including Other Files:

The #Include Keyword tells the assembler to load another file to be assembled along with the current file. It is more or less equivalent to copying the contents of the included file into the current file being processed. You simply put the name of the file to include after the keyword.

```
#Include print.asm
```

The assembler looks for that file in two places, in this order:

1. Beside the file that asked for it. A library including its own siblings needs no help.
2. Along the include directories given with -I on the command line, in the order they were given.

An absolute path is taken as it is written. If the file turns up nowhere, the assembler says so and lists every place it looked.

Because a library is normally referred to by name alone, a program that uses one has to be told where the libraries live:

```
Assembler -I Libraries primeSieve/8bitSieve.asm
```

Including the same file twice does nothing the second time, so two libraries may both depend on a third without the program that uses them having to know. The assembler compares files by where they really are rather than by how they were spelled, so the same library reached by two different routes is still only assembled once.

## Running the Assembler:

```
Assembler [options] <sourcefile>
```

| Option | Meaning |
| -- | -- |
| -o, --output \<file\> | Write the binary to this path. Without it, the binary is named after the source file, with a .bin extension, in the directory the assembler was run from. |
| -I, --include \<dir\> | Look in this directory for included files. May be given more than once, and the directories are searched in the order given. |
| -M, --depend \<file\> | Write out which source files went into the binary, as a make rule. |
| -h, --help | Print the options and stop. |

The assembler stops at the first error, says which file and line it was in, and exits without writing a binary.

## Building With Make:

The -o and -M options are there so that the assembler fits into a build system. -o puts the binary wherever the build wants it, and -M writes down which libraries went into it, so that editing a library reassembles every program that includes it.

```
$(BUILD)/%.bin: %.asm
	@mkdir -p $(@D)
	$(ASM) -I Libraries -M $(@:.bin=.d) -o $@ $<

-include $(BINARIES:.bin=.d)
```

Programs/makefile in this repository builds every program that way, if you would like a longer example to copy.

## An Example SplitBit Assembly Program:

```
; This is a slightly more advanced hello world program that demonstrates some SplitBit programming conventions.

#Program

start:              ; By unenforced convention, Program Labels start with a lowercase letter.
  SETD HelloString  ; Set the Data Pointer to the address of the string.
  CALL printString  ; Call the string printing subroutine.
  HALT              ; End the program.

; This is a reusable subroutine that could be included in other programs.
printString:        ; Expects Data Pointer to be set to the beginning of the string to be printed.
  LDA               ; Move the first character of the string into A.
  BRA printDone     ; If A is NULL, the string is finished, so return.
  OUTA 0x00         ; Output the character.
  INCD              ; Increment Data Pointer to the next character.
  BRI printString   ; Branch to the beginning of the loop.
 printDone:
  RET               ; Return to the caller.

#Data

HelloString:  ; By unenforced convention, Data Labels start with a capital letter.
"Hello, World!"
```

## An Example Using More Than One Data Pointer:

Copying between two places in Data Memory needs two pointers: one to read through and one to write through. With a single pointer this loop has to save and restore it on every pass.

```
; Copy a string from one place in Data Memory to another.

#Program

start:
  SETD.0 Source     ; DP0 walks the source.
  SETD.1 Dest       ; DP1 walks the destination.

copy:
  LDA.0             ; Read a byte through DP0.
  BRA copyDone      ; A zero byte is the end of the string.
  STA.1             ; Write it through DP1.
  INCD.0
  INCD.1
  BRI copy

copyDone:
  HALT

#Data

Source:
"Copied through two pointers."

Dest:
0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
```

Remember that DP0, DP1 and DP2 survive a CALL, so a loop like this one can call a subroutine in the middle without losing either pointer. DP3 does not survive, which is what makes it the pointer a subroutine uses to hand an address back.

## An Example Using Interrupts:

This program installs three handlers and never writes a vector number. The Boot Vector sends the machine somewhere other than the first byte of the program, a trap the program names for itself is reached with SWI, and the test device on port 0x10 is caught when it asks for attention.

```
; Interrupt handling from all three directions.

#Program

start:
  CIF               ; Hold devices off while we set up.
  SETD.0 Greeting
  CALL printString

  SWI announce      ; A trap of our own, reached by name.

  INIA 0d1
  OUTA 0x10         ; Ask the test device for attention. Its line goes up.
  SIF               ; Let it through. It is answered before the next instruction.

  HALT

; A trap. It is entered with a full frame, so it may use any register it likes
; without agreeing anything with the code it interrupted.
announce:
  SETD.0 Trapped
  CALL printString
  RETI

; The device handler. Reached because the device sits on port 0x10.
deviceReady:
  SETD.0 Device
  CALL printString
  RETI

; The fault handler. It reports and stops, rather than trying to carry on.
reportFault:
  SETD.0 Broken
  CALL printString
  HALT

printString:        ; Expects DP0 to be set to the beginning of the string.
  LDA.0
  BRA printDone
  OUTA 0x00
  INCD.0
  BRI printString
 printDone:
  INIA 0x0A
  OUTA 0x00
  RET

#Data

Greeting:
"ready"
Trapped:
"trap"
Device:
"device"
Broken:
"bad opcode"

#Vectors

  Boot          start         ; Begin here rather than at the first byte.
  BadOpcode     reportFault
  announce      announce      ; A name of our own. The assembler numbers it.
  Device 0x10   deviceReady   ; Named by the port, because that is what decides it.
```

The output is `ready`, `trap`, then `device`.

Note that a vector name and a routine name are kept apart, so naming both `announce` is allowed. If that reads as confusing, name them differently: nothing requires them to match.
