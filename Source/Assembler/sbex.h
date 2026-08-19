// sbex.h
// The SplitBit loadable program format, version one.
//
// A program that is not the one the machine booted from has to say where it wants to
// live, because nothing relocates it. This is a header saying that, in front of the
// bytes themselves. It is the same idea as the load address on the front of a C64 .PRG,
// with room for the machine to ask a few more questions later.
//
// Two things read this: whatever builds one on the host, and the loader running on
// SplitBit. As with the filesystem, nothing is shared between them but the specification.
//
// All multi byte numbers are most significant byte first.
//
//   0   4  "SBEX"
//   4   1  Version
//   5   1  How many vectors follow the data, zero in a version 1 file
//   6   2  Where the code goes in Program Memory
//   8   2  Where to start running, an address in Program Memory
//   10  2  How many bytes of code there are
//   12  2  Where the data goes in Data Memory
//   14  2  How many bytes of data there are
//   16     The code, then the data, then the vectors
//
// ---- Vectors, added in version two ----
//
// Four bytes each, the same shape a boot image uses: the address of the vector table slot,
// then the address to put in it. Both most significant byte first. Saying the slot outright
// rather than the vector number means the loader does no arithmetic and does not need to
// know where either vector table begins, and one entry can name a software or a hardware
// vector without saying which.
//
// A PROGRAM CARRYING VECTORS SAYS VERSION TWO, and one carrying none stays version one and
// loads anywhere. The version is not decided by the format's age but by whether the file
// needs something of its loader: an older loader meeting a version two file refuses it and
// says so, which is the right answer, because a program whose handlers were quietly dropped
// is not the program somebody asked for. It would run, and then fail later at a place with
// nothing to connect it back to loading.
//
// INSTALLING THEM IS THE LOADER'S JOB, AND SO IS TAKING THEM BACK. A vector points into the
// program that supplied it, so leaving one installed after that program is gone aims an
// interrupt at whatever occupies those addresses next. A loader restores what it found.
#define SBEX_VECTOR_ENTRY_BYTES 4
//
// Sixteen bytes, so the code begins at a round offset and finding it is one step rather
// than an arithmetic. Nothing here relocates anything: the addresses are where the
// program was built to live, and putting it anywhere else would leave every branch and
// every SETD inside it pointing at the wrong place.
//
// Written by Anachronaut

#ifndef SBEX_H
#define SBEX_H

#define SBEX_MAGIC "SBEX"
#define SBEX_MAGIC_BYTES 4
// What a program says when it asks nothing of its loader beyond code and data, and what
// it says when it also brings vectors that have to be installed.
#define SBEX_VERSION 1
#define SBEX_VERSION_VECTORS 2
#define SBEX_HEADER_BYTES 16

#define SBEX_VERSION_AT   4
#define SBEX_VECTORS_AT   5
#define SBEX_CODE_AT      6
#define SBEX_ENTRY_AT     8
#define SBEX_CODE_LEN_AT  10
#define SBEX_DATA_AT      12
#define SBEX_DATA_LEN_AT  14

#endif // SBEX_H
