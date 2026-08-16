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
//   5   1  Reserved
//   6   2  Where the code goes in Program Memory
//   8   2  Where to start running, an address in Program Memory
//   10  2  How many bytes of code there are
//   12  2  Where the data goes in Data Memory
//   14  2  How many bytes of data there are
//   16     The code, then the data
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
#define SBEX_VERSION 1
#define SBEX_HEADER_BYTES 16

#define SBEX_VERSION_AT   4
#define SBEX_CODE_AT      6
#define SBEX_ENTRY_AT     8
#define SBEX_CODE_LEN_AT  10
#define SBEX_DATA_AT      12
#define SBEX_DATA_LEN_AT  14

#endif // SBEX_H
