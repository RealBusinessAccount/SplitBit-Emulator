#!/usr/bin/env bash
# Checks the manuals against the code.
#
# Documentation goes stale quietly. An instruction added without a table row, or a count
# in a heading that nobody updated, is wrong in a way nothing notices until somebody
# trusts it. Everything here is a claim the manuals make that can be settled by looking
# at the source, so it is settled every time the tests run.
#
# Written by Anachronaut

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

python3 - <<'PY'
import re
import sys

problems = []


def read(path):
    return open(path).read()


pm = read("SplitBit Programming Manual.md")
am = read("SplitBit Assembler Manual.md")
asmc = read("Source/Assembler/assembly.c")
util = read("Source/Assembler/Assm-util.c")

# ---- Every instruction has a row, and every row is an instruction ----
#
# A mnemonic begins with a letter, which is what keeps the offset and size columns of the
# other tables in these manuals out of it.
documented = {(int(m.group(1), 16), m.group(2))
              for m in re.finditer(r'^\|\s*([0-9A-F]{2})\s*\|\s*([A-Z][A-Z0-9]*)\s*\|', pm, re.M)}
implemented = {(int(m.group(1), 16), m.group(2))
               for m in re.finditer(r'\{0x([0-9A-Fa-f]{2}),\s*"([A-Z0-9]+)"\}', asmc)}
for opcode, name in sorted(implemented - documented):
    problems.append("%s (0x%02X) is implemented and not in the manual" % (name, opcode))
for opcode, name in sorted(documented - implemented):
    problems.append("%s (0x%02X) is in the manual and not implemented" % (name, opcode))

# ---- The counts in the group headings ----
body = asmc[asmc.index("Instruction instruction_set[]"):asmc.index("int num_instructions")]
actual = {}
group = None
for line in body.split("\n"):
    heading = re.match(r'\s*// (.+?) Operations:', line)
    if heading:
        group = heading.group(1)
        actual.setdefault(group, 0)
    if re.search(r'\{0x[0-9A-Fa-f]{2},', line) and group:
        actual[group] += 1

for m in re.finditer(r'^### (.+?) Operations: (\d+) Instructions?$', pm, re.M):
    name, claimed = m.group(1), int(m.group(2))
    # The manual's headings are wordier than the source's comments, so match on the start.
    match = [v for k, v in actual.items() if name.startswith(k)]
    if not match:
        problems.append("the manual has a group called \"%s\" that the source does not" % name)
    elif match[0] != claimed:
        problems.append("the manual says %s has %d instructions, and it has %d"
                        % (name, claimed, match[0]))

# ---- How many instructions carry a Data Pointer selector ----
#
# The manual says this as a word rather than a figure, and it is the sort of number that
# goes stale quietly: adding an instruction that takes a selector leaves the sentence
# looking perfectly reasonable and wrong. dataPointerOperands is the list, so it is the
# one to believe.
words = {12: "Twelve", 13: "Thirteen", 14: "Fourteen", 15: "Fifteen", 16: "Sixteen",
         17: "Seventeen", 18: "Eighteen", 19: "Nineteen", 20: "Twenty"}
selectors = asmc[asmc.index("int dataPointerOperands"):asmc.index("uint8_t getOpcode")]
taking = len(re.findall(r'^\s*case 0x[0-9A-Fa-f]{2}:', selectors, re.M))
said = re.search(r'^([A-Z][a-z]+) instructions work through a Data Pointer\.', pm, re.M)
if not said:
    problems.append("the manual no longer says how many instructions take a Data Pointer")
elif said.group(1) != words.get(taking):
    problems.append("the manual says %s instructions work through a Data Pointer, and %d do"
                    % (said.group(1).lower(), taking))

# ---- Every device class in the header has a row in the Devices table ----
#
# The table says which ports a device answers on and what class it reports. Adding a
# device, or widening one from a single port to a block, leaves the table looking perfectly
# reasonable and describing a machine that no longer exists. The classes are the part that
# can be checked against the source without teaching this script how ports are laid out:
# every class the header defines except DEVICE_NONE is something a program can find on the
# bus, so every one of them has to be findable in the manual too.
ioh = read("Source/Emulator/io.h")
classes = {name: int(value, 16)
           for name, value in re.findall(r'^#define (DEVICE_[A-Z_]+)\s+(0x[0-9A-Fa-f]{2})$',
                                         ioh, re.M)
           if name not in ("DEVICE_NONE",)}
if "## Devices:" not in pm:
    problems.append("the Programming Manual has lost its Devices table")
else:
    table = pm.split("## Devices:")[1].split("\n## ")[0]
    listed = {int(m, 16) for m in re.findall(r'\|\s*(0x[0-9A-Fa-f]{2})\s*\|\s*$', table, re.M)}
    for name, value in sorted(classes.items(), key=lambda pair: pair[1]):
        if value not in listed:
            problems.append("%s (0x%02X) is a device class and has no row in the Devices"
                            " table" % (name, value))

# ---- Every console status bit is described ----
#
# The status port is read by writing a mask and testing it, so a program can only use a bit
# it has been told the number of. Adding one and forgetting to write it down leaves a bit
# that works and that nobody can discover. The section names them as "bit N", so that is
# what is looked for.
status = {name: int(value, 16)
          for name, value in re.findall(r'^#define (CONSOLE_STATUS_[A-Z]+)\s+(0x[0-9A-Fa-f]{2})$',
                                        ioh, re.M)}
if "## The Console:" not in pm:
    problems.append("the Programming Manual has lost its \"The Console\" section")
else:
    console = pm.split("## The Console:")[1].split("\n## ")[0]
    for name, value in sorted(status.items(), key=lambda pair: pair[1]):
        bit = value.bit_length() - 1
        if "bit %d" % bit not in console:
            problems.append("%s is bit %d of the console status port and The Console does"
                            " not mention it" % (name, bit))

# ---- Every directive the assembler knows is written down ----
for directive in sorted(set(re.findall(r'"(#[A-Za-z]+)"', util))):
    if directive not in am:
        problems.append("%s is a directive and is not in the Assembler Manual" % directive)

# ---- Every routine the manual promises exists ----
#
# The first column of the table in each of these sections names something the library has
# to define. A routine renamed in the source and not in the manual is caught here, which
# is what keeps the tables a description rather than a memory.
for heading, library in [("## Reading The Filesystem:", "Programs/CosmOS/Source/sbfs.asm"),
                         ("## The Console Library:", "Programs/CosmOS/Source/console.asm")]:
    if heading not in pm:
        problems.append("the Programming Manual has lost its \"%s\" section"
                        % heading.strip("# :"))
        continue
    section = pm.split(heading)[1].split("\n## ")[0]
    defined = set(re.findall(r'^([a-zA-Z][A-Za-z0-9]*):', read(library), re.M))
    for name in re.findall(r'^\| ([a-z][A-Za-z0-9]*) \|', section, re.M):
        if name not in defined:
            problems.append("the manual lists %s, which %s does not define" % (name, library))

# ---- The worked example still assembles to the bytes the manual prints ----
#
# The hello world program and the hex dump beside it are two claims about the same thing,
# and nothing but this keeps them agreeing.
import os
import subprocess
import tempfile

source = pm.split("### Example Program: Hello World")[1].split("```")[1]
claimed = pm.split("assembled and dumped as hex:")[1].split("```")[1].split()
with tempfile.TemporaryDirectory() as work:
    asm = os.path.join(work, "hello.asm")
    binary = os.path.join(work, "hello.bin")
    open(asm, "w").write(source)
    built = subprocess.run(["./Assembler", asm, "-o", binary],
                           capture_output=True)
    if built.returncode != 0:
        problems.append("the hello world program in the manual no longer assembles")
    else:
        actual = ["%02x" % b for b in open(binary, "rb").read()]
        if [c.lower() for c in claimed] != actual:
            problems.append("the hex dump in the manual is not what that program assembles to"
                            " now: it prints %d bytes and the assembler makes %d"
                            % (len(claimed), len(actual)))

# ---- The Assembler Manual's worked programs still assemble ----
for heading in ["## An Example SplitBit Assembly Program:",
                "## An Example Using More Than One Data Pointer:",
                "## An Example Using Interrupts:"]:
    if heading not in am:
        problems.append("the Assembler Manual has lost its \"%s\" section" % heading.strip("# :"))
        continue
    example = am.split(heading)[1].split("```")[1]
    with tempfile.TemporaryDirectory() as work:
        asm = os.path.join(work, "example.asm")
        open(asm, "w").write(example)
        built = subprocess.run(["./Assembler", "-I", "Programs/Libraries",
                                "-I", "Programs/CosmOS/Source", asm,
                                "-o", os.path.join(work, "example.bin")],
                               capture_output=True)
        if built.returncode != 0:
            problems.append("the example under \"%s\" no longer assembles"
                            % heading.strip("# :"))

if problems:
    print("The manuals and the code disagree:")
    for p in problems:
        print("  " + p)
    sys.exit(1)
print("The manuals agree with the code.")
PY
