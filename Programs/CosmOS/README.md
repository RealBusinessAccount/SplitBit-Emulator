# CosmOS

## Overview:
CosmOS is a small, single-tasking disk operating environment for the SplitBit 8-bit
computer. It boots the machine, finds and mounts an SBFS filesystem, provides a command
line and memory monitor, loads applications from disk, and takes control back when they
finish.

CosmOS is written entirely in SplitBit assembly. It is closer in scale and purpose to a
resident monitor or an early disk operating system than to a modern multitasking OS: one
program owns the machine at a time, there is no privilege boundary, and applications are
assembled for fixed regions of memory. What it provides is a stable home from which those
programs can be found, run, and given services without each one having to boot the machine
for itself.

### Features:
- Interactive Shell: Read commands from the SplitBit console and continue until `exit` or
  the end of input.
- SBFS Filesystem: Mount, list, read, write, delete, and rename files on a SplitBit disk.
- Loadable Applications: Validate SBEX files, copy their Program and Data segments into
  the addresses for which they were assembled, and start them at their declared entry
  point.
- Resident Services: Applications can print strings and numbers, read lines, receive their
  command arguments, read and write files, and return to the shell through named software
  interrupts.
- Application Vectors: Install interrupt vectors carried by a loadable program and
  restore whatever they replaced when the program exits.
- Stack Reclamation: Save the system Stack before launching an application and take it
  back on exit, so an application need not unwind itself before returning.
- Memory Monitor: Inspect and modify Program Memory, Data Memory, and registered
  device-memory banks through the SplitBit memory controller, disassemble instructions,
  and begin execution at an address.
- Hardware Discovery: Mount the disk through the device registry rather than assuming
  that one is present at a particular controller bank.
- Native Applications: Includes demonstrations, mathematical programs, interactive
  programs, a game, and a line-oriented text editor.
- Reproducible Disk Image: The makefile assembles the system and every application, then
  constructs a fresh SBFS image containing the resulting executables.

## Building and Running:

CosmOS currently lives inside the SplitBit Emulator repository and uses its assembler,
emulator, and disk-image tool. From the repository root, build those tools first:

```sh
make
```

Then build CosmOS and all of its applications:

```sh
cd Programs
make cosmos
```

Build a fresh SBFS application disk as well:

```sh
make cosmos-disk
```

To boot CosmOS with that disk attached:

```sh
make run-cosmos
```

The generated files are kept under `Programs/build/`:

- `CosmOS/Source/cosmos.bin` is the bootable CosmOS image.
- `CosmOS/Apps/*.sbx` are loadable application images.
- `cosmos.img` is the SBFS disk containing those applications.

The disk is rebuilt from scratch when its applications change, so its contents describe
the current source tree rather than accumulating files left by older builds.

## Shell Commands:

CosmOS currently provides these built-in commands:

| Command | Description |
| -- | -- |
| `dir` | List the files on the mounted disk and their sizes. |
| `load <file>` | Read and validate an SBEX application, then place its code and data where its header requests. |
| `run [words]` | Start the loaded application and make the rest of the line available to it as an argument. |
| `delete <file>` | Remove a file from the filesystem and release its blocks. |
| `rename <file> <to>` | Give a file a different name without moving its contents. |
| `monitor` | Enter monitor mode, in which the prompt becomes `*` and the commands below are also available. |
| `help` | Show the built-in command summary. |
| `exit` | Leave monitor mode if in it, and otherwise halt the machine. |

Monitor mode adds the following. It is a mode rather than a separate program because a
loaded application occupies the one region a loaded application is given, so a monitor
which was itself an application could never examine another one. The mode persists: an
application started with `g` which returns through `osExit` arrives back at the monitor
prompt rather than at the shell.

| Command | Description |
| -- | -- |
| `x [address]` | Display 64 bytes as hexadecimal and as characters. |
| `d [address]` | Disassemble eight instructions. |
| `a <address>` | Assemble instructions into memory until a line containing only a dot. |
| `s <address> <byte>...` | Write bytes into the bank being examined, including Program Memory. |
| `b <program\|data\|bank>` | Select a memory space or a registered bank number. |
| `g <address>` | Begin execution at an address. |

`x` and `d` share a position, and each leaves it after what it displayed, so either may be
given without an address to continue from where the last one stopped.

For example:

```text
> dir
> load Snake.sbx
> run
```

Loading and running are separate operations for now. A loaded program may be run again
without being read from disk again, which is useful both as a monitor facility and as a
test that CosmOS correctly restores its Stack and vector table after every run.

CosmOS also boots without a disk. It reports that no filesystem was found, leaves the
shell and memory monitor available, and refuses commands that require a mounted disk
without stopping the machine.

## Included Applications:

The application disk is populated from every assembly file in `CosmOS/Apps/`. At present
it includes:

- `Edit`: A line-oriented text editor that can create, load, modify, and save files from
  inside CosmOS.
- `Snake`: A playable terminal game using nonblocking single-key input.
- `Life`: A 16 by 16 Conway's Game of Life simulation that returns when it settles or
  reaches its generation limit.
- `Keys`: An interrupt-driven console demonstration carrying its own hardware vector.
- `Say`: Demonstrates receiving the argument supplied to `run`.
- `Files`: Writes, reads, renames, and deletes a file using only the system's services,
  including no filesystem code of its own.
- `greet` and `hello`: Small examples of, respectively, using CosmOS services and talking
  directly to SplitBit hardware.
- `Fib-8`, `Fib-16`, and `Fib-32`: Fibonacci demonstrations at three integer widths.
- `Sieve-8` and `Sieve-16`: Prime sieves covering the 8-bit and 16-bit ranges.

These programs are ordinary SBEX files on SBFS. They are not built into the operating
system, and the host-side `SplitDisk` tool can add or remove other files from an image.

## The Application Model:

CosmOS divides the two SplitBit address spaces by convention:

| Memory | CosmOS | Loaded application |
| -- | -- | -- |
| Program Memory | `0x0000` through `0x1FFF` | `0x2000` and above |
| Data Memory | `0x0000` through `0x0FFF` | `0x1000` and above |

Applications state their actual Program and Data addresses with `#Base`. The SplitBit
assembler then writes an SBEX loadable image containing those addresses, the entry point,
the segment lengths, and any vectors the application needs. CosmOS does not relocate
code: the addresses in the file must be the addresses for which it was assembled.

This division is an ABI convention rather than protection. An application owns the
machine while it runs and may address hardware or CosmOS memory directly. The convention
keeps independently assembled software out of the system's way; it is not a security
boundary.

### System Services:

Applications include `Source/services.asm` to obtain stable names and vector numbers for
the services CosmOS provides. The currently installed services are:

| Service | Interface |
| -- | -- |
| `osPrintString` | DP0 names a zero-terminated string to print. |
| `osReadLine` | DP0 names a destination and B is its capacity; Q returns the line length. |
| `osArgument` | DP0 names a destination and B is its capacity; receives the text following `run`. |
| `osExit` | Abandon the application's Stack, restore the CosmOS environment, and return to the shell. |
| `osFileRead` | DP0 names a file and DP1 a destination; Q reports success and DP3 returns its length in bytes. |
| `osFileSave` | DP0 names a file, DP1 supplies its contents, and A with B give the length; Q reports success. |
| `osFileDelete` | DP0 names a file to remove; Q reports success. |
| `osFileRename` | DP0 names an existing file and DP1 its new name; Q reports success. |
| `osPrintNumber` | A with B give a number to print in decimal without leading zeroes. |
| `osBreak` | Stops the application, shows every register as it had them, waits for a key, and carries on. |
| `osFileInfo` | DP0 names a file; Q reports whether it is there and DP3 returns how many blocks it occupies. |
| `osFileBlock` | DP0 names a file, DP1 a destination, and A with B give which block; Q reports success and DP3 returns how many of the block's bytes belong to the file. |

The largest application CosmOS has is the assembler in `Programs/CosmOS/Assembler/`, which
is why the streaming services below exist: it reads source a block at a time, twice, and
keeps only its label table in between. It travels with CosmOS rather than with the emulator,
for the same reason the C assembler travels with the emulator - it is part of the system it
is written for.

`osFileInfo` and `osFileBlock` are how an application reads a file too big to hold. A whole
file arrives through `osFileRead`, which cannot help with anything above 64K, and CosmOS's
own source is above it. Neither call keeps anything open: each one names the file and says
which block it wants, so an application that stops halfway leaves nothing behind. Both
report why they failed rather than only that they did - 1 for no disk, 2 for no such file,
3 for a block past the end, and 4 for a disk that would not read - because running off the
end is how a reader learns it has finished.

The filesystem services exist so that an application need not contain a second copy of the
filesystem in order to keep a file. There is deliberately no service to mount a disk: the
system mounts one before its first prompt, and an application mounting it again was only
ever a consequence of owning a private copy of the library.

A minimal CosmOS application therefore looks like this:

```asm
#Include services.asm

#Program
  #Base 0x2000

start:
  SETD.0 Message
  SWI osPrintString
  SWI osExit

#Data
  #Base 0x1000

Message:
  "Hello from CosmOS."
```

An application may also include its own libraries or access hardware ports directly.
The services are an interface offered by the system, not the only way software is allowed
to use the computer.

## Source Layout:

- `Source/cosmos.asm`: Boot process, shell, loader, monitor, system services, and
  application lifecycle.
- `Source/console.asm`: Console input, strings, hexadecimal and decimal output, and line
  handling.
- `Source/text.asm`: String comparison, splitting, and hexadecimal text conversion used
  by the shell.
- `Source/sbfs.asm`: Target-side implementation of the SplitBit filesystem.
- `Source/services.asm`: The shared names and stable vector numbers used by CosmOS and
  separately assembled applications.
- `Apps/`: Loadable programs packaged onto the CosmOS disk image.

## Tests:

CosmOS is exercised as part of the SplitBit repository's normal test suite:

```sh
make test
```

The tests boot the system with and without a disk and drive the shell through recorded
console input. They cover directory traversal, every loader refusal, repeated application
runs, memory inspection, vector installation and restoration, command arguments,
filesystem deletion and renaming, interactive applications, and editing a file followed
by reading the saved result back in a second editor session.

Individual CosmOS tests can be run from the repository root, for example:

```sh
./Tests/run.sh cosmos cosmosRun cosmosEdit
```

Test disks are constructed with the host-side `SplitDisk` tool. CosmOS is therefore
reading filesystems written by an independent implementation of the same format rather
than merely checking its filesystem code against itself.

## Current Scope:

CosmOS is early software for an experimental computer. It runs one application at a
time, has no privilege levels or process isolation, does not relocate applications, and
provides a line assembler but not yet a native assembler for source files, nor a linker. Its present purpose is to make
SplitBit usable from inside the machine: inspect it, manage persistent files, load
programs, provide common services, and return reliably to a command prompt.

The intended long-term milestone is self-hosting: editing SplitBit assembly source under
CosmOS, assembling and linking it natively, and eventually rebuilding CosmOS and its own
development tools on the machine.

## Additional Information:

The SplitBit Programming Manual describes the CPU, devices, memory controller, SBFS,
SBEX format, interrupt model, and CosmOS service interface. The SplitBit Assembler Manual
documents the assembly language, loadable-program bases, and vector declarations.

## License:

CosmOS is part of the SplitBit Emulator project and is licensed under the Apache License,
Version 2.0. See the repository's top-level `LICENSE` file for the full license text.
