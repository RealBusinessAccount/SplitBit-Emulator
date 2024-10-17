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

### Installation:
1) Clone the repository:
```
git clone https://github.com/RealBusinessAccount/SplitBit-Emulator.git
cd SplitBit-Emulator
```
2) Build the Emulator: You'll need gcc and make or similar.
```
make
```
3) Run the emulator:
```
./SplitBit Programs/hello.bin
```

### Usage:
```
./SplitBit [options] [binary file]
```
#### Options:
- -d, --debug: Enable debug mode to single step through cycles.
- -h, --help: Show help and usage information.

### Additional Info:
For more information on the custom ISA and programming for SplitBit, see the Programming Manual.

### License:
This project is licensed under the Apache License, Version 2.0. You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0).
