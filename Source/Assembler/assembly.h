// assembly.h
// These are functions useful for translating assembly mnemonics to hex and vice-versa for the SplitBit CPU.
// Written by Anachronaut
// 10/18/2024

#include <stdint.h>

#ifndef ASSEMBLY_H
#define ASSEMBLY_H

// ---- The SplitBit binary format ----
//
// A binary starts with a file header, then the Program Segment, then the Data
// Segment. All multi byte numbers are stored most significant byte first.
//
//   Offset  Size  Field
//   0       4     "SPBT", so a file that is not a SplitBit binary is spotted at once
//   4       1     Format version
//   5       4     Required feature flags
//   9       3     "PRG"
//   12      2     Program Segment length
//   14      N     Program Segment
//   ..      3     "DAT"
//   ..      2     Data Segment length
//   ..      M     Data Segment
//   ..      3     "VEC", optional
//   ..      2     Vector Segment length, in bytes
//   ..      K     Vector Segment, four bytes per entry
//
// The Vector Segment is optional and comes last, so a binary written before it existed
// simply ends after its Data Segment and still loads. Each entry is two bytes saying
// where in Program Memory the vector sits, then two bytes saying where its handler is,
// most significant byte first. It is a list rather than an image of the table, so a
// program with three handlers costs twelve bytes instead of a padded kilobyte.
//
// The feature flags are how a binary says it needs something the base machine does
// not provide, so that an emulator which cannot provide it refuses to run the binary
// rather than quietly doing the wrong thing. No features are defined yet; the field
// is here so that adding one later does not need another format version.

// ---- The vector table ----
//
// The top kilobyte of Program Memory is reserved for vectors. Both tools have to
// agree on where it begins: the CPU starts execution through it, and the assembler
// has to refuse program text that would run into it.
//
// Entries are two bytes each, most significant byte first, the same order the branch
// instructions and this file format already use.
//
//   0xFC00  Software vectors 0 to 255
//   0xFE00  Hardware vectors 0 to 255, one for each I/O port
//
// Software vectors 0 and 1 are start addresses rather than handlers. Vector 0 is
// where the machine begins at power on and vector 1 is a warm restart, so a zero in
// either of them is not "nothing installed" but the address 0x0000, which is where a
// program carrying no vector table of its own begins. A zero in any other entry does
// mean no handler is installed, and dispatching through one is a fault.

#define SOFTWARE_VECTOR_BASE 0xFC00
#define HARDWARE_VECTOR_BASE 0xFE00
#define VECTOR_ENTRY_BYTES   2
#define VECTOR_BOOT          0
#define VECTOR_SOFT_RESET    1
#define VECTOR_INVALID_OPCODE 2
// A device refused a write, because it landed inside a raised fence.
#define VECTOR_GUARD_VIOLATION 3
// A bank was named that has nothing registered in it, or an access ran past its end.
#define VECTOR_BANK_FAULT     4
// Vectors 5 to 15 are held back for faults that do not exist yet, so that each cause
// can have an entry of its own rather than sharing one and needing a cause register to
// tell them apart. Everything from 16 up belongs to programs, in two halves.
//
// PINNED, 16 to 63. Numbers in here are never handed out by the assembler; a program that
// wants one writes it down. This is where anything TWO SEPARATELY ASSEMBLED PROGRAMS have
// to agree about lives - the system's services, and any library that stays resident and is
// called through the vector table.
//
// AUTOMATIC, 64 up. Numbered by the assembler in the order they are written. These belong
// to one program and nothing outside it can name them, so what number they get does not
// matter as long as it is not somebody else's.
//
// THE SPLIT IS THE POINT. With one range for both, what number a program's own traps got
// depended on what it had included: adding a line that included the system's service names
// silently pushed every trap after it along by three. Worse, a program that did NOT include
// them was given 16, which is osPrintString, so installing its own handler would have
// replaced a system service by accident. Numbers that must agree are now written out loud,
// and numbers that need not agree are drawn from somewhere nobody else is looking.
#define VECTOR_FIRST_PINNED  16
#define VECTOR_FIRST_AUTO    64

// The first address the vector table occupies, and so the first address that program
// text may not use.
#define PROGRAM_TEXT_LIMIT SOFTWARE_VECTOR_BASE

#define SPLITBIT_MAGIC "SPBT"
#define SPLITBIT_MAGIC_LENGTH 4
#define SPLITBIT_FORMAT_VERSION 1
#define SPLITBIT_FLAGS_LENGTH 4
#define SEGMENT_MARKER_LENGTH 3
#define SEGMENT_LENGTH_BYTES 2
// Where a vector sits, and where its handler is.
#define VECTOR_ENTRY_FILE_BYTES 4

// Everything the format costs a file, on top of the two segments themselves.
#define SPLITBIT_HEADER_BYTES (SPLITBIT_MAGIC_LENGTH + 1 + SPLITBIT_FLAGS_LENGTH \
                               + 2 * (SEGMENT_MARKER_LENGTH + SEGMENT_LENGTH_BYTES))

// Features this build of the emulator can provide. A binary asking for anything
// outside this set is refused.
#define SPLITBIT_FEATURES_SUPPORTED 0x00000000u

// Features the assembler currently needs to ask for. Nothing, so far.
#define SPLITBIT_FEATURES_REQUIRED 0x00000000u

const char* getMnemonic(uint8_t opcode);

uint8_t getOpcode(char* mnemonic);

// How many Data Pointer selector bytes follow the given opcode. Never more than two.
#define MAX_DATA_POINTER_OPERANDS 2

int dataPointerOperands(uint8_t opcode);

#endif // CPU_H
