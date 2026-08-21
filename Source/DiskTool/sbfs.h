// sbfs.h
// The SplitBit Filesystem, version one.
//
// This is the host side's copy of the format. The other implementation is SplitBit
// assembly running on the machine itself, so nothing can be shared between them except
// the specification: the two have to be kept honest by a document rather than by a
// header. Everything here follows that document exactly, and anything that changes here
// has to change there in the same breath.
//
// All multi byte numbers are most significant byte first, the same as every other number
// SplitBit stores: addresses, the SPBT boot image header, and the vector table.
//
// Written by Anachronaut

#ifndef SBFS_H
#define SBFS_H

#include <stdint.h>

#define SBFS_MAGIC "SBFS"
#define SBFS_MAGIC_BYTES 4
#define SBFS_VERSION 1

#define SBFS_BLOCK_BYTES 256

// ---- Block 0, the superblock ----
//
//   0   4  "SBFS"
//   4   1  Version
//   5   1  Reserved
//   6   2  Blocks on the disk
//   8   2  First directory block
//   10  2  Blocks the directory occupies
//   12  2  Free blocks, a cache rather than the authority
//   14     Reserved to the end of the block

#define SBFS_SUPER_VERSION    4
#define SBFS_SUPER_DISK       6
#define SBFS_SUPER_DIRSTART   8
#define SBFS_SUPER_DIRBLOCKS  10
#define SBFS_SUPER_FREE       12

// ---- Directory entries ----
//
//   0   1  Flags
//   1   2  First block of the file's data
//   3   2  Whole blocks the file occupies
//   5   1  Bytes in the trailing part block, or zero if there is not one
//   6  22  Name, padded with zeroes
//   28  4  Reserved
//
// Thirty two divides two hundred and fifty six, so an entry never straddles a block and
// reading one never means handling a split.

#define SBFS_ENTRY_BYTES 32
#define SBFS_ENTRIES_PER_BLOCK (SBFS_BLOCK_BYTES / SBFS_ENTRY_BYTES)

#define SBFS_ENTRY_FLAGS  0
#define SBFS_ENTRY_START  1
#define SBFS_ENTRY_BLOCKS 3
#define SBFS_ENTRY_TAIL   5
#define SBFS_ENTRY_NAME   6
#define SBFS_NAME_BYTES   22

#define SBFS_FLAG_IN_USE 0x01

// The directory begins at block 1 and is this many blocks unless told otherwise, which
// is sixty four files. The superblock carries the real number, so this is only what a
// freshly formatted disk gets.
#define SBFS_FIRST_DIRECTORY_BLOCK 1
#define SBFS_DEFAULT_DIRECTORY_BLOCKS 8

// A file of n bytes occupies n / 256 whole blocks and, if anything is left over, one more
// for the tail. Zero means zero in both, so an empty file occupies nothing at all.
#define SBFS_WHOLE_BLOCKS(bytes) ((bytes) / SBFS_BLOCK_BYTES)
#define SBFS_TAIL_BYTES(bytes)   ((bytes) % SBFS_BLOCK_BYTES)
#define SBFS_BLOCKS_USED(blocks, tail) ((blocks) + ((tail) ? 1 : 0))

#endif // SBFS_H
