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
 	 - The SP is moved by the push and pop instructions, by CALL and RET, and by an interrupt arriving or returning. MVSD copies it out without moving it, and MVDS sets it outright. See The Stack Pointer, Set By Hand below before using MVDS.
 	 - The Stack lives in Data Memory, so a Data Pointer can be aimed at it and used to read what is on it. MVSD is how a program finds out where to aim.

 - The Status register is an 8 bit register whose various bits are used as flags. Only four of these flags are used in the current implementation.
	 - Bit 0 is the Carry/Borrow Flag. Any arithmetic operation either sets or clears it depending on whether or not the result causes Q to overflow/underflow. It is a 1 if a carry/underflow occurred, and a 0 otherwise. If A or B overflows or underflows from the use of an increment or decrement instruction, this flag will also be set. Non-overflowing increments or decrements will also reset it.
	 - Bit 1 is the Fault Flag. It is set when the CPU cannot get past something and no handler was installed to deal with it: a byte that is not an instruction, or a dispatch through an empty vector. See Faults below.
	 - Bit 2 is the Interrupt Flag. It is set by SIF and cleared by CIF. While it is set the CPU answers devices asking for attention; while it is clear they wait. Arriving at a handler clears it, and RETI restores it along with the rest of the Status register. See Hardware Interrupts below.
	 - Bit 7 is the Halt Flag. It is set by the HALT instruction, and by a fault.

Each condition has a branch both ways round, so a loop that carries on while something is not zero is one instruction rather than a branch over an unconditional one. Before these existed a quarter of every conditional branch in the corpus was written backwards and padded out, and each of those needed a label invented only to be jumped past.

A conditional branch reads the thing it names at the moment it runs. BRA looks at A, and it does not matter which instruction set A or how long ago. The two that read the Carry Flag are the exception, and they say so in their names. That is worth knowing when reading somebody else's code: nothing else on this machine leaves a hidden condition behind for a later branch to find.

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
| 0x00 - 0x02 | The console. See The Console below. Writing to 0x00 sends a byte to standard output, reading takes one from standard input. It interrupts on 0x00, its base port, when asked to. | 0x02 |
| 0x10 | A test device. Writing anything to it puts its own line up, so that interrupt handling can be exercised without waiting on anything. The byte written is ignored. | 0x10 |
| 0x11 | A device that refuses everything, in both directions, so that refusal can be exercised without the memory controller. | 0x11 |
| 0x20 - 0x23 | The disk. See Storage below. It interrupts on 0x20, its base port. | 0x13 |
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

### Being Turned Away:

A bank knows how big it is, so an access past the end of one is a BankFault rather than a read of whatever happens to be next. Naming a bank with nothing registered in it is the same fault.

A write the controller will not perform is a GuardViolation. There are two reasons for one: the bank is read only, or the write touches a fence that has been raised over it.

Both arrive at the instruction that asked, so a handler sees which one it was. A handler that means to carry on past it steps the saved address on by two, since the input and output instructions are an opcode and a port.

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

## Reading And Writing The Filesystem:

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

Which is why saving a document is not the same as writing a file, and why sbfsSaveFile exists rather than each tool doing it. A file that has grown will usually not fit where it was, so saving it means putting it somewhere else and letting go of where it was — and **the obvious order is a trap**:

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

**That is what renaming is for.** It looks like a convenience and it is the safety mechanism: it is the only one of the three operations that moves no data — a name lives in the directory entry, so renaming writes twenty two bytes into one block — which makes it the only one that can be left until last and relied on not to fail.

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

## What A Program May Ask The System For:

A loaded program is on its own hardware and can do anything the machine can do — it is a fence, not a wall. But the things it usually wants are things the system is already doing, and asking is both shorter and the only way to reach code that was assembled separately. `CALL` needs a label, and a label has to be in the same assembly; `SWI` needs only a number both sides agree on.

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
A 11 B 22 Q 00 S 00
DP0 1030 DP1 05AE DP2 039A DP3 2000
press a key
```

Every value comes out of the interrupt frame rather than out of the registers, because by the time the handler runs the registers belong to the handler. The frame is what the program had and what RETI is about to give back, so what is shown is what will be resumed with. The address is two before where it resumes: the `SWI` and the vector it names.

**Nothing is overwritten, and that is the whole of why it is simple.** A breakpoint poked into a running program has to replace an instruction, and putting that instruction back in order to continue is the same act as disarming the breakpoint. Firing a second time would mean stepping over the restored instruction and putting the breakpoint back behind it, and this machine has no way to step a single instruction. Two bytes of `SWI` cost a little space and fire for ever, because there was never anything to restore.

The price is that a breakpoint is part of the program. A build with breakpoints in it has different addresses from a build without — the same bargain every machine makes that has a break instruction.

### The Disk Without A Filesystem:

A program that wants a file does not need to know what a filesystem is. Before these existed it had to include the whole of `sbfs.asm` — two and a half kilobytes of a private copy of code the system already had running — and then mount a disk that was already mounted.

There is no service to mount one, and that is not an omission. The system mounts the disk before it reads its first prompt, and there is one disk with one buffer registered as one bank; a program mounting it again was only ever an artefact of owning a second copy of the library. That call disappears rather than moving.

Sizes fit the registers exactly, in both directions. A file that can be read into Data Memory is under 64K by definition, so its length is sixteen bits: coming back it is DP3, and going out it is A and B together. Neither direction needs a record in memory whose shape both sides have to agree on.

A file of 256 blocks or more is refused by `osFileRead` rather than partly read, because 64K will not fit in Data Memory and its length will not fit in the pointer that reports it. A length that lies would be worse than a file that will not open.

`Programs/CosmOS/Apps/Files.asm` does the whole round trip — write, read, report, rename, delete — in 645 bytes, and includes nothing but the service names.

`osArgument` is how a program is told what it is for. Everything written before it did the same thing however it was started, which is fine for a program that greets you and no use to one that edits a named document. What arrives is the whole rest of the line, spaces and all, rather than a list of words: what counts as an argument is the program's business, and handing over what was typed is the system's.

A handler is entered with the caller's registers exactly as they were, because an interrupt frame is pushed rather than cleared. That is why a service can be given a pointer in DP0 and a count in B without any of it being copied anywhere first.

### How A Service Answers:

The same thing that makes an interrupt safe makes a service mute. RETI restores every register from the frame, so whatever a handler worked out is thrown away on the way out — which is exactly right for a device interrupting at a moment nobody chose, and useless for a service that was asked a question.

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

**Only the handler itself can do this.** The offsets are from wherever the Stack Pointer is, and a CALL moves it by ten — so a routine called by a handler that tried the same thing would be writing into its own return address. The poke belongs inline, next to the RETI.

A service that has nothing to say does nothing, and the caller's registers arrive back untouched. That is worth knowing from the other side too: a service cannot corrupt a register by accident, only by deciding to.

## Loading A Program From A Disk:

A program that was not the one the machine booted from carries sixteen bytes in front of it saying where it belongs.

| Offset | Size | Holds |
| --- | --- | --- |
| 0 | 4 | SBEX |
| 4 | 1 | Version. One, or two if it brings vectors. |
| 5 | 1 | How many vectors follow the data. Zero in a version one file. |
| 6 | 2 | Where the code goes in Program Memory. |
| 8 | 2 | Where to start running. |
| 10 | 2 | How many bytes of code there are. |
| 12 | 2 | Where the data goes in Data Memory. |
| 14 | 2 | How many bytes of data there are. |
| 16 | | The code, then the data, then the vectors. |

Programs/loader.asm reads one off a disk, puts the two pieces where the header asks, and jumps to the entry with BRD. Every part of that already existed: the filesystem finds the file, the memory controller writes Program Memory, and BRD turns an address worked out at run time into somewhere to go. The header is the only new thing. Programs/CosmOS does the same as one of its commands, and then takes the machine back afterwards, which the standalone loader has no way to do.

The magic matters for the same reason it does everywhere else on this machine. Without it, loading a text file would put nonsense into Program Memory and then jump into it.

### Bringing Vectors:

A program that only wants to be run needs nothing here and says version one. A program that wants a handler installed needs something of whoever loads it, and says version two.

Each vector is four bytes: the address of the slot in the vector table, then the address to put in it, both most significant byte first. Naming the slot rather than the vector number means the loader does no arithmetic and does not have to know where either vector table begins, and one entry can be a software or a hardware vector without saying which it is.

**A version two file is refused by a loader that cannot install them.** That is the point of the version rather than an inconvenience of it. A program whose handlers were quietly dropped would load, run, and then go wrong somewhere with nothing to connect the failure back to loading — a game waiting for keys that no longer arrive. Failing once, at load, with a reason, is worth more than running.

**Whoever installs them takes them back.** A vector points into the program that supplied it, so one left in the table after that program has gone aims an interrupt at whatever occupies those addresses next. CosmOS keeps its own copy of what a program brought, puts them in when the program is run and not when it is loaded, and restores what was underneath them when the program gives the machine back. Restoring, rather than clearing: a program is allowed to install a handler over one the system was already using, and when it goes, what it covered up has to come back rather than become a hole.

`Boot` in a loadable program fills in the entry field, since that is what it means, and is not installed as vector 0 — where the machine starts is not a loaded program's business. Without one, a program begins at the first byte of its code.

### Where A Program Says It Lives:

**Nothing relocates anything.** A program is put exactly where its header asks, and that has to be the address it was assembled for, or every branch and every SETD inside it points somewhere wrong.

A program says where it lives with #Base, at the top of each segment. Every label inside is then resolved from there, so the addresses in the program and the addresses in its header say the same thing. Giving either segment a base is also what makes the assembler write the program out as a loadable one rather than as a boot image, carrying none of the empty space below it.

```
#Program
  #Base 0x2000          ; This program's code lives from 0x2000.
hello:
  ...

#Data
  #Base 0x1000          ; And its data from 0x1000.
```

That is not general placement: a base applies to a whole segment, and only the first thing in one can set it. It is exactly enough for a program that wants to live at one address, which is what a loadable program is. See the Assembler Manual.

Whoever does the loading keeps its own code and data below the addresses the loaded program claims. That is an arrangement between the two of them rather than anything the machine enforces. Programs/CosmOS is where that arrangement is written down as a memory map and kept to.

## Programs That Come With The System:

`Programs/CosmOS/Apps` holds what the shell can load. Several are old programs written for the bare machine that needed five edits each to become loadable ones — the Fibonacci and sieve programs, `greet`, and `hello`. The rest were written for the system as it is now, and each of those exists to show one thing working:

| Program | What it is for |
| --- | --- |
| Life | Conway's Game of Life, which had to be taught to stop, since a program that never ends takes the shell with it. Polls the console between generations. |
| Snake | A game. Draws a whole screen with cursor addressing and steers with single keys, asking the console once a frame and never waiting. |
| Keys | The console interrupting rather than being asked. The only one that brings a vector of its own, which is what the version two format exists for. |
| Say | Prints whatever it was told, which is the shortest thing that shows osArgument working. |
| Files | Writes a file, reads it back, renames it and deletes it, in 645 bytes, including nothing but the service names. It is what says a program does not need a filesystem inside it. |
| Break | Stops itself twice with SWI osBreak, so that the registers can be seen changing between one stop and the next. |
| Edit | A line editor. |

### The Monitor:

The monitor is **part of the shell**, not a program the shell loads, and that is the whole reason it works. A loaded program occupies the one place a loaded program goes, so a monitor that was an application could never look at any other application: loading the thing you wanted to inspect would replace the thing doing the inspecting.

`monitor` turns it on and the prompt changes from `>` to `*`. It is **a mode, not a detour** — the shell's own commands still work, and the mode persists until you say otherwise:

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

`exit` leaves whatever you are in — the monitor if you are in it, the machine if you are not.

| | |
| --- | --- |
| `x [addr]` | Sixty-four bytes, as hex and as characters |
| `d [addr]` | Eight instructions, disassembled |
| `s addr b b …` | Put those bytes there |
| `b program\|data\|n` | Which bank to look at |
| `g addr` | Go there |

`x` and `d` share one cursor and each leaves it past what it showed, so without an address either carries on — reading through memory is one letter at a time, and you can switch between bytes and instructions without retyping where you are. `s` deliberately does not move it.

Everything else here does something; the monitor looks at what the others did. It shows memory as hex and as characters, disassembles it, writes bytes into it, and jumps to an address — all through the memory controller, which is the only thing that can reach Program Memory.

That is why a monitor is worth more on this machine than on most. Data Memory a program can already read for itself with a Data Pointer. The half it cannot see is Program Memory, and that is the half its bugs are in.

**Its instruction table is generated from the assembler's**, by `Tests/instructiontable.py`, and checked against it by `Tests/docs.sh` — along with a second check that the lengths that table implies are the ones the manual's own Bytes column prints. Both matter for the same reason: a disassembler that disagreed about how long an instruction is would not print one line wrong, it would lose its place and print everything after it wrong. Which is what a disassembler does anyway when it starts in the middle of an instruction, and is worth seeing once so it is recognised later.

**Where to put something you typed in yourself** is a question the monitor answers, because the answer moves every time the monitor is rebuilt. `m` says where its own two segments end, and those are the first free addresses:

```
> m
code from 2000, free from 2607
data from 1000, free from 1367 up to the stack
```

Which is what makes the monitor's real trick possible — a program that no assembler ever saw:

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

`Edit` is the first program on this machine that makes a file a person typed — every byte on every disk before it was put there by the host tool. It is line oriented in the manner of `ed`: `l` lists, `a` adds at the end, `i` and `c` and `d` take a line number, `w` writes and `q` stops.

It includes nothing but `services.asm` and `text.asm`: the filesystem and the console are the system's, asked for rather than carried. That is what took it from 4,941 bytes to 1,983 without a line of its own logic changing — and the way that was checked is worth knowing, because the recorded output of the `cosmosEdit` test did not move by a single byte across the rewrite.

It keeps the document as a **linked list of lines** rather than one buffer with newlines in it. Each line says where the next one is, how long it is, and then its bytes. Inserting is two pointers changed and nothing moved; with a flat buffer it would mean shifting every byte after the edit, on a machine whose only block move is a device asked politely. The price is that deleted lines are not reused, so a heavy session uses more room than the document needs and writing it out is what tidies up.

Saving goes through `sbfsSaveFile`, so a document that has grown is written somewhere else and the original is only let go of once the new one is safely down. That is the whole reason the editor was written: not because the machine needed an editor, but because every tool that produces a file needs the same four operations, and building them for one imaginary tool is how they end up wrong.

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

## Input and Output In the Emulator:

Port 0 is the console: writing sends a byte to standard output and reading takes one from standard input. It answers on two more ports than that, which are described under The Console above and which a program can ignore entirely if all it wants is to read and write bytes. Everything else this machine has is listed under Devices above, and a program that wants to know what is actually there asks the bus registry rather than assuming.

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

After the header come the segments. The Program Segment comes first and then the Data Segment, each beginning with a three character marker, `PRG` or `DAT`, followed by a two byte length. The system loads each memory with the bytes that follow, in sequence, starting from address 0x0000.

A third segment may follow them, marked `VEC`, holding the vectors a program named in its Vector Segment. It is four bytes an entry: two saying where in Program Memory the vector sits, and two saying where its handler is. A program that named no vectors has no such segment, and a file that simply ends after its Data Segment is one written before vectors existed. Either way the reader treats the end of the file as an empty table, which is why adding this cost no format version and left every binary already written still loadable.

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
