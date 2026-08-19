#!/usr/bin/env python3
"""The instruction table, as the assembler has it.

The monitor needs the same 64 instructions the assembler does, with the same names and the
same lengths, and a disassembler that disagreed with the assembler about how long an
instruction is would not merely print one thing wrong - it would lose its place and print
everything after it wrong too. So the table is generated from assembly.c rather than typed
out again, and Tests/docs.sh checks the generated form against what is in the monitor.

Shapes are what follows the opcode:
  0 nothing          1 an address       2 one byte         3 a Data Pointer selector
  4 selector, byte   5 selector, address                   6 two selectors
"""
import re
import sys

ADDRESS = {0x10, 0x11, 0x12, 0x13, 0x14, 0x17, 0x1A, 0x1B, 0x1C, 0x1D}
ONE_BYTE = {0x18, 0x26, 0x27}
TWO_SELECTORS = {0x4A, 0x4B}
SELECTOR = {0x15, 0x33, 0x36, 0x40, 0x41, 0x42, 0x43, 0x44,
            0x45, 0x46, 0x47, 0x48, 0x49, 0x4C, 0x4D}


def shapeOf(opcode):
    if opcode in TWO_SELECTORS:
        return 6
    if opcode == 0x47:                      # SETD, a selector and then an address
        return 5
    if opcode in (0x48, 0x49):              # DPUP and DPDN, a selector and then a byte
        return 4
    if opcode in SELECTOR:
        return 3
    if opcode in ADDRESS:
        return 1
    if opcode in ONE_BYTE or (opcode & 0xF0) in (0xD0, 0xE0):
        return 2
    return 0


def table(path="Source/Assembler/assembly.c"):
    source = open(path).read()
    found = re.findall(r'\{0x([0-9A-Fa-f]{2}),\s*"([A-Z0-9]+)"\}', source)
    return [(int(code, 16), name) for code, name in found]


def asAssembly(entries):
    lines = []
    for opcode, name in entries:
        padded = (name + "    ")[:4]
        lines.append('  0x%02X 0d%d "%s"' % (opcode, shapeOf(opcode), padded))
    return lines


if __name__ == "__main__":
    entries = table()
    if len(sys.argv) > 1 and sys.argv[1] == "--count":
        print(len(entries))
    else:
        for line in asAssembly(entries):
            print(line)
