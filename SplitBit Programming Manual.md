# General Description:

SplitBit is a small 8 bit CPU.
It is a Harvard Architecture machine with a separate 64k memory space for its Program and another for its Data.

It has ten registers:

 - The A and B Registers are each a general purpose 8 bit register.
	 - A and B are the operand registers for the ALU.
	 - A and B together form a 16-bit circular shift register, AB, in the context of the bit shift instructions, SHL and SHR.
	 - ALU operations do not overwrite A or B.
	 - A and B are preserved through subroutine calls. They can pass two bytes to a subroutine, but cannot directly pass bytes back from a subroutine.

 - The Q Register is the 8 bit ALU output register.
	 - All ALU operations store their result in Q.
	 - Q is not preserved through subroutine calls. It can be used to pass a one byte result back to the calling routine.

 - The Program Counter is a 16 bit pointer into the Program Memory.
 	 - The PC points to the current operation the CPU is executing, it initializes at Program Address 0x0000.
 	 - The PC is only modified by the branch instructions and the CALL and RET instructions. It cannot be directly set by the programmer.

 - The Data Pointers (0-3) are 16 bit pointers into the Data Memory.
 	 - A DP points to a byte of data that the CPU can read or write, and each one initializes at Data Address 0x0000.
 	 - A DP can be set arbitrarily by the programmer to any value.
 	 - Every instruction that reads or writes Data Memory names the DP it works through. See Naming a Data Pointer below.
 	 - Data Pointers 0, 1 and 2 are preserved through subroutine calls. Data Pointer 3 is not.
 	 - Because DP3 is not preserved, a subroutine can use it to pass an address back to the calling routine, in the same way Q passes back a byte. Unlike Q, an address can refer to as much data as you like.

 - The Stack Pointer is a 16 bit pointer into the Data Memory.
 	 - The SP points to the current element of the stack, it initializes at location 0xFFFF.
 	 - The SP value is only modified by the push and pop instructions and cannot be set by the programmer.
 	 - The Stack lives in Data Memory, so a Data Pointer can be aimed at it and used to read what is on it.

 - The Status register is an 8 bit register whose various bits are used as flags. Only two of these flags are used in the current implementation.
	 - Bit 0 is the Carry/Borrow Flag. Any arithmetic operation either sets or clears it depending on whether or not the result causes Q to overflow/underflow. It is a 1 if a carry/underflow occurred, and a 0 otherwise. If A or B overflows or underflows from the use of an increment or decrement instruction, this flag will also be set. Non-overflowing increments or decrements will also reset it.
	 - Bit 7 is the Halt Flag. It is set by the HALT instruction.

## Naming a Data Pointer:

Twelve instructions work through a Data Pointer. Each of them carries a selector byte immediately after its opcode, naming which Data Pointer it means. LDD and STD move a pointer through a pointer, so they carry two selectors, the first naming the pointer being moved and the second naming the pointer that addresses it.

The selector is a full byte, but only enough of it is read to choose among the Data Pointers the machine has. A selector larger than the highest numbered pointer wraps around rather than being rejected, so it is the assembler's job to refuse to write one.

In assembly the selector is written on the mnemonic itself, as `LDA.2` or `LDD.1.0`. Leaving it off means Data Pointer 0, so a program that only needs one pointer never has to mention them at all. See the Assembler Manual.

## List of Instructions:

The Bytes column is the total length of the instruction, counting its opcode, any Data Pointer selectors, and any other operands it reads out of Program Memory.

### Arithmetic and Logic Operations: 9 Instructions
| Hex Code | Mnemonic | Bytes | Description |
| -- | ---- | -- | -- |
| 00 | ADD  | 1 | Adds A, B, and the Carry Flag, the result is stored in Q. |
| 01 | SUB  | 1 | Subtracts B and the Carry Flag from A, the result is stored in Q. |
| 02 | AND  | 1 | Bitwise and of A and B, the result is stored in Q. |
| 03 | OR   | 1 | Bitwise or of A and B, the result is stored in Q. |
| 04 | XOR  | 1 | Bitwise xor of A and B, the result is stored in Q. |
| 05 | NOTA | 1 | Bitwise inversion of A, the result is stored in Q. |
| 06 | NOTB | 1 | Bitwise inversion of B, the result is stored in Q. |
| 07 | SHL  | 1 | A and B form a circular shift register. Rotate this register left. |
| 08 | SHR  | 1 | A and B form a circular shift register. Rotate this register right. |

### Branch and Subroutine Operations: 7 Instructions
| Hex Code | Mnemonic | Bytes | Description |
| -- | ---- | -- | -- |
| 10 | BRI  | 3 | Branch Immediately. Loads the immediate next two bytes of Program Memory into the Program Counter, first the most significant byte, then the least. |
| 11 | BRQ  | 3 | Branch on Q. If Q is zero, loads the immediate next two bytes of Program Memory into the Program Counter. |
| 12 | BRA  | 3 | Branch on A. If A is zero, loads the immediate next two bytes of Program Memory into the Program Counter. |
| 13 | BRB  | 3 | Branch on B. If B is zero, loads the immediate next two bytes of Program Memory into the Program Counter. |
| 14 | BRC  | 3 | Branch if Carry is set. |
| 17 | CALL | 3 | Call subroutine. Pushes the Program Counter, Data Pointers 0 through 2, B and A to the Stack, then performs an immediate branch. This costs ten bytes of Stack. |
| 1F | RET  | 1 | Return from subroutine. Restores A, B, and Data Pointers 0 through 2 from the Stack, then sets the Program Counter to the instruction after the CALL. Data Pointer 3 and Q are left as the subroutine leaves them. |

### Register Operations: 9 Instructions
| Hex Code | Mnemonic | Bytes | Description |
| -- | ---- | -- | -- |
| 20 | RSTA | 1 | Resets A to 0. |
| 21 | RSTB | 1 | Resets B to 0. |
| 22 | INCA | 1 | Adds 1 to A. If it overflows, it sets the Carry Flag, otherwise, it resets it. |
| 23 | INCB | 1 | Adds 1 to B. If it overflows, it sets the Carry Flag, otherwise, it resets it. |
| 24 | DECA | 1 | Subtracts 1 from A. If it underflows, it sets the Carry Flag, otherwise, it resets it. |
| 25 | DECB | 1 | Subtracts 1 from B. If it underflows, it sets the Carry Flag, otherwise, it resets it. |
| 26 | INIA | 2 | Loads the next byte of Program Memory to A. |
| 27 | INIB | 2 | Loads the next byte of Program Memory to B. |
| 28 | CCF  | 1 | Clears the Carry Flag. |

### Stack Operations: 7 Instructions
| Hex Code | Mnemonic | Bytes | Description |
| -- | ---- | -- | -- |
| 30 | PSHQ | 1 | Stores Q into Data Memory at the location referenced by the Stack Pointer then decrements the Stack Pointer. |
| 31 | PSHA | 1 | Stores A into Data Memory at the location referenced by the Stack Pointer then decrements the Stack Pointer. |
| 32 | PSHB | 1 | Stores B into Data Memory at the location referenced by the Stack Pointer then decrements the Stack Pointer. |
| 33 | PSHD | 2 | Stores the named Data Pointer to the stack, with the low byte on top. Decrements the Stack Pointer by two. |
| 34 | POPA | 1 | Reads the location referenced by the Stack Pointer from Data Memory into A then increments the Stack Pointer. |
| 35 | POPB | 1 | Reads the location referenced by the Stack Pointer from Data Memory into B then increments the Stack Pointer. |
| 36 | POPD | 2 | Restores the named Data Pointer from the stack, increments the Stack Pointer by two. |

### Data Operations: 12 Instructions
| Hex Code | Mnemonic | Bytes | Description |
| -- | ---- | -- | -- |
| 40 | INCD | 2 | Increments the named Data Pointer. |
| 41 | DECD | 2 | Decrements the named Data Pointer. |
| 42 | LDA  | 2 | Loads the byte addressed by the named Data Pointer into A. |
| 43 | LDB  | 2 | Loads the byte addressed by the named Data Pointer into B. |
| 44 | STQ  | 2 | Stores Q into the byte addressed by the named Data Pointer. |
| 45 | STA  | 2 | Stores A into the byte addressed by the named Data Pointer. |
| 46 | STB  | 2 | Stores B into the byte addressed by the named Data Pointer. |
| 47 | SETD | 4 | Loads the two bytes of Program Memory following the selector into the named Data Pointer, most significant byte first. |
| 48 | DPUP | 3 | Offsets the named Data Pointer up by the value of the byte following the selector. |
| 49 | DPDN | 3 | Offsets the named Data Pointer down by the value of the byte following the selector. |
| 4A | LDD  | 3 | Loads the first named Data Pointer from the two bytes of Data Memory addressed by the second, most significant byte first. |
| 4B | STD  | 3 | Stores the first named Data Pointer into the two bytes of Data Memory addressed by the second, most significant byte first. |

LDD and STD are how a program follows an address it has stored, rather than one the assembler wrote into the instruction. Together with more than one Data Pointer, they are what makes a table of addresses usable: one pointer walks the table while another follows whatever entry it is on. Naming the same pointer twice, as in `LDD.0.0`, makes that pointer follow the address it is currently holding.

### Output Operations: 3 Instructions
| Hex Code | Mnemonic | Bytes | Description |
| -- | ---- | -- | -- |
| D0 | OUTQ | 2 | Writes the value of Q to an Output specified by the next byte of Program Memory. |
| D1 | OUTA | 2 | Writes the value of A to an Output specified by the next byte of Program Memory. |
| D2 | OUTB | 2 | Writes the value of B to an Output specified by the next byte of Program Memory. |

### Input Operations: 2 Instructions
| Hex Code | Mnemonic | Bytes | Description |
| -- | ---- | -- | -- |
| E0 | INA | 2 | Writes the value of an Input to A. The input port is specified by the next byte of Program Memory. |
| E1 | INB | 2 | Writes the value of an Input to B. The input port is specified by the next byte of Program Memory. |

### Special Operations: 2 Instructions
| Hex Code | Mnemonic | Bytes | Description |
| -- | ---- | -- | -- |
| F0 | NOP  | 1 | Perform no Operation, increment the Program Counter. |
| FF | HALT | 1 | Stops CPU Execution. |

## Input and Output In the Emulator:

The current implementation has Input 0 and Output 0 hooked to stdin and stdout respectively, allowing programs to read to and from the console.

### Example Program: Hello World
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

Nothing in that program names a Data Pointer, so all of it runs through Data Pointer 0.

### Structure of a SplitBit Binary File:

The Program and Data values are both stored in a single file for loading into the system. Every multi byte value in the format is stored most significant byte first, which is the same order the CPU reads addresses out of Program Memory.

A file begins with a nine byte header:

| Offset | Size | Field |
| -- | -- | -- |
| 0 | 4 | The characters `SPBT`, so that a file which is not a SplitBit binary is recognised as such straight away. |
| 4 | 1 | The format version. This document describes version 1. |
| 5 | 4 | Required feature flags. |

The feature flags are how a binary states that it needs something the base machine does not provide. An emulator that cannot provide everything a binary asks for refuses to run it, rather than running it and going quietly wrong. No feature bits are defined yet, so the field is currently zero in every binary.

After the header come the two segments, the Program Segment first and then the Data Segment. Each begins with a three character marker, `PRG` or `DAT`, followed by a two byte length. The system loads each memory with the bytes that follow, in sequence, starting from address 0x0000.

Here is the hello world program above, assembled and dumped as hex:

```
53 50 42 54 01 00 00 00 00 50 52 47 00 11 42 00 12 00 0c d1 00 40 00 10 00 00 26 0a d1 00 ff 44
41 54 00 0e 48 65 6c 6c 6f 2c 20 57 6f 72 6c 64 21 00
```

Taken apart:

| Bytes | Meaning |
| -- | -- |
| `53 50 42 54` | `SPBT` |
| `01` | Format version 1 |
| `00 00 00 00` | No features required |
| `50 52 47` | `PRG` |
| `00 11` | The Program Segment is 17 bytes long |
| `42 00 12 00 0c d1 00 40 00 10 00 00 26 0a d1 00 ff` | The Program Segment |
| `44 41 54` | `DAT` |
| `00 0e` | The Data Segment is 14 bytes long |
| `48 65 6c 6c 6f 2c 20 57 6f 72 6c 64 21 00` | The Data Segment |

The `42 00` at the start of the Program Segment is worth a look: `42` is LDA, and the `00` after it is the Data Pointer selector the assembler filled in, because the program did not name one.
