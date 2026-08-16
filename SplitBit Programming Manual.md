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
| 3 | A device refused a write, because it landed inside a raised fence. GuardViolation. |
| 4 | A bank was named that has nothing in it, or an access ran past its end. BankFault. |
| 5 to 15 | Held back for faults not yet defined. |
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

| Port | Device | Class |
| --- | --- | --- |
| 0x00 | The console. Writing sends a byte to standard output, reading takes one from standard input. | 0x02 |
| 0x10 | A test device. Writing anything to it puts its own line up, so that interrupt handling can be exercised without waiting on anything. The byte written is ignored. | 0x10 |
| 0x11 | A device that refuses everything, in both directions, so that refusal can be exercised without the memory controller. | 0x11 |
| 0x12 | A device that owns 256 bytes of memory. Writing to its port fills that memory with the byte written, standing in for a disk controller reading a sector. Its memory is unreachable until it is registered as a bank. | 0x12 |
| 0xE0 - 0xEF | The memory controller. See The Memory Controller below. | 0x03 |
| 0xFF | The bus registry. See Asking What Is There below. | 0x01 |

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
| 0x13 - 0xFF | Peripherals. |

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

### Loading A Program:

Everything the controller does adds up to one thing a SplitBit machine could not do before: run code that was not in the binary it started from.

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

### What The Fence Does Not Do:

It is worth being plain about the limit, because the name suggests more than it delivers.

Every write to Program Memory goes through the controller, so a fence over bank 0 catches all of them. That is what it is for: code that gets walked over is otherwise discovered much later, when the wreckage is finally executed, thousands of cycles from the mistake and with the evidence gone. A fence turns that into a fault at the instruction responsible, with the address still in the controller's registers to be read.

Data Memory is different. STA, STB, STQ and STD write bank 1 directly and never go near the controller, so a runaway Data Pointer walking over a program's variables is **not** caught and cannot be. Catching it would mean putting the check inside the CPU's store path, which would make an instruction behave differently depending on state that does not appear in the listing. That is the thing this machine does not do.

So the fence protects code from a mistaken loader. It is not general memory protection, and a program should not be written as though it were.

### Being Turned Away:

A bank knows how big it is, so an access past the end of one is a BankFault rather than a read of whatever happens to be next. Naming a bank with nothing registered in it is the same fault.

A write the controller will not perform is a GuardViolation. There are two reasons for one: the bank is read only, or the write touches a fence that has been raised over it.

Both arrive at the instruction that asked, so a handler sees which one it was. A handler that means to carry on past it steps the saved address on by two, since the input and output instructions are an opcode and a port.

## Refusing:

A device can refuse what it was asked to do. This is not the same as interrupting. An interrupt is a device asking for attention later, answered between instructions once the CPU is ready. A refusal is a device saying no to the instruction happening now, so the machine stops where it stands rather than carrying on as though the access had worked.

A refusal names a software vector, so a handler knows what happened from the entry it arrived through, the same as every other fault. The frame carries the address of the instruction that was refused, so a handler can see which one it was.

That means a handler returning with a bare RETI will meet the same refused instruction again. A handler that means to carry on past it steps the saved address on by two, since the input and output instructions are an opcode and a port.

If nothing is installed for the vector a device refused with, the machine stops and the emulator says which port refused and where.

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
