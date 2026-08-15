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
 	 - The PC points to the current operation the CPU is executing. It starts at whatever address the Boot Vector holds. See The Vector Table below.
 	 - The PC is only modified by the branch instructions, by CALL and RET, by SWI and RETI, and by an interrupt arriving. It cannot be directly set by the programmer.

 - The Data Pointers (0-3) are 16 bit pointers into the Data Memory.
 	 - A DP points to a byte of data that the CPU can read or write, and each one initializes at Data Address 0x0000.
 	 - A DP can be set arbitrarily by the programmer to any value.
 	 - Every instruction that reads or writes Data Memory names the DP it works through. See Naming a Data Pointer below.
 	 - Data Pointers 0, 1 and 2 are preserved through subroutine calls. Data Pointer 3 is not.
 	 - Because DP3 is not preserved, a subroutine can use it to pass an address back to the calling routine, in the same way Q passes back a byte. Unlike Q, an address can refer to as much data as you like.

 - The Stack Pointer is a 16 bit pointer into the Data Memory.
 	 - The SP points to the next free slot, not to the last thing pushed. It initializes at location 0xFFFF, so the first push writes there and the byte pushed last always sits one above the SP.
 	 - The SP value is only modified by the push and pop instructions, by CALL and RET, and by an interrupt arriving or returning. It cannot be set by the programmer. MVSD copies it out without moving it.
 	 - The Stack lives in Data Memory, so a Data Pointer can be aimed at it and used to read what is on it. MVSD is how a program finds out where to aim.

 - The Status register is an 8 bit register whose various bits are used as flags. Only four of these flags are used in the current implementation.
	 - Bit 0 is the Carry/Borrow Flag. Any arithmetic operation either sets or clears it depending on whether or not the result causes Q to overflow/underflow. It is a 1 if a carry/underflow occurred, and a 0 otherwise. If A or B overflows or underflows from the use of an increment or decrement instruction, this flag will also be set. Non-overflowing increments or decrements will also reset it.
	 - Bit 1 is the Fault Flag. It is set when the CPU cannot get past something and no handler was installed to deal with it: a byte that is not an instruction, or a dispatch through an empty vector. See Faults below.
	 - Bit 2 is the Interrupt Flag. It is set by SIF and cleared by CIF. While it is set the CPU answers devices asking for attention; while it is clear they wait. Arriving at a handler clears it, and RETI restores it along with the rest of the Status register. See Hardware Interrupts below.
	 - Bit 7 is the Halt Flag. It is set by the HALT instruction, and by a fault.

## The Vector Table:

The top kilobyte of Program Memory is reserved for vectors. Each entry is two bytes, most significant byte first, and holds a Program Memory address.

| Address | Contents |
| --- | --- |
| 0xFC00 | Software vectors 0 to 255 |
| 0xFE00 | Hardware vectors 0 to 255, one for each I/O port |

Program text may not run past 0xFBFF. The assembler refuses to assemble a program that would.

The software vectors are given out like this:

| Vector | Meaning |
| --- | --- |
| 0 | The Boot Vector. Where the machine begins at power on. |
| 1 | The Soft Reset Vector. A warm restart. |
| 2 | A byte that is not an instruction. |
| 3 to 15 | Held back for faults not yet defined. |
| 16 and up | A program's own, given out by the assembler in the order they are named. |

A programmer does not write vector numbers. Handlers are named in the Vector Segment of an assembly file and used by name, the same way every other address in SplitBit is worked out by the assembler rather than typed. See the SplitBit Assembler Manual.

The table holds two kinds of entry, and they behave differently when they are zero.

Software vectors 0 and 1 are start addresses rather than handlers. Vector 0 is the Boot Vector: the CPU reads it at power on and begins executing there. Vector 1 is the Soft Reset Vector, for a warm restart. Nothing dispatches through either of them, and 0x0000 is an ordinary address to begin at, so a zero in one of these two means exactly what it says: start at 0x0000.

That is deliberate, and it is what lets a program that carries no vector table of its own still run. Program Memory reads as zero where nothing was loaded into it, so such a program's Boot Vector reads 0x0000, which is where its first instruction sits.

The cost of that rule is worth knowing: a machine with neither a Boot Vector nor anything at 0x0000 will start executing zeroes, and 0x00 decodes as ADD, so it will wander instead of stopping. There is no way for the CPU to tell that case apart from a program that genuinely begins at 0x0000.

Every other entry is a handler. A zero in one of those means no handler is installed, and dispatching through it is a fault rather than a jump to the bottom of memory.

The exemption for vectors 0 and 1 belongs to that one read the CPU makes at reset, not to the entries themselves. Anything that dispatches treats a zero as no handler, whichever entry it is, so SWI SoftReset through an empty Soft Reset Vector faults like any other. That is what makes SWI SoftReset the way to ask for a warm restart once one has been installed.

## Interrupts:

An interrupt is an involuntary transfer of control. A subroutine call is agreed to by the code that makes it, so CALL can leave Q and Data Pointer 3 alone and let a subroutine pass results back through them. An interrupt arrives in code that has never heard of it, where Q and DP3 are ordinary working registers, so it saves everything:

| Pushed | Bytes |
| --- | --- |
| The address to resume at | 2 |
| Data Pointers 0 through 3 | 8 |
| B, then A, then Q, then Status | 4 |

That is fourteen bytes of Stack per interrupt, and the order matches CALL: least significant byte first, lowest numbered Data Pointer first.

Entry clears the Interrupt Flag, so a handler runs without being interrupted again unless it sets the flag itself. The old value of the flag rides into the frame inside the Status register, so RETI restores it along with everything else and nothing has to remember it separately.

RETI pops the frame and carries on from the address in it. The frame holds a real address rather than an adjusted one, so a handler can read it and make sense of where it came from.

A handler reaches its own frame with MVSD. The Stack Pointer points at the next free slot, so everything in the frame sits above it:

| Offset from the Stack Pointer | Holds |
| --- | --- |
| 1 | Status |
| 2 | Q |
| 3 | A |
| 4 | B |
| 5 and 6 | Data Pointer 3, high byte then low |
| 7 and 8 | Data Pointer 2, high byte then low |
| 9 and 10 | Data Pointer 1, high byte then low |
| 11 and 12 | Data Pointer 0, high byte then low |
| 13 and 14 | The address to resume at, high byte then low |

Writing to those bytes changes what RETI restores. Adding one to the address at offsets 13 and 14 is how a fault handler steps over the byte that failed and carries on, and rewriting the saved registers is how a handler hands something back to the code it interrupted.

SWI is never masked, because it is an instruction the program deliberately ran rather than something a device asked for.

## Hardware Interrupts:

A device asks for attention by putting its line up. Which line it uses is not a choice: a device on port N interrupts on N, and arrives through hardware vector N. That is what spares the machine any arbitration, and it means a program can work out what a device will do by knowing where it is plugged in.

A line is answered between instructions and never inside one, so the address in the frame is always the start of an instruction.

The Interrupt Flag decides whether lines are answered at all. While it is clear, a line that goes up stays up: masking holds a device off, it does not lose what the device was asking for. The moment the flag is set, the line is answered on the very next step. Since entry clears the flag again, a handler is not interrupted while it works unless it sets the flag itself.

When several lines are up at once, the lowest numbered port is answered first. This is a scan rather than a priority scheme, so there is nothing to configure and nothing to explain: a programmer works out what happens next by reading the port numbers.

Answering a line takes it down, so a device that wants attention again has to ask again. A handler returning with RETI restores the Status register, and with it the Interrupt Flag as it was before, so anything still waiting is answered next.

If a device interrupts and its vector is empty, that is a fault: the machine stops and the emulator says which port asked and where it was.

## Devices:

| Port | Device |
| --- | --- |
| 0x00 | The console. Writing sends a byte to standard output, reading takes one from standard input. |
| 0x10 | A test device. Writing anything to it puts its own line up, so that interrupt handling can be exercised without waiting on anything. The byte written is ignored. |

## Faults:

If the CPU reads a byte from Program Memory that does not decode to an instruction, it dispatches through Software Vector 2.

Faults get a vector each rather than sharing one. Vector 2 is the only cause defined so far, and vectors 3 through 15 are held back for the ones that come later, so that a handler always knows what happened from the entry it arrived through. That is why the machine has no fault cause register to read.

The address in the frame is the address of the offending byte itself, not the one after it. A handler can therefore read the byte that failed and say what it was. It also means a handler that returns with a bare RETI will meet the same byte again, because resuming past a fault means deciding where to resume, and only the handler knows that.

If nothing is installed at Vector 2, the CPU sets the Fault Flag and the Halt Flag and stops, leaving the Program Counter on the offending byte. The emulator then reports the byte and its address, and exits with a non zero status.

Stopping matters because the alternative is worse. A byte that means nothing is almost always a sign that execution has wandered into data, or that a program was built for a machine with instructions this one does not have. Stepping over it and carrying on turns a clear failure into a program that appears to run and quietly does the wrong thing.

## Naming a Data Pointer:

Sixteen instructions work through a Data Pointer. Each of them carries a selector byte immediately after its opcode, naming which Data Pointer it means. LDD and STD move a pointer through a pointer, so they carry two selectors, the first naming the pointer being moved and the second naming the pointer that addresses it.

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

### Branch and Subroutine Operations: 8 Instructions
| Hex Code | Mnemonic | Bytes | Description |
| -- | ---- | -- | -- |
| 10 | BRI  | 3 | Branch Immediately. Loads the immediate next two bytes of Program Memory into the Program Counter, first the most significant byte, then the least. |
| 11 | BRQ  | 3 | Branch on Q. If Q is zero, loads the immediate next two bytes of Program Memory into the Program Counter. |
| 12 | BRA  | 3 | Branch on A. If A is zero, loads the immediate next two bytes of Program Memory into the Program Counter. |
| 13 | BRB  | 3 | Branch on B. If B is zero, loads the immediate next two bytes of Program Memory into the Program Counter. |
| 14 | BRC  | 3 | Branch if Carry is set. |
| 15 | BRD  | 2 | Branch to the address held in the named Data Pointer. |
| 17 | CALL | 3 | Call subroutine. Pushes the Program Counter, Data Pointers 0 through 2, B and A to the Stack, then performs an immediate branch. This costs ten bytes of Stack. |
| 18 | SWI  | 2 | Software Interrupt. The next byte names a software vector. Pushes an interrupt frame and dispatches through it. Never masked. |
| 19 | RETI | 1 | Return from an interrupt. Restores everything the frame holds and carries on from where the interrupt arrived. |
| 1F | RET  | 1 | Return from subroutine. Restores A, B, and Data Pointers 0 through 2 from the Stack, then sets the Program Counter to the instruction after the CALL. Data Pointer 3 and Q are left as the subroutine leaves them. |

### Register Operations: 11 Instructions
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
| 29 | MVQA | 1 | Copies Q into A. No flags are changed. |
| 2A | MVQB | 1 | Copies Q into B. No flags are changed. |
| 2B | SIF  | 1 | Sets the Interrupt Flag. No other flags are changed. |
| 2C | CIF  | 1 | Clears the Interrupt Flag. No other flags are changed. |

Q is where every ALU result lands, and Q is not itself an ALU operand, so MVQA and MVQB are how a result becomes the input to the next sum. Without them the only route is to store Q into Data Memory and load it back, which costs two instructions and needs a Data Pointer aimed somewhere useful. With them a running total can be kept in the registers and never touch memory at all.

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
| 4C | MVSD | 2 | Copies the Stack Pointer into the named Data Pointer. The Stack Pointer itself is unchanged and still cannot be written. |

BRD is the only branch whose destination is not written into the program. Every other branch carries the address it goes to, fixed when the program was assembled; BRD takes it from a Data Pointer, which is what makes a table of addresses something a program can dispatch through rather than only read. Together with LDD it turns the Data Segment into somewhere a program can keep a list of places to go.

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
