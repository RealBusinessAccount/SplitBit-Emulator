# SplitBit Assembler Manual:

SplitBit assembly syntax is similar to many other assembler syntaxes. Whitepsace at the start or end of a line is disregarded by the assembler and may be used to make programs more readable to the programmer. The Instruction Mnemonics are listed in the SplitBit Programming Manual, and the assembler is not case sensitve in regard to the mnemonics.

A semicolon, ';', denotes the start of a comment, anything beyond it on a line is disregarded by the assembler.

Special Keywords are denoted with hash marks, '#'. The Keywords are #Include, #Program, and #Data.

SplitBit programs must have a Program Segment. You define the start of a program with the #Program Keyword.
SplitBit programs may have a Data Segment. You may define the start of the data with the #Data Keyword.

## Literal Values:

Literal values may be defined in a few ways. Numerical values must be within the range of a single 8 bit integer.
The assembler will accept:
- Hexadecimal values prefaced with 0x, eg. 0x00, 0x7F.
- Decimal values prefaced with 0d, eg. 0d0, 0d120, 0d255.
- Strings enclosed in double qoutes, eg. "a", "Hello, World!", "It is dark, you are likely to be eaten by a grue."

Any token beginning with a '0' is read as a numerical literal, so a malformed one is an error rather than something the assembler tries to interpret as a label. This also means a label cannot begin with a '0'.

## Labels:

Labels may be a string of up to 32 alphanumeric characters that must end with a colon, ':'.

```
programStart:

loopStart:

errorHandler01:
```

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

Instructions that read operand bytes out of Program Memory must be followed by those operands. The branch instructions and CALL take a label; SETD takes a label or a pair of literal bytes; INIA, INIB, DPUP, DPDN, and the input and output instructions each take a single literal byte.

Data Pointer selectors do not count as operands here, because they are written on the mnemonic rather than after it.

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

start:              ; By uninforced convention, Program Labels start with a lowercase letter.
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

HelloString:  ; By uninforced convention, Data Labels start with a capital letter.
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
