# SplitBit Emulator

## Overview:
SplitBit is a custom 8 bit system designed for hobbyist projects and experimentation: a CPU with its own instruction set, an interrupt and vector system, a bus that programs can enumerate, and a memory controller that can load code. The SplitBit Emulator is a C implementation of it. It allows users to load and run binary programs created for SplitBit interactively from the command line.

### Features:
- 8-bit Harvard Architecture: The system memory is separated into two 64k banks, one for the Program Memory and another for the Data Memory.
- Custom ISA: A fully implemented instruction set architecture optimized for simplicity and easy assembly programming.
- Debug Mode: Single-step through instructions and monitor the CPU's registers as they change through each cycle.
- CLI Based: Debug messages and CPU input and output are supported through the command line.
- Binary File Support: Load programs and data from binary files.
- Modular Codebase: Mostly clean separation of CPU, I/O, and utility functions for easy modification.
- Interrupts: Software traps, hardware lines from devices, and faults, all arriving through one vector table with a full context save.
- Devices: A bus registry that says what a machine is made of, so a program can ask rather than being told.
- Filesystem: SBFS, read and written by SplitBit itself, and by a host tool that speaks the same format so an image can be moved either way.
- Loadable Programs: A program that was not booted from carries a header saying where it belongs, and Programs/loader.asm reads one off a disk, puts it there, and runs it.
- Storage: A block device with 256 byte blocks and 16 megabytes of them, backed by an image file on the host. It knows blocks and not files, because a filesystem is meant to be software SplitBit runs.
- Memory Controller: Reads and writes Program Memory, moves blocks between memory banks, reaches memory that devices bring with them, and guards a range against being written by accident. It is how a SplitBit machine loads a program.
- Assembler: Assemble human readable assembly language files directly into SplitBit compatible binary files. Supports including external files, handling labels, alignment and reservation, and defining Program, Data and Vector segments.

### Installation:
1) Clone the repository:
```
git clone https://github.com/RealBusinessAccount/SplitBit-Emulator.git
cd SplitBit-Emulator
```
2) Build the Emulator, the Assembler and the disk tool: You'll need gcc and make or similar.
```
make
```
The sources are ISO C, and build clean under -std=c11 -pedantic with -Wall -Wextra. Beyond ISO C they need POSIX.1-2008, which the makefile asks for by name, and getopt_long for the long form of the command line options.
3) Assemble a program:
```
./Assembler Programs/hello.asm
```

4) Run the program:
```
./SplitBit hello.bin
```

### Usage:
```
./SplitBit [options] [binary file]
```
#### Options:
- -d, --debug: Enable debug mode to single step through cycles. Each key press advances one instruction.
- -c, --cycles N: Stop after N cycles rather than running until the program halts. Useful for programs that never halt, and for getting the same output from a run every time.
- -f, --fast: Run as fast as the host machine allows, ignoring the emulated cycle rate.
- -D, --disk \<file\>: Attach a disk image, creating a 128K one if the file is not there.
- -W, --write-protect: Attach the disk read only. A disk whose image the host will not let you write is read only whether you ask for this or not.
- -h, --help: Show help and usage information.

#### Notes:
- If the CPU reads a byte that is not an instruction, it goes to the fault handler the program installed. If it installed none, it raises the Fault Flag and halts, and the emulator reports the byte and the address it was found at and exits with a non zero status. The same happens if a program or a device asks for a handler that was never installed.

### Usage:
```
./SplitDisk <command> <image> [arguments]
```
#### Commands:
- format \<image\> [blocks] [dirblocks]: Lay down a fresh filesystem. 512 blocks and 8 of directory by default, which is 128K and room for 64 files.
- list \<image\>: Show what is on the disk.
- put \<image\> \<file\> [name]: Put a host file onto it. Without a name it uses the file's own, which is often longer than the 22 characters a name may be.
- get \<image\> \<name\> [file]: Take one off it.
- delete \<image\> \<name\>: Remove one.

#### Notes:
- SplitDisk speaks the same on disk format SplitBit does, so an image it makes is one the machine can read, and one the machine writes is one it can read back. Until SplitBit can write its own filesystem this is the only way to get a program onto a disk.
- Files are laid down contiguously, so a disk can have free blocks without having them in one piece. When that happens put says so rather than putting part of a file on.

### Usage:
```
./Assembler [options] [assembly file]
```
#### Options:
- -o \<file\>: Write the binary to this path.
- -I \<dir\>: Look in this directory for included files. May be given more than once.
- -M \<file\>: Write out which source files the binary depends on, as a make rule.
- -h, --help: Show help and usage information.

#### Notes:
- Without -o, the assembled binary is saved with the same name as the assembly source file, with a .bin extension, in the directory that you call the assembler from.
- Included files are looked for beside the file that includes them, and then along the directories given with -I.

### Building Programs With Make:
The assembler is built to work with make. The -o option puts the binary where the build system wants it, and -M writes out which libraries went into it, so that editing a library reassembles everything that includes it.

Programs/makefile does this for the programs in this repository:
```
cd Programs
make
```

The rule it uses is small enough to copy into your own projects:
```
$(BUILD)/%.bin: %.asm
	@mkdir -p $(@D)
	$(ASM) -I Libraries -M $(@:.bin=.d) -o $@ $<

-include $(BINARIES:.bin=.d)
```

### Tests:
The test suite assembles and runs every program in Programs/ and compares the results against recorded output.
```
make test
```
Disk images that tests read from are built by Tests/makedisks.sh before the run, using SplitDisk. A test that reads one is therefore checked against a filesystem written by different code from the same written format, rather than against itself.

The disk tool is checked separately by Tests/disk.sh, which make test runs afterwards: it puts files of every awkward size onto an image and takes them off again, and checks that the things the format says cannot happen are refused.

Tests/terminal.sh checks the things a recorded output cannot see. Every other test pipes input in and output to a file, which answers what a program prints and is blind to two whole classes of behaviour: **when** something is printed, since piped output is buffered and flushed at exit, so a prompt shown before its answer is asked for and one shown an hour late produce identical files; and **what happens to the terminal**, since key mode only touches one when there is one. Both have gone wrong here, and both were found by a person whose terminal stopped working rather than by anything in this suite. So it runs the emulator under a pseudo-terminal and asks the questions directly: that a prompt arrives before input is read, that a keystroke arrives without Return, that the terminal is handed back however the machine dies, and that suspending and resuming leave it as they found it.

A cycle count is deliberately **not** part of a recorded result. The last line of the emulator's output has the number taken out of it before anything is compared, keeping only whether the program stopped on its own or ran into its limit, which is behaviour. Two instructions added to CosmOS used to move that number in six unrelated files at once, so a real difference would arrive in a crowd of meaningless ones. Anything that wants to measure cycles should say so in a test of its own.

Tests/docs.sh then checks the manuals against the code: that every instruction has a row and every row is an instruction, that the counts in the headings are right, that every directive is written down, that every routine the manuals promise exists, and that the worked examples still assemble to the bytes printed beside them. Documentation goes stale quietly, and this is what stops it.

Tests are defined in Tests/manifest, one line per program. To record the current output as the expected result, after you have checked that it is correct:
```
make bless
```
Programs are built inside Tests/build, so running the suite never overwrites the binaries in Programs/. To run only some of the tests, call the runner directly with their names:
```
./Tests/run.sh hello 8bitFibonacci
```

To rebuild both tools with the address and undefined behaviour sanitizers and run the suite under them:
```
make sanitize
```
This catches reads and writes past the end of an array, use after free, leaks, and undefined arithmetic. It also fills fresh allocations with a junk pattern, which turns a read of uninitialised memory from something that quietly works into something the tests notice. It takes about twice as long as make test, and puts the ordinary binaries back when it finishes.

### Additional Info:
For more information on the custom ISA and programming for SplitBit, see the Programming Manual and Assembler Manual.

### License:
This project is licensed under the Apache License, Version 2.0. You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0).
