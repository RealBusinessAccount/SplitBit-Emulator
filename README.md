# SplitBit

SplitBit is an 8 bit computer that does not exist: a CPU with its own instruction set, split Program and Data memories, an interrupt and vector system, a bus that programs can enumerate, a memory controller that can write code into memory, and a disk. This repository is a C implementation of the machine, an assembler for it, a tool for its disks, and the software that runs on it, which now includes an operating system and an assembler written in SplitBit's own assembly language.

**SplitBit assembles SplitBit.** [`Programs/CosmOS/Assembler/`](Programs/CosmOS/Assembler) runs on the machine, reads source off a SplitBit disk, and writes a boot image or a loadable program back to it with no host involved. It builds the operating system it is running under, and it builds itself, both byte for byte identical to what the C assembler produces from the same source. The test suite then boots the CosmOS that CosmOS built and has *that* one assemble CosmOS again, and the second generation is identical to the first, so the machinery has been through itself. After that the host is a convenience rather than a necessity.

```
> load Asm.sbx
> run cosmos.asm
wrote cosmos.bin: program 7036, data 2448, labels 475
> run Asm.asm
wrote Asm.sbx: program 7533, data 4099, labels 555
```

## What Is In Here:

| Directory | What it holds |
| --- | --- |
| [`Source/Emulator`](Source/Emulator) | The machine: CPU, memory controller, devices, console, disk |
| [`Source/Assembler`](Source/Assembler) | The assembler that runs on a host |
| [`Source/DiskTool`](Source/DiskTool) | SplitDisk, which reads and writes SplitBit's filesystem |
| [`Programs/Examples`](Programs/Examples) | Programs to read: hello, a calculator, Fibonacci, a prime sieve, Life |
| [`Programs/Libraries`](Programs/Libraries) | Code included by name rather than linked, since there is no linker |
| [`Programs/Loader`](Programs/Loader) | The standalone loader CosmOS grew out of |
| [`Programs/CosmOS`](Programs/CosmOS) | The operating system, its applications, and the native assembler |
| [`Programs/testPrograms`](Programs/testPrograms) | What the test suite drives |
| [`Tests`](Tests) | The suite: the manifest, the recorded output, and the scripts that check it |

## The Machine:

- **Harvard architecture.** Two 64K memories, one for instructions and one for data. An instruction can only read the second, which is why strings live there and why the memory controller exists.
- **Its own instruction set**, 64 instructions, four Data Pointers, and a Q register that holds what the ALU last worked out. Small enough that the table describing it fits in the machine's own memory, which is what lets it disassemble and assemble for itself.
- **Interrupts.** Software traps, hardware lines from devices, and faults, all arriving through one vector table with a full context save.
- **A bus programs can enumerate**, so a program can ask what a machine is made of rather than being told.
- **A memory controller** that reads and writes Program Memory, moves blocks between banks, reaches memory that devices bring with them, and guards a range against being written by accident. It is how a SplitBit machine loads a program.
- **Storage**: a block device with 256 byte blocks and up to 16 megabytes of them, backed by an image file. It knows blocks and not files, because a filesystem is meant to be software SplitBit runs.

## The Software:

- **SBFS**, a filesystem read and written by SplitBit itself and by a host tool that speaks the same format, so an image can be moved either way and each implementation checks the other.
- **CosmOS**, an operating system: it boots the machine, mounts a disk, lists what is on it, loads a program and runs it, and takes the machine back when the program finishes. It comes with a library of programs including a game, a line editor, and a monitor that examines memory, disassembles, assembles a line at a time, and sets breakpoints.
- **Loadable programs.** A program that was not booted from carries a header saying where it belongs, and may bring interrupt handlers of its own for the loader to install and take back again.
- **System services.** A loaded program reaches the console and the disk through numbered software interrupts rather than carrying a copy of the code that drives them. The numbers are written down in one file both sides include, so neither ever types one. It took the editor from 4941 bytes to 1983 without changing a line of what it does.
- **Streaming reads.** A file bigger than the machine's memory is read a block at a time, through services that keep nothing open between calls. CosmOS's own source is far larger than its 64K of Data Memory, and this is what the native assembler stands on.

## Getting Started:

Clone it and build the three tools. You need gcc and make, or similar:

```
git clone https://github.com/RealBusinessAccount/SplitBit-Emulator.git
cd SplitBit-Emulator
make
```

The sources are ISO C and build clean under `-std=c11 -pedantic` with `-Wall -Wextra`. Beyond ISO C they need POSIX.1-2008, which the makefile asks for by name, and `getopt_long` for the long form of the command line options.

Building needs nothing else. **Running the tests needs `bash` and Python 3**, because two of the checking scripts are Python and one of them opens a pseudo-terminal to ask questions a recorded file cannot answer. They also use `stty`, `timeout`, and the usual text utilities: `sed`, `awk`, `grep`, `cmp`, `diff`, `tr`, `sort`, `wc`.

Assemble something and run it:

```
./Assembler Programs/Examples/hello.asm
./SplitBit hello.bin
```

Or boot the operating system, with a disk of programs and all of its own source on it:

```
cd Programs
make run-cosmos
```

Then `dir` to see what is there, `load Snake.sbx` and `run` to play something, or `load Asm.sbx` and `run cosmos.asm` to watch the machine build itself.

## Running Programs: SplitBit

```
./SplitBit [options] [boot image]
```

| Option | What it does |
| --- | --- |
| `-d`, `--debug` | Single step through cycles. Each key press advances one instruction. |
| `-c`, `--cycles N` | Stop after N cycles rather than running until the program halts. Useful for programs that never halt, and for getting the same output from a run every time. |
| `-f`, `--fast` | Run as fast as the host allows, ignoring the emulated cycle rate. |
| `-D`, `--disk <file>` | Attach a disk image, creating a 128K one if the file is not there. |
| `-W`, `--write-protect` | Attach the disk read only. A disk whose image the host will not let you write is read only whether you ask for this or not. |
| `-h`, `--help` | Show help and usage information. |

If the CPU reads a byte that is not an instruction, it goes to the fault handler the program installed. If it installed none, it raises the Fault Flag and halts, and the emulator reports the byte and the address it was found at and exits with a non zero status. The same happens if a program or a device asks for a handler that was never installed.

## Assembling: Assembler

```
./Assembler [options] [assembly file]
```

| Option | What it does |
| --- | --- |
| `-o <file>` | Write the output to this path. |
| `-I <dir>` | Look in this directory for included files. May be given more than once. |
| `-M <file>` | Write out which source files the output depends on, as a make rule. |
| `-h`, `--help` | Show help and usage information. |

Without `-o` the output takes the source file's name, in the directory you called the assembler from, with the extension the format asks for: `.bin` for a boot image and `.sbx` for a loadable program. Included files are looked for beside the file that includes them, and then along the directories given with `-I`.

## Managing Disks: SplitDisk

```
./SplitDisk <command> <image> [arguments]
```

| Command | What it does |
| --- | --- |
| `format <image> [blocks] [dirblocks]` | Lay down a fresh filesystem. 512 blocks and 8 of directory by default, which is 128K and room for 64 files. |
| `list <image>` | Show what is on the disk. |
| `put <image> <file> [name]` | Put a host file onto it. Without a name it uses the file's own, which is often longer than the 22 characters a name may be. |
| `get <image> <name> [file]` | Take one off it. |
| `delete <image> <name>` | Remove one. |

SplitDisk speaks the same on disk format SplitBit does, so an image it makes is one the machine can read, and one the machine writes is one it can read back. It is a convenience rather than a necessity: SplitBit writes its own filesystem, and now assembles its own programs, so a disk can be filled without leaving the machine.

Files are laid down contiguously, so a disk can have free blocks without having them in one piece. When that happens `put` says so rather than putting part of a file on.

## Building Programs With Make:

The assembler is built to work with make. `-o` puts the output where the build system wants it, and `-M` writes out which libraries went into it, so that editing a library reassembles everything that includes it.

`Programs/makefile` does this for the programs in this repository:

```
cd Programs
make
```

The rule it uses is small enough to copy into your own projects:

```
$(BUILD)/%.bin: %.asm
	@mkdir -p $(@D)
	$(ASM) $(INCLUDES) -M $(@:.bin=.d) -o $@ $<

-include $(BINARIES:.bin=.d)
```

## Tests:

```
make test
```

The suite assembles and runs every program in `Programs/` and compares the results against recorded output. Tests are defined in `Tests/manifest`, one line per program. To record the current output as the expected result, after you have checked that it is correct:

```
make bless
```

Programs are built inside `Tests/build`, so running the suite never overwrites anything in `Programs/`. To run only some of the tests, call the runner directly with their names:

```
./Tests/run.sh hello 8bitFibonacci
```

The disk images tests read from are built first by `Tests/makedisks.sh`, using SplitDisk. A
test that reads one is therefore checked against a filesystem written by different code from
the same written specification, rather than against itself.

`Tests/run.sh` drives that comparison. Four more scripts run alongside it, and each exists
because a recorded file cannot answer its question:

- **`Tests/disk.sh`** checks the disk tool on its own: files of every awkward size onto an image and off again, and the things the format says cannot happen refused rather than half done.
- **`Tests/terminal.sh`** checks what a recorded file cannot see. Piped output is buffered and flushed at exit, so a prompt shown before its answer is asked for and one shown an hour late produce identical files; and key mode only touches a terminal when there is one. Both have gone wrong here, and both were found by a person whose terminal stopped working rather than by anything in this suite. So it runs the emulator under a pseudo-terminal and asks directly: that a prompt arrives before input is read, that a keystroke arrives without Return, that the terminal is handed back however the machine dies, and that suspending and resuming leave it as they found it.
- **`Tests/native.sh`** checks the assembler that runs on SplitBit against the one that runs on the host, byte for byte, on a boot image and four loadable programs, and then on CosmOS and on itself, and then on the CosmOS that CosmOS built.
- **`Tests/docs.sh`** checks the manuals against the code: that every instruction has a row and every row is an instruction, that the counts in the headings are right, that every directive is written down, that every service the system implements is described and every service described is implemented, that every routine the manuals promise exists, and that the worked examples still assemble to the bytes printed beside them.

A cycle count is deliberately **not** part of a recorded result. The last line of the emulator's output has the number taken out before anything is compared, keeping only whether the program stopped on its own or ran into its limit, which is behaviour. Two instructions added to CosmOS used to move that number in six unrelated files at once, so a real difference would have arrived in a crowd of meaningless ones. Anything that wants to measure cycles should say so in a test of its own.

To rebuild all three tools with the address and undefined behaviour sanitizers and run the suite under them:

```
make sanitize
```

This catches reads and writes past the end of an array, use after free, leaks, and undefined arithmetic. It also fills fresh allocations with a junk pattern, which turns a read of uninitialised memory from something that quietly works into something the tests notice. It runs everything `make test` runs, takes about twice as long, and puts the ordinary binaries back when it finishes.

## Documentation:

Three documents, divided by what they are about rather than by who reads them.

**[SplitBit Programming Manual](SplitBit%20Programming%20Manual.md)** describes **the machine**: the instruction set, the registers, the vector table, interrupts, devices, the memory controller, the console, storage, and faults. Everything here is true of any SplitBit, whatever is running on it.

**[SplitBit Assembler Manual](SplitBit%20Assembler%20Manual.md)** describes **the language and the file formats**: literal values, labels, segments, the directives, the loadable program header, and the assembler that runs on SplitBit itself.

[Programs/CosmOS/README.md](Programs/CosmOS/README.md) describes **the operating system**: its shell, its applications, what a program may ask it for, and the libraries it owns. A different system on the same machine would answer all of that differently, which is why it is documented with the system rather than with the CPU.

## License:

Apache License, Version 2.0. You may obtain a copy at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0).
