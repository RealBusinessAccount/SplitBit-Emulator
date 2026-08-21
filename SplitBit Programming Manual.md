# The SplitBit Programming Manual

This describes the machine: what the CPU has, what its instructions do, how something gets
its attention, and what a SplitBit is made of. Everything here is true of any SplitBit,
whatever happens to be running on it.

The **Assembler Manual** describes the language you write for it and the two file formats
it produces. `Programs/CosmOS/README.md` describes CosmOS, which is one operating system
that runs on this machine rather than part of the machine itself.

# The Machine

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
 	 - The PC points to the current operation the CPU is executing. It starts at whatever address the Boot Vector holds. See The Vector Table.
 	 - The PC is only modified by the branch instructions, by CALL and RET, by SWI and RETI, and by an interrupt arriving. It cannot be directly set by the programmer.

 - The Data Pointers (0-3) are 16 bit pointers into the Data Memory.
 	 - A DP points to a byte of data that the CPU can read or write, and each one initializes at Data Address 0x0000.
 	 - A DP can be set arbitrarily by the programmer to any value.
 	 - Every instruction that reads or writes Data Memory names the DP it works through. See Naming a Data Pointer.
 	 - Data Pointers 0, 1 and 2 are preserved through subroutine calls. Data Pointer 3 is not.
 	 - Because DP3 is not preserved, a subroutine can use it to pass an address back to the calling routine, in the same way Q passes back a byte. Unlike Q, an address can refer to as much data as you like.

 - The Stack Pointer is a 16 bit pointer into the Data Memory.
 	 - The SP points to the next free slot, not to the last thing pushed. It initializes at location 0xFFFF, so the first push writes there and the byte pushed last always sits one above the SP.
 	 - The SP is moved by the push and pop instructions, by CALL and RET, and by an interrupt arriving or returning. MVSD copies it out without moving it, and MVDS sets it outright. See The Stack Pointer, Set By Hand before using MVDS.
 	 - The Stack lives in Data Memory, so a Data Pointer can be aimed at it and used to read what is on it. MVSD is how a program finds out where to aim.

 - The Status register is an 8 bit register whose various bits are used as flags. Only four of these flags are used in the current implementation.
	 - Bit 0 is the Carry/Borrow Flag. Any arithmetic operation either sets or clears it depending on whether or not the result causes Q to overflow/underflow. It is a 1 if a carry/underflow occurred, and a 0 otherwise. If A or B overflows or underflows from the use of an increment or decrement instruction, this flag will also be set. Non-overflowing increments or decrements will also reset it.
	 - Bit 1 is the Fault Flag. It is set when the CPU cannot get past something and no handler was installed to deal with it: a byte that is not an instruction, or a dispatch through an empty vector. See Faults.
	 - Bit 2 is the Interrupt Flag. It is set by SIF and cleared by CIF. While it is set the CPU answers devices asking for attention; while it is clear they wait. Arriving at a handler clears it, and RETI restores it along with the rest of the Status register. See Hardware Interrupts.
	 - Bit 7 is the Halt Flag. It is set by the HALT instruction, and by a fault.

Each condition has a branch both ways round, so a loop that carries on while something is not zero is one instruction rather than a branch over an unconditional one. Before these existed a quarter of every conditional branch in the corpus was written backwards and padded out, and each of those needed a label invented only to be jumped past.

A conditional branch reads the thing it names at the moment it runs. BRA looks at A, and it does not matter which instruction set A or how long ago. The two that read the Carry Flag are the exception, and they say so in their names. That is worth knowing when reading somebody else's code: nothing else on this machine leaves a hidden condition behind for a later branch to find.

## Naming a Data Pointer:

Seventeen instructions work through a Data Pointer. Each of them carries a selector byte immediately after its opcode, naming which Data Pointer it means. LDD and STD move a pointer through a pointer, so they carry two selectors, the first naming the pointer being moved and the second naming the pointer that addresses it.

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

### Branch and Subroutine Operations: 14 Instructions
| Hex Code | Mnemonic | Bytes | Description |
| -- | ---- | -- | -- |
| 10 | BRI  | 3 | Branch Immediately. Loads the immediate next two bytes of Program Memory into the Program Counter, first the most significant byte, then the least. |
| 11 | BRQ  | 3 | Branch on Q. If Q is zero, loads the immediate next two bytes of Program Memory into the Program Counter. |
| 12 | BRA  | 3 | Branch on A. If A is zero, loads the immediate next two bytes of Program Memory into the Program Counter. |
| 13 | BRB  | 3 | Branch on B. If B is zero, loads the immediate next two bytes of Program Memory into the Program Counter. |
| 14 | BRC  | 3 | Branch if Carry is set. |
| 15 | BRD  | 2 | Branch to the address held in the named Data Pointer. |
| 1A | BNQ  | 3 | Branch if Q is not zero. |
| 1B | BNA  | 3 | Branch if A is not zero. |
| 1C | BNB  | 3 | Branch if B is not zero. |
| 1D | BNC  | 3 | Branch if the Carry Flag is clear. |
| 17 | CALL | 3 | Call subroutine. Pushes the Program Counter, Data Pointers 0 through 2, B and A to the Stack, then performs an immediate branch. This costs ten bytes of Stack. |
| 18 | SWI  | 2 | Software Interrupt. The next byte names a software vector. Pushes an interrupt frame and dispatches through it. Never masked. |
| 19 | RETI | 1 | Return from an interrupt. Restores everything the frame holds and carries on from where the interrupt arrived. |
| 1F | RET  | 1 | Return from subroutine. Restores A, B, and Data Pointers 0 through 2 from the Stack, then sets the Program Counter to the instruction after the CALL. Data Pointer 3 and Q are left as the subroutine leaves them. |

### Register Operations: 13 Instructions
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

### Data Operations: 14 Instructions
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
| 4C | MVSD | 2 | Copies the Stack Pointer into the named Data Pointer. The Stack Pointer itself is unchanged. |
| 4D | MVDS | 2 | Copies the named Data Pointer into the Stack Pointer, moving the Stack. Read The Stack Pointer, Set By Hand before using it. |

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

# Making It Do Something

## Making It Print Something:

Port 0 is the console: writing sends a byte to standard output and reading takes one from standard input. It answers on two more ports than that, which are described under The Console and which a program can ignore entirely if all it wants is to read and write bytes. Everything else this machine has is listed under Devices, and a program that wants to know what is actually there asks the bus registry rather than assuming.

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

## The Console:

Port 0x00 is the oldest thing on this machine and it has not changed: writing sends a byte out, reading takes one in and waits until there is one. Every program ever written for SplitBit uses it that way and still does. What is new is that a program can say what it wants a keypress to mean, can ask whether a read would have to wait, and can arrange to be told when a byte arrives instead of having to ask at all.

| Port | Register |
| --- | --- |
| 0x00 | Data. Writing sends a byte out, reading takes one in and waits for it. |
| 0x01 | Status. Bit 0 a byte is waiting, bit 1 input has ended, bit 2 the console is in key mode, bit 3 the console is set to interrupt. |
| 0x02 | Control. Bit 0 asks for key mode, bit 1 asks the console to interrupt when a byte arrives. Writing 0x00 asks for neither, which is how the console starts. |

The control port's two bits are independent, and one write sets both. Everything the control port can ask for, the status port reports, so a program can put the console back the way it found it instead of assuming it knows.

### Two Kinds Of Input:

In **line mode**, which is how the machine starts, the terminal holds what is typed until Return and does the echoing and the backspacing on the way. A program reading the data port gets a finished line, one byte at a time. This is what the machine has always done and what a shell wants.

In **key mode** the terminal stops holding the line. Keys arrive as they are pressed, and nothing echoes them, so a program that wants them seen has to send them back out itself. The editing goes with the echo: there is no backspace, because backspace was the terminal's doing and the terminal is no longer involved. That is not a choice this machine makes, it is what asking for keys means, and a program that wants keys is expected to want it.

A program is expected to put the console back in line mode before it finishes. CosmOS also does it whenever a program returns, because a program that stops early would otherwise hand back a shell with no echo, and a shell has no way to find out that happened.

### Reading Without Waiting:

Reading the data port waits in **both** modes. The status port is how a program declines to wait, and keeping that in one place is deliberate: a read that sometimes blocked and sometimes did not, depending on a mode set somewhere else, would be a program that works until it does not.

So a simulation that should stop when somebody presses a key asks the status port between steps, and only reads the data port once it knows there is something to read:

```
  INA 0x01
  INIB 0x01                 ; Bit 0: is a byte waiting?
  AND
  BRQ nobodyPressedAnything
  INA 0x00                  ; There is one, so this will not wait.
```

### The End Of Input:

Reading the data port when input has run out gives 0xFF, which is what it has always given and what programs written before any of this expect. But 0xFF is also an ordinary byte, and nothing could tell the two apart. Bit 1 of the status port is what tells them apart now.

Bit 0 is **not** set once input has ended, even though a read would answer immediately. The bit means a byte is there to be had, and at the end of input there is not. That way a loop that reads while bit 0 is set stops when the input does, instead of taking imaginary bytes forever.

### Being Told Instead Of Asking:

Bit 1 of the control port asks the console to put its interrupt line up when a byte arrives, so a program can get on with something else and be told. The console is on port 0x00, so that is the vector a key comes through, named the way every device is:

```
#Vectors
  Device 0x00  keyHandler
```

The handler is entered because the console had something to say, and asks the status port what. There are two possible answers, and the second is why a program can rely on this instead of also polling:

```
keyHandler:
  INA 0x01
  INIB 0x02                 ; Bit 1: has input ended?
  AND
  BNQ noMoreKeys            ; Nothing more is ever coming.
  INA 0x00                  ; The byte this interrupt was about.
  OUTA 0x00                 ; Nothing echoes in key mode, so send it back out.
  RETI
```

**The end of input raises the line once**, as well as an arriving byte. A program driven entirely by interrupts would otherwise sit forever waiting to be told about a key that cannot arrive.

**The line goes up at most once per byte.** The console holds one byte, so while that byte is still there, nothing new can arrive to ask about, and a handler that returns without reading it is simply not called again. This is what a receive register holding one byte does, and it means a handler cannot interrupt-storm the machine by forgetting something. The cost is the other half of the same fact: bytes arriving while that one is unread are lost, exactly as they would be on hardware.

The two control bits do not depend on each other, so a program may ask to be interrupted in line mode. The terminal still holds what is typed until Return, and then the whole line arrives at once as a run of interrupts, one per byte. That is rarely what anyone wants, but a control bit that quietly did nothing because of another control bit would be worse.

**A program that interrupts on input must not also block on the data port.** Reading it waits, and nothing else in the machine runs while it is waiting, so a program that does both has chosen to wait after asking not to. Interrupting and blocking are two answers to the same question, and a program wants one of them.

The machine notices an arriving key between instructions, and does not look on every single one. The delay is about a quarter of a millisecond, which is shorter than the gap between two keystrokes by a wide margin and shorter than anything a person can perceive at all.

## The Stack Pointer, Set By Hand:

MVDS copies a Data Pointer into the Stack Pointer. It is the most dangerous instruction on this machine, and it is here for one job.

Everything a program is in the middle of doing lives on the Stack. Moving the Stack Pointer does not move any of it, and does not destroy any of it either: it steps away from it. Every return address, every saved register and every interrupt frame stays exactly where it was in Data Memory, and the Stack Pointer is simply no longer looking at it. A RET taken while the Stack Pointer is somewhere else does not go back to whoever called: it reads two bytes from wherever the Stack Pointer now points and branches there. If those bytes are a string, execution lands in the middle of it.

That is not a bug to be worked around. It is what moving the Stack means, and it is why nothing else on this machine can do it.

The job it is here for is reclaiming the Stack from a program that has stopped running. A system that loads other programs and takes the machine back afterwards has a problem without it. A program that gives up part way through leaves everything it pushed behind, and the interrupt frame carrying its request to stop is on there too. Nothing unwinds any of that, because the program is not going to return. Without MVDS the Stack only ever moves downward, a little more with every program run, and a shell cannot outlive many of them.

The pattern is to write the Stack Pointer down before giving the machine away and put it back afterwards:

```
  ; Before handing control to a program, remember where the Stack was.
  MVSD.0
  SETD.1 SavedStack
  STD.0.1

  ; ... the program runs, and eventually asks to stop ...

  ; Taking the machine back. The Stack is ours again, and everything the
  ; program left on it is gone.
  SETD.1 SavedStack
  LDD.0.1
  MVDS.0
```

### Coming Back From It:

A routine that moves the Stack and then puts the Stack Pointer back exactly where it found it can return in the ordinary way. The return address and the frame were never destroyed, only stepped away from, and RET or RETI finds them precisely as they were. Nothing special is needed for this to work, but one thing is required for it to keep working: nothing done while the Stack was elsewhere may reach back over those bytes. A borrowed Stack has to be somewhere the old one is not, and it has to be far enough away that pushing on it cannot walk into the old one.

A routine that moves the Stack and **leaves it moved** is the other case, and that one cannot return at all, because its return address is on the Stack it walked away from. This is not a limitation to work around either. It is the entire point when the reason for moving is that whoever owned that Stack is not coming back. A handler for a service meaning "give the machine back" restores the system's Stack and then branches to the prompt, because there is nowhere left to return to.

### Where To Keep The Old One:

This is the awkward part. A fixed location in Data Memory is the obvious place to write the old Stack Pointer down, and it works until two routines that do this are nested. The inner one overwrites the outer one's copy, the outer one restores the inner one's Stack, and it never gets home. Nothing about that failure points back at the cause.

The answer that nests is to keep the old Stack Pointer on the borrowed Stack itself. Move first, then push it, and pop it back before returning. Each nesting keeps its own copy, on its own Stack, and no two of them can collide:

```
  MVSD.3                ; Where the Stack is now.
  SETD.0 BorrowedTop    ; The highest address of somewhere a Stack can live,
  MVDS.0                ; because the Stack grows downward from here.
  PSHD.3                ; The old Stack Pointer, kept on the borrowed Stack.

  ; ... work, with the borrowed Stack under us ...

  POPD.3
  MVDS.3                ; And put it back.
  RET                   ; Which now finds the frame exactly as it was left.
```

One last thing. An interrupt arriving while the Stack Pointer is somewhere unusual builds its frame there, so anywhere it is set has to be somewhere a Stack can actually live. And a system holding a saved Stack Pointer for a program it is running has to keep it somewhere that program cannot reach, or a program that scribbles over it takes the machine down with it on the way out.

# When Something Else Wants Attention

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

## The Vector Table:

The top kilobyte of Program Memory is reserved for vectors. Each entry is two bytes, most significant byte first, and holds a Program Memory address.

| Address | Contents |
| --- | --- |
| 0xFC00 | Software vectors 0 to 255 |
| 0xFE00 | Hardware vectors 0 to 255, one for each I/O port |

The Program Segment may not run past 0xFBFF. The assembler refuses to assemble a program that would.

The software vectors are given out like this:

| Vector | Meaning |
| --- | --- |
| 0 | The Boot Vector. Where the machine begins at power on. |
| 1 | The Soft Reset Vector. A warm restart. |
| 2 | A byte that is not an instruction. |
| 3 | A device refused a write, because it landed inside a raised fence. GuardViolation. |
| 4 | A bank was named that has nothing in it, or an access ran past its end. BankFault. |
| 5 to 15 | Held back for faults not yet defined. |
| 16 to 63 | Pinned. Numbers that separately assembled programs have to agree about, written down rather than allocated. |
| 64 and up | A program's own, given out by the assembler in the order they are named. |

A programmer almost never writes a vector number. Handlers are named in the Vector Segment of an assembly file and used by name, the same way every other address in SplitBit is worked out by the assembler rather than typed.

The exception is the range from 16 to 63, and it exists because the assembler only ever sees one program. A program calling `osExit` and the system implementing it are assembled separately, so nothing the assembler can look at ties the two together; the only thing that can is a number both sides write down. Those numbers come from that range, and the assembler never allocates one there, so a number agreed between two programs can never be handed to a third by accident. See the SplitBit Assembler Manual.

The table holds two kinds of entry, and they behave differently when they are zero.

Software vectors 0 and 1 are start addresses rather than handlers. Vector 0 is the Boot Vector: the CPU reads it at power on and begins executing there. Vector 1 is the Soft Reset Vector, for a warm restart. Nothing dispatches through either of them, and 0x0000 is an ordinary address to begin at, so a zero in one of these two means exactly what it says: start at 0x0000.

That is deliberate, and it is what lets a program that carries no vector table of its own still run. Program Memory reads as zero where nothing was loaded into it, so such a program's Boot Vector reads 0x0000, which is where its first instruction sits.

The cost of that rule is worth knowing: a machine with neither a Boot Vector nor anything at 0x0000 will start executing zeroes, and 0x00 decodes as ADD, so it will wander instead of stopping. There is no way for the CPU to tell that case apart from a program that genuinely begins at 0x0000.

Every other entry is a handler. A zero in one of those means no handler is installed, and dispatching through it is a fault rather than a jump to the bottom of memory.

The exemption for vectors 0 and 1 belongs to that one read the CPU makes at reset, not to the entries themselves. Anything that dispatches treats a zero as no handler, whichever entry it is, so SWI SoftReset through an empty Soft Reset Vector faults like any other. That is what makes SWI SoftReset the way to ask for a warm restart once one has been installed.

## Hardware Interrupts:

A device asks for attention by putting its line up. Which line it uses is not a choice: a device on port N interrupts on N, and arrives through hardware vector N. That is what spares the machine any arbitration, and it means a program can work out what a device will do by knowing where it is plugged in.

A line is answered between instructions and never inside one, so the address in the frame is always the start of an instruction.

The Interrupt Flag decides whether lines are answered at all. While it is clear, a line that goes up stays up: masking holds a device off, it does not lose what the device was asking for. The moment the flag is set, the line is answered on the very next step. Since entry clears the flag again, a handler is not interrupted while it works unless it sets the flag itself.

When several lines are up at once, the lowest numbered port is answered first. This is a scan rather than a priority scheme, so there is nothing to configure and nothing to explain: a programmer works out what happens next by reading the port numbers.

Answering a line takes it down, so a device that wants attention again has to ask again. A handler returning with RETI restores the Status register, and with it the Interrupt Flag as it was before, so anything still waiting is answered next.

If a device interrupts and its vector is empty, that is a fault: the machine stops and the emulator says which port asked and where it was.

## Faults:

If the CPU reads a byte from Program Memory that does not decode to an instruction, it dispatches through Software Vector 2.

Faults get a vector each rather than sharing one. Vector 2 is the only cause defined so far, and vectors 3 through 15 are held back for the ones that come later, so that a handler always knows what happened from the entry it arrived through. That is why the machine has no fault cause register to read.

The address in the frame is the address of the offending byte itself, not the one after it. A handler can therefore read the byte that failed and say what it was. It also means a handler that returns with a bare RETI will meet the same byte again, because resuming past a fault means deciding where to resume, and only the handler knows that.

If nothing is installed at Vector 2, the CPU sets the Fault Flag and the Halt Flag and stops, leaving the Program Counter on the offending byte. The emulator then reports the byte and its address, and exits with a non zero status.

Stopping matters because the alternative is worse. A byte that means nothing is almost always a sign that execution has wandered into data, or that a program was built for a machine with instructions this one does not have. Stepping over it and carrying on turns a clear failure into a program that appears to run and quietly does the wrong thing.

## Refusing:

A device can refuse what it was asked to do. This is not the same as interrupting. An interrupt is a device asking for attention later, answered between instructions once the CPU is ready. A refusal is a device saying no to the instruction happening now, so the machine stops where it stands rather than carrying on as though the access had worked.

A refusal names a software vector, so a handler knows what happened from the entry it arrived through, the same as every other fault. The frame carries the address of the instruction that was refused, so a handler can see which one it was.

That means a handler returning with a bare RETI will meet the same refused instruction again. A handler that means to carry on past it steps the saved address on by two, since the input and output instructions are an opcode and a port.

If nothing is installed for the vector a device refused with, the machine stops and the emulator says which port refused and where.

# What A Machine Is Made Of

## Devices:

| Port | Device | Class |
| --- | --- | --- |
| 0x00 - 0x02 | The console. See The Console. Writing to 0x00 sends a byte to standard output, reading takes one from standard input. It interrupts on 0x00, its base port, when asked to. | 0x02 |
| 0x10 | A test device. Writing anything to it puts its own line up, so that interrupt handling can be exercised without waiting on anything. The byte written is ignored. | 0x10 |
| 0x11 | A device that refuses everything, in both directions, so that refusal can be exercised without the memory controller. | 0x11 |
| 0x20 - 0x23 | The disk. See Storage. It interrupts on 0x20, its base port. | 0x13 |
| 0x12 | A device that owns 256 bytes of memory. Writing to its port fills that memory with the byte written, standing in for a disk controller reading a sector. Its memory is unreachable until it is registered as a bank. | 0x12 |
| 0xE0 - 0xEF | The memory controller. See The Memory Controller. | 0x03 |
| 0xFF | The bus registry. See Asking What Is There. | 0x01 |

## Asking What Is There:

A program that only ever runs on one machine can be told where everything is. A program meant to run on more than one has to ask, and the bus registry on port 0xFF is what it asks.

Write a port number to the registry to say which port you are asking about, then read to get that port's record a byte at a time:

| Byte | Meaning |
| --- | --- |
| 0 | The device class. Zero means there is nothing on that port. |
| 1 | Flags. Bit 0 means the device brings memory of its own. |

Reading past the end of a record gives zero, so a record can grow later without anything already written having to change. Selecting a port starts its record again from the beginning.

```
  INIA 0x03
  OUTA 0xFF         ; Ask about port 3.
  INA 0xFF          ; A is now the class of whatever is on port 3.
```

The registry answers on the device's behalf and never touches it. That is the reason it exists rather than programs simply reading each port to see what answers: reading a port is a real operation with real consequences, and reading the console to find out what it is would take a character off standard input and then wait for one that may never come.

The registry is read only. A program cannot tell it that a device exists, because saying so would not make one exist, and once a program could write to it nothing reading it could tell what is really there from what has merely been claimed. Which routine handles a device is a separate question, and the vector table already answers it: installing a driver for the device on port 3 means writing hardware vector 3.

Absence describes itself. Reading a port with nothing on it gives zero, so class zero means nothing is there. A machine with no registry at all answers zero when asked about port 0xFF, which correctly says that it cannot be enumerated. A program finds out whether it can ask by asking.

One thing to be careful of: the registry remembers which port it was asked about, so an interrupt handler that enumerates in the middle of an enumeration will lose the caller's place. Enumerate with the Interrupt Flag down, or do it before any device is enabled.

### Device Classes:

| Class | Device |
| --- | --- |
| 0x00 | Nothing. |
| 0x01 | Bus registry. |
| 0x02 | Console. |
| 0x03 | Memory controller. |
| 0x04 - 0x0F | Reserved for the machine itself. |
| 0x10 | Test device, which raises its own line. |
| 0x11 | Test device, which refuses everything. |
| 0x12 | Test device, which owns memory. |
| 0x13 | Disk. |
| 0x14 - 0xFF | Peripherals. |

## The Memory Controller:

SplitBit's instruction set cannot write Program Memory. That is what a Harvard machine is, and it is worth keeping true of the instructions: a machine where any instruction stream can rewrite its own code has given away the separation it was built for. The memory controller can, so writing code is a capability reached deliberately through a port rather than something every program has by accident.

It answers on ports 0xE0 to 0xEF, one register to a port.

| Port | Register |
| --- | --- |
| 0xE0 | SourceBank |
| 0xE1 | SourceHigh |
| 0xE2 | SourceLow |
| 0xE3 | DestBank |
| 0xE4 | DestHigh |
| 0xE5 | DestLow |
| 0xE6 | LengthHigh |
| 0xE7 | LengthLow |
| 0xE8 | Command |
| 0xE9 | Data |
| 0xEA | Status |
| 0xEB | GuardBank |
| 0xEC | GuardStartHigh |
| 0xED | GuardStartLow |
| 0xEE | GuardEndHigh |
| 0xEF | GuardEndLow |

Reading the Data port takes a byte from the source and steps the source address on. Writing to it puts a byte at the destination and steps the destination address on. Reading a run of bytes is therefore a loop over one instruction rather than four.

Status says how the last thing the controller was asked to do went. Zero means it worked; anything else is the vector it refused with.

### Commands:

Writing to the Command port performs it at once. A transfer is instantaneous as far as the CPU is concerned: waiting belongs to a peripheral that has something to wait for, not to the moving of bytes.

| Value | Command | Does |
| --- | --- | --- |
| 0x01 | Blit | Moves Length bytes from Source to Dest. Either end may be any bank, including the same one. |
| 0x02 | Fill | Writes the byte in SourceLow across Dest, Length times. SourceBank and SourceHigh mean nothing here, because a fill has nowhere to read from. |
| 0x10 | GuardOn | Raises a fence over the bank named by GuardBank, across the range in the guard registers. |
| 0x11 | GuardOff | Lowers that bank's fence. |
| 0x03 | RegisterBank | Gives the bank number in DestBank to the memory owned by the device on port SourceLow. |

Length is how many bytes, and zero means the whole 64K, since a transfer of nothing is never what anyone meant. Both commands leave the addresses past whatever they touched and leave Length as it was, so asking again carries straight on from where the last one stopped.

A blit may overlap itself. Sliding a run of bytes along inside its own bank works, rather than repeating the first byte the way a plain forward copy would.

Everything a transfer would touch is checked before any of it moves. A transfer that would run out of bank, or write somewhere it may not, is refused whole: nothing moves at all. A transfer that stopped halfway would leave memory in a state no program asked for, and the diagnostic would arrive after the damage rather than instead of it.

Filling is worth reaching for. Clearing a page with one Fill instead of a store and a loop takes about a tenth off the running time of the segmented sieve, which spends most of its life zeroing its window.

### Banks:

Memory the controller can reach is divided into banks of up to 64K each, numbered 0 to 255. Program and Data are banks like any other; being 0 and 1 is the only thing special about them.

| Bank | Holds |
| --- | --- |
| 0 | Program Memory. |
| 1 | Data Memory. |
| 2 | The controller's own memory, which is where the bank table lives. |
| 3 and up | Registered by software, for devices that bring memory of their own. |

Banks 0 to 2 belong to the machine and cannot be handed out. Everything above them is registered by whoever enumerated the hardware, so which number a device's memory answers to is the operating system's business rather than the machine's. That is what lets a device own no banks, one, or several.

Registering asks the bus registry which ports bring memory, then names one:

```
  INIA 0d5
  OUTA 0xE3         ; The bank number being handed out.
  INIA 0x12
  OUTA 0xE2         ; The port that owns the memory.
  INIA 0x03
  OUTA 0xE8         ; RegisterBank.
```

How big the bank is comes from the device, not from the program. Capacity was settled when the machine was built, so a program asserting it could only ever be wrong. Registering a bank over one that already holds something is allowed: nothing was allocated that could be lost by changing your mind.

Registering fails if the number is one of the machine's own, or if the port named brings no memory. Either would put a bank in the table that leads nowhere.

A reset clears the table back to banks 0, 1 and 2. Banks are soft state, so a program that wants a device's memory registers it during setup, which is a handful of writes and needs no operating system.

Banks are reachable only through the controller. There is no bank register that changes what the CPU sees, and there never will be: a Data Pointer addresses bank 1, always, so an instruction never means something different depending on state you cannot see in the listing.

### The Bank Table:

Bank 2 holds a description of every bank, eight bytes each, so bank n's record begins at n times eight.

| Byte | Holds |
| --- | --- |
| 0 | Flags: bit 0 present, bit 1 read only, bit 2 fenced. |
| 1 | The port that owns it, or 0xFF for the machine itself. |
| 2 and 3 | Capacity, where zero means the whole 64K. |
| 4 and 5 | The first guarded address. |
| 6 and 7 | The last guarded address. |

A program reads it the way it reads anything else, by pointing the controller at bank 2. There is no separate query for it, and nothing to interfere with an enumeration already in progress.

Bank 2 is read only. That is what keeps the table something only the controller changes, and the table is what every transfer routes through: corrupt it and everything afterwards goes somewhere arbitrary. What the table holds is a description rather than the machinery, so writing to it could never redirect a bank even if it were allowed.

### The Fence:

Every bank may have one guarded range. A write that lands inside it is refused, and so is any transfer that so much as overlaps it: a blit that clipped the edge would otherwise do the part that fitted and leave the rest undone.

Set GuardBank to say which bank, put the first and last guarded addresses in the guard registers, and write GuardOn. GuardOff lowers it again.

**Any program may lower any fence.** This is a fence rather than a wall, and nobody is ever told no. What it stops is walking into something by accident. A program that genuinely means to write there lowers the fence first, which costs one instruction and says plainly in the listing what it intended.

A fence guards writing, not reading. Whatever is behind it can still be read, because a debugger has to be able to see what it is protecting.

A range that ends before it starts is refused. No address could be inside it, so it would catch nothing while looking like it caught something, and a program that raised one would believe it was protected when it was not.

A raised fence is published in the bank table along with everything else about the bank, so a program can see what is guarded without having to remember.

### What The Fence Does Not Do:

It is worth being plain about the limit, because the name suggests more than it delivers.

Every write to Program Memory goes through the controller, so a fence over bank 0 catches all of them. That is what it is for: code that gets walked over is otherwise discovered much later, when the wreckage is finally executed, thousands of cycles from the mistake and with the evidence gone. A fence turns that into a fault at the instruction responsible, with the address still in the controller's registers to be read.

Data Memory is different. STA, STB, STQ and STD write bank 1 directly and never go near the controller, so a runaway Data Pointer walking over a program's variables is **not** caught and cannot be. Catching it would mean putting the check inside the CPU's store path, which would make an instruction behave differently depending on state that does not appear in the listing. That is the thing this machine does not do.

So the fence protects code from a mistaken loader. It is not general memory protection, and a program should not be written as though it were.

### Loading A Program:

Everything the controller does adds up to one thing a SplitBit machine could not do before: run code that was not in the boot image it started from.

The sequence is short. Put the bytes of a routine somewhere, blit them into Program Memory, write their address into a vector, and call it.

```
  ; Vector 20 lives at 0xFC00 plus twice twenty, which is 0xFC28.
  RSTA
  OUTA 0xE3         ; DestBank = 0, Program Memory.
  INIA 0xFC
  OUTA 0xE4
  INIA 0x28
  OUTA 0xE5
  OUTB 0xE9         ; The handler's address, high byte then low.
  OUTA 0xE9
  SWI 0d20
```

A vector that is empty when a program starts and holds a working handler by the time it is called is the whole reason this device exists. A vector table nothing can write is not really a vector table.

### What Loading Does Not Solve:

A routine that has been moved works at its new address only if it does not contain any addresses of its own.

INIA, OUTA and RETI name no places, so a routine built only from those runs correctly wherever it is put. A branch, a CALL, or a SETD is different: each of them carries an address that was decided when it was assembled, and that address is wrong everywhere except where it was assembled for. Nothing in SplitBit adjusts them.

So loading works and relocating does not exist. A program can be put into memory at the address it was built for, and it will run. Putting it anywhere else is an unsolved problem, and a real one, because a machine that can only ever load a program to one place cannot load two programs at once.

### Being Turned Away:

A bank knows how big it is, so an access past the end of one is a BankFault rather than a read of whatever happens to be next. Naming a bank with nothing registered in it is the same fault.

A write the controller will not perform is a GuardViolation. There are two reasons for one: the bank is read only, or the write touches a fence that has been raised over it.

Both arrive at the instruction that asked, so a handler sees which one it was. A handler that means to carry on past it steps the saved address on by two, since the input and output instructions are an opcode and a port.

## Storage:

The disk is a block device. It knows numbered blocks of 256 bytes and has never heard of a file. A filesystem is software this machine runs, not something done on its behalf: a disk that understood filenames would be the emulator doing the work while the machine pretended it had.

A block is a page, so a block number is a whole 16 bit address and the arithmetic never needs a multiply. Sixteen megabytes of them is absurd for this machine, which is the point: there is room for whatever a filesystem grows into.

| Port | Register |
| --- | --- |
| 0x20 | BlockHigh |
| 0x21 | BlockLow |
| 0x22 | Command. 0x01 reads, 0x02 writes. |
| 0x23 | Status. Bit 0 busy, bit 1 the last operation failed, bit 2 the disk is write protected. |

The disk owns one block of memory, its buffer. Reading fills it and writing takes what is in it. Like any memory a device brings, it is unreachable until it has been registered as a bank, and reachable only through the memory controller even then. The CPU never touches it directly.

A device that answers on more than one port raises its line on the first of them, so the disk interrupts on 0x20.

### Waiting:

A command returns at once and the line goes up when the block has moved. Status bit 0 says the disk is still working.

That bit always reads clear here, because the host finishes before the next instruction does. **Honour it anyway.** A machine with a slower disk would set it, and a program written to ignore it would work on this one and fail on that one. Waiting for the line is the other way, and the right one once vectors are installed; the bit is what a bootstrap polls before there are any.

### Write Protection:

A disk may be read only, and the bar is in the device. Status bit 2 says so.

That bit is not like the two below it. Busy and error describe the last operation; **protection describes the medium**, so it reads true before anything has been asked of the disk at all. A program can find out whether it can write without having to try and be refused.

The bar being in the device is the point of it. A flag in a superblock can be got around by writing blocks directly, and this cannot be got around at all. It is the tab on the side of a floppy rather than a note asking politely.

A disk is read only if it was attached that way, or if the host will not let its image be written. The machine cannot tell those two apart, and has no reason to.

Reading a protected disk is ordinary and does not disturb the bit.

### When It Does Not Work:

Status bit 1 says the last operation failed: there is no disk, or the block asked for is not on it.

A disk error is not a fault. Faults on this machine mean it cannot continue, and a read that fails is an ordinary thing that happens to working programs on failing media. It is reported so that a program can cope with it, rather than stopping the machine and taking the choice away.

