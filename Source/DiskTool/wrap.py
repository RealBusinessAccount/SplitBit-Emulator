#!/usr/bin/env python3
"""Wraps an assembled SplitBit binary into a loadable program.

The assembler emits a boot image: a Program Segment that loads at zero and a Data Segment
that does the same. A program meant to be loaded somewhere else has to say where it goes,
which is what the SBEX header in front of it is for.

A program says where it lives by reserving the front of each segment, so the addresses
given here have to match the reserves in its source. Nothing checks that for you, and
nothing relocates anything if you get it wrong.
"""
import struct
import sys


def segments(raw):
    at = 4 + 1 + 4                      # magic, version, feature flags
    assert raw[:4] == b"SPBT", "not a SplitBit binary"
    assert raw[at:at + 3] == b"PRG"
    plen = struct.unpack(">H", raw[at + 3:at + 5])[0]
    program = raw[at + 5:at + 5 + plen]
    at = at + 5 + plen
    assert raw[at:at + 3] == b"DAT"
    dlen = struct.unpack(">H", raw[at + 3:at + 5])[0]
    return program, raw[at + 5:at + 5 + dlen]


def main():
    if len(sys.argv) != 6:
        sys.exit("usage: wrap.py <binary> <output> <code address> <data address> <entry>")
    binary, output = sys.argv[1], sys.argv[2]
    codeAt, dataAt, entry = (int(a, 0) for a in sys.argv[3:6])

    program, data = segments(open(binary, "rb").read())

    # Everything below the address a segment is placed at is the padding the reserve put
    # there, and is not part of the program.
    code = program[codeAt:]
    values = data[dataAt:]

    header = bytearray(16)
    header[0:4] = b"SBEX"
    header[4] = 1
    struct.pack_into(">H", header, 6, codeAt)
    struct.pack_into(">H", header, 8, entry)
    struct.pack_into(">H", header, 10, len(code))
    struct.pack_into(">H", header, 12, dataAt)
    struct.pack_into(">H", header, 14, len(values))

    with open(output, "wb") as out:
        out.write(header)
        out.write(code)
        out.write(values)
    print("%s: %d bytes of code at 0x%04X, %d of data at 0x%04X, entry 0x%04X"
          % (output, len(code), codeAt, len(values), dataAt, entry))


main()
