# SplitBit Assembler Manual:

SplitBit assembly syntax is similar to many other assembler syntaxes. Whitepsace at the start or end of a line is disregarded by the assembler and may be used to make programs more readable to the programmer. The Instruction Mnemonics are listed in the SplitBit Programming Manual, and the assembler is not case sensitve in regard to the mnemonics.

A semicolon, ';', denotes the start of a comment, anything beyond it on a line is disregarded by the assembler.

Special Keywords are denoted with hash marks, '#'. The Keywords are #Include, #Program, and #Data.

Literal values may be defined in a few ways. Numerical values must be within the range of a single 8 bit integer.
The assembler will accept:
- Hexadecimal values prefaced with 0x, eg. 0x00, 0x7F.
- Decimal values prefaced with 0d, eg. 0d0, 0d120, 0d255.
- Strings enclosed in double qoutes, eg. "a", "Hello, World!", "It is dark, you are likely to be eaten by a grue."


Labels may be a string of up to 32 alphanumeric characters that must end with a colon, ':'.

```
programStart:

loopStart:

errorHandler01:
```


The #Include Keyword tells the assembler to load another file to be assembled along with the current file. It is more or less equivalent to copying the contents of the included file into the current file being processed. You simply put the path to the file to include in quotes after the keyword.

```
#Include string.asm
```

SplitBit programs must have a Program Segment. You define the start of a program with the #Program Keyword.
SplitBit programs may have a Data Segment. You may define the start of the data with the #Data Keyword.

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


