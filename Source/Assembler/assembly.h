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
//
// The feature flags are how a binary says it needs something the base machine does
// not provide, so that an emulator which cannot provide it refuses to run the binary
// rather than quietly doing the wrong thing. No features are defined yet; the field
// is here so that adding one later does not need another format version.

#define SPLITBIT_MAGIC "SPBT"
#define SPLITBIT_MAGIC_LENGTH 4
#define SPLITBIT_FORMAT_VERSION 1
#define SPLITBIT_FLAGS_LENGTH 4
#define SEGMENT_MARKER_LENGTH 3
#define SEGMENT_LENGTH_BYTES 2

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
