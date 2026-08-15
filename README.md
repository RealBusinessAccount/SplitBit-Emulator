# SplitBit Emulator

## Overview:
SplitBit is a custom CPU designed for hobbyist projects and experimentation. The SplitBit Emulator is a C implementation of its bespoke instruction set architecture. It allows users to load and run binary programs created for the SplitBit CPU interactively from the command line.

### Features:
- 8-bit Harvard Architecture: The system memory is separated into two 64k banks, one for the Program Memory and another for the Data Memory.
- Custom ISA: A fully implemented instruction set architecture optimized for simplicity and easy assembly programming.
- Debug Mode: Single-step through instructions and monitor the CPU's registers as they change through each cycle.
- CLI Based: Debug messages and CPU input and output are supported through the command line.
- Binary File Support: Load programs and data from binary files.
- Modular Codebase: Mostly clean separation of CPU, I/O, and utility functions for easy modification.
- Assembler: Assemble human readable assembly language files directly into SplitBit compatible binary files. Supports including external files, handling labels, and defining Program and Data segments.

### Installation:
1) Clone the repository:
```
git clone https://github.com/RealBusinessAccount/SplitBit-Emulator.git
cd SplitBit-Emulator
```
2) Build the Emulator and the Assembler: You'll need gcc and make or similar.
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
- -h, --help: Show help and usage information.

#### Notes:
- If the CPU reads a byte that is not an instruction, it goes to the fault handler the program installed. If it installed none, it raises the Fault Flag and halts, and the emulator reports the byte and the address it was found at and exits with a non zero status. The same happens if a program or a device asks for a handler that was never installed.

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
