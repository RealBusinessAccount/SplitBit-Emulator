# General Description:

SplitBit is a small 8 bit CPU.
It is a Harvard Architecture machine with a separate 64k memory space for its Program and another for its Data.

It has six registers:
 - The A and B Registers are the 8 bit operands for the ALU. All ALU operations use them as operands. They can also be used as general purpose accumulators.
 - The Q Register is the 8 bit ALU output register, all ALU operations store their result in it.
 - The Program Counter is a 16 bit pointer into the Program Memory. It points to the current operation the CPU is executing. It initializes at address 0x0000.
 - The Data Pointer is a 16 bit pointer into the Data Memory. It points to the current byte of data that the CPU can read or write to, and can be set arbitrarily by the programmer to any value in the Data Memory. It initializes at location 0x0000.
 - The Stack Pointer is a 16 bit pointer into the Data Memory. It points to the current element of the stack, and is only ever modified by the use of the push and pop instructions. It initializes at location 0xFFFF.
 - The Status register is an 8 bit register whose various bits are used as flags. Only three of these flags are used in the current implementation. 
	 - Bit 0 is the Carry/Borrow Flag. Any arithmetic operation either sets or clears it depending on whether or not the result causes Q to overflow/underflow. It is a 1 if a carry/underflow occurred, and a 0 otherwise.
	 - Bit 1 is the Stack Collision Flag. It is set if the Data Pointer's value ever meets or exceeds the Stack Pointer's value. This condition also sets the Halt Flag.
	 - Bit 7 is the Halt Flag. It is set by the HALT instruction, or if there is a stack collision.

## List of Instructions:

### Arithmetic and Logic Operations: 9 Instructions
Hex Code | Mnemonic | Description
-- | -- | --
00 | ADD |  Adds A, B, and the Carry Flag, the result is stored in Q.
01 | SUB | Subtracts B and the Carry Flag from A, the result is stored in Q.
02 | AND | Bitwise and of A and B, the result is stored in Q.
03 | OR | Bitwise or of A and B, the result is stored in Q.
04 | NOR | Bitwise nor of A and B, the result is stored in Q.
05 | NAND | Bitwise nand of A and B, the result is stored in Q.
06 | XOR | Bitwise xor of A and B, the result is stored in Q.
07 | NOTA | Bitwise inversion of A, the result is stored in Q.
08 | NOTB | Bitwise inversion of B, the result is stored in Q.

### Branch Operations: 4 Instructions
Hex Code | Mnemonic | Description
-- | -- | --
10 | BRI | Branch Immediately. Loads the immediate next two bytes of Program Memory into the Program Counter, first the most significant byte, then the least.
11 | BRQ | Branch on Q. If Q is zero, loads the immediate next two bytes of Program Memory into the Program Counter.
12 | BRA | Branch on A. If A is zero, loads the immediate next two bytes of Program Memory into the Program Counter.
13 | BRB | Branch on B. If B is zero, loads the immediate next two bytes of Program Memory into the Program Counter.

### Register Operations: 6 Instructions
| Hex Code | Mnemonic | Description         |
| -------- | -------- | ------------------- |
| 20       | RSTA     | Resets A to 0.      |
| 21       | RSTB     | Resets B to 0.      |
| 22       | INCA     | Adds 1 to A.        |
| 23       | INCB     | Adds 1 to B.        |
| 24       | DECA     | Subtracts 1 from A. |
| 25       | DECB     | Subtracts 1 from B. |

### Stack Operations: 9 Instructions
Hex Code | Mnemonic | Description
-- | -- | --
30 | PSHQ | Stores Q into Data Memory at the location referenced by the Stack Pointer then decrements the Stack Pointer.
31 | PSHA | Stores A into Data Memory at the location referenced by the Stack Pointer then decrements the Stack Pointer.
32 | PSHB | Stores B into Data Memory at the location referenced by the Stack Pointer then decrements the Stack Pointer.
33 | PSHP | Stores the Program Counter to the next two bytes in the stack, decrements the Stack Pointer by two.
34 | PSHD | Stores the Data Pointer to the next two bytes in the stack, decrements the Stack Pointer by two.
35 | POPA | Reads the location referenced by the Stack Pointer from Data Memory into A then increments the Stack Pointer.
36 | POPB | Reads the location referenced by the Stack Pointer from Data Memory into B then increments the Stack Pointer.
37 | POPP | Restores the Program Counter from the top two bytes in the stack, increments the Stack Pointer by two.
38 | POPD | Restores the Program Counter from the top two bytes in the stack, increments the Stack Pointer by two.

### Data Operations: 7 Instructions
Hex Code | Mnemonic | Description
-- | -- | --
40 | INCD | Increments the Data Pointer.
41 | DECD | Decrements the Data Pointer.
42 | LDA | Loads the byte referenced from Data Memory by the Data Pointer into A.
43 | LDB | Loads the byte referenced from Data Memory by the Data Pointer into B.
44 | STQ | Stores Q into the byte referenced by the Data Pointer in Data Mmoery.
45 | STA | Stores A into the byte referenced by the Data Pointer in Data Memory.
46 | STB | Stores B into the byte referenced by the Data Pointer in Data Memory.


### Output Operations: 3 Instructions
Hex Code | Mnemonic | Description
-- | -- | --
D0 | OUTQ | Writes the value of Q to an Output specified by the next byte of Program Memory.
D1 | OUTA | Writes the value of A to an Output specified by the next byte of Program Memory.
D2 | OUTB | Writes the value of B to an Output specified by the next byte of Program Memory.

### Input Operations: 3 Instructions
Hex Code | Mnemonic | Description
-- | -- | --
E1 | RDA | Writes the value of an Input to A. The input port is specified the next byte of Program Memory.
E2 | RDB | Writes the value of an Input to B. The input port is specified the next byte of Program Memory.
E3 | RDD | Writes the value of an Input to Data Memory at the location referenced by the Data Pointer. The input port is specified by the next byte of Program Memory.

### Special Operations: 2 Instructions
Hex Code | Mnemonic | Description
-- | -- | --
F0 | HALT | Stops CPU Execution.
FF | NOP | Perform no Operation, increment the Program Counter.

## Input and Output In the Emulator:

The current implementation has Input 0 and Output 0 hooked to stdout and stdin respectively, allowing programs to read to and from the console.

### Example Program: Hello World
```
; Hello World for SplitBit CPU
; First, we define the string in Data Memory.
Data:
0000 0x48 ; 'H'
0001 0x65 ; 'e'
0002 0x6C ; 'l'
0003 0x6C ; 'l'
0004 0x6F ; 'o'
0005 0x2C ; ','
0006 0x20 ; ' '
0007 0x57 ; 'W'
0008 0x6F ; 'o'
0009 0x72 ; 'r'
000A 0x6C ; 'l'
000B 0x64 ; 'd'
000C 0x32 ; '!'
000D 0x0A ; This is a linefeed, it's equivalent to putting '\n' in a string in C.
000E 0x00 ; Zero terminates the string.

; Next, we'll create a loop that outputs each byte of our string to Output 0, the text console.
Program:
0000 LDA    0x42    ; Load the first byte of the string into A.
0001 BRA    0x12    ; If A is zero, branch out of the loop.
0002 0x00   0x00    ; The high byte of the branch.
0003 0x0A   0x0A    ; The low byte of the branch.
0004 OUTA   0xD1    ; Output the value in A.
0005 0x01   0x00    ; The Output Port to use.
0006 INCD   0x40    ; Increment the Data Pointer to the next byte of the string.
0007 BRI    0x10    ; Branch immediately to the start of the loop.
0008 0x00   0x00    ; The high byte of the branch address.
0009 0x00   0x00    ; The low byte of the branch address.
000A HALT   0xFF    ; The end of the program.
```

### Structure of a SplitBit Binary File:
The Program and Data values are both stored in a single file for loading into the system. The Program Segment must come first, then the Data Segment. The system will look for a three letter header, PRG for program and DAT for data. After the header is a two byte value representing the length of the segment. The system loads the memories with the bytes from the file in sequence starting from address 0x0000.

Here's an example hex dump of the hello world program stored in the proper format:

```
50 52 47 00 0A 42 12 00 0A D1 00 40 10 00 00 FF 44 41 54 00 0E 48 65 6C 6C 6F 2C 20 57 6F 72 6C 64 21 0A 00
```