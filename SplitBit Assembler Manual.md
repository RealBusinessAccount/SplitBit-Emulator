# SplitBit Assembler Manual:

SplitBit assembly syntax is similar to many other assembler syntaxes. Whitepsace at the start or end of a line is disregarded by the assembler and may be used to make programs more readable to the programmer. The Instruction Mnemonics are listed in the SplitBit Programming Manual, and the assembler is not case sensitve in regard to the mnemonics.

A semicolon, ';', denotes the start of a comment, anything beyond it on a line is disregarded by the assembler.

Special Keywords are denoted with hash marks, '#'. The Keywords are #Include, #Program, and #Data.

Literal values may be defined in a few ways. Numerical values must be within the range of a single 8 bit integer.
The assembler will accept:
    - Hexadecimal values prefaced with 0x, eg. 0x00, 0x7F.
    - Decimal values prefaced with 0d, eg. 0d0, 0d120, 0d255.
    - Strings enclosed in double qoutes, eg. "a", "Hello, World!", "It is dark, you are likely to be eaten by a grue."


Labels may be a string of up to 32 alphanumeric characters that must end with a semicolon, ':'.

```
ProgramStart:

LoopStart:

ErrorHandler01:
```


The #Include Keyword tells the assembler to load another file to be assembled along with the current file. It is more or less equivalent to copying the contents of the included file into the current file being processed. You simply put the path to the file to include in quotes after the keyword.

```
#Include string.asm
```

SplitBit programs must have a Program Segment. You define the start of a program with the #Program Keyword.
SplitBit programs may have a Data Segment. You may define the start of the data with the #Data Keyword.

## An Example SplitBit Assembly Program:

```
; This is a basic hello world program for the SplitBit CPU.
; We'll create a loop that outputs each byte of our string to Output 0, the text console.

#Program

Start:
  LDA         ; Load a byte of the string into A.
  BRA End     ; If A is zero, branch out of the loop.
  OUTA 0x00   ; Output the value in A to Port 0, the text console.
  INCD        ; Increment the Data Pointer to the next byte of the string.
  BRI Start   ; Branch immediately to the start of the loop.

End:
  INIA 0x0A   ; We'll load a linefeed into A and output it to make it look nice.
  OUTA 0x00   ; Output it to the text console.
  HALT        ; Terminate the program.

#Data

"Hello, World!"
```


