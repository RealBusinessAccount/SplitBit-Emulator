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

# ---- The vector ranges the manuals quote are the ones the assembler uses ----
#
# Both manuals print the boundary between numbers a program may pin and numbers the
# assembler hands out. Those are two constants in one header, and moving them without
# touching the manuals would leave every programmer reading a range that no longer exists
# and being refused a number the manual said was theirs.
header = read("Source/Assembler/assembly.h")
ranges = {name: int(value)
          for name, value in re.findall(r'^#define (VECTOR_FIRST_[A-Z]+)\s+(\d+)$',
                                        header, re.M)}
if set(ranges) != {"VECTOR_FIRST_PINNED", "VECTOR_FIRST_AUTO"}:
    problems.append("the vector range constants are not the two this check knows about: %s"
                    % ", ".join(sorted(ranges)) if ranges else "none found")
else:
    pinnedFrom = ranges["VECTOR_FIRST_PINNED"]
    autoFrom = ranges["VECTOR_FIRST_AUTO"]
    said = "%d to %d" % (pinnedFrom, autoFrom - 1)
    for manual, text in [("Programming Manual", pm), ("Assembler Manual", am)]:
        if said not in text:
            problems.append("the %s does not say the pinned vectors are %s"
                            % (manual, said))
    if "%d and up" % autoFrom not in pm:
        problems.append("the Programming Manual does not say the automatic vectors start"
                        " at %d" % autoFrom)
    if "from vector %d upwards" % autoFrom not in am:
        problems.append("the Assembler Manual does not say the automatic vectors start"
                        " at %d" % autoFrom)

# ---- The loadable header table matches the offsets the assembler writes ----
#
# The Programming Manual prints the header field by field, which is the description two
# implementations work from. sbex.h is where the offsets actually are, so a field moved
# there and not here would leave the manual describing a format nobody writes.
sbex = read("Source/Assembler/sbex.h")
offsets = {name: int(value)
           for name, value in re.findall(r'^#define (SBEX_[A-Z_]+_AT)\s+(\d+)$', sbex, re.M)}
if "## Loading A Program From A Disk:" not in pm:
    problems.append("the Programming Manual has lost its loadable program section")
else:
    loading = pm.split("## Loading A Program From A Disk:")[1].split("\n## ")[0]
    listed = [int(m) for m in re.findall(r'^\| (\d+) \| \d* \|', loading, re.M)]
    for name, offset in sorted(offsets.items(), key=lambda pair: pair[1]):
        if offset not in listed:
            problems.append("%s is at offset %d and the header table has no row for it"
                            % (name, offset))
    # Spelled as a word, the way these manuals write small numbers in prose.
    asWord = {1: "one", 2: "two", 3: "three", 4: "four", 5: "five"}
    for version in ("SBEX_VERSION", "SBEX_VERSION_VECTORS"):
        number = re.search(r'^#define %s\s+(\d+)$' % version, sbex, re.M)
        if not number:
            problems.append("%s is gone from sbex.h" % version)
            continue
        said = asWord.get(int(number.group(1)))
        if said is None or said not in loading.lower():
            problems.append("the loadable program section does not mention version %s (%s)"
                            % (number.group(1), said))

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

# ---- Every service the system offers has a row ----
#
# services.asm is the one place the numbers are written, and both the system and every
# program include it. A service added there and not here is one nothing can find out about
# except by reading the source of the operating system.
# DECLARING A SERVICE AND IMPLEMENTING ONE ARE DIFFERENT THINGS, and the manual should
# describe the second. services.asm names them and fixes their numbers, which is what lets a
# number be pinned before anything answers to it; cosmos.asm is where a name gets a handler.
# A row for a service nothing implements would be describing a call that faults, and a
# missing row for one that works is a service nobody can find out about.
services = read("Programs/CosmOS/Source/services.asm")
named = set(re.findall(r'^\s{2}(os[A-Za-z]+)\s+0d\d+', services, re.M))
system = read("Programs/CosmOS/Source/cosmos.asm")
vectors = system.split("#Vectors")[-1] if "#Vectors" in system else ""
implemented = {name for name in re.findall(r'^\s{2}(os[A-Za-z]+)\s+[a-zA-Z]', vectors, re.M)
               if name in named}
if not named:
    problems.append("no services could be found in services.asm")
elif "## What A Program May Ask The System For:" not in pm:
    problems.append("the Programming Manual has lost its services section")
else:
    section = pm.split("## What A Program May Ask The System For:")[1].split("\n## ")[0]
    documented = set(re.findall(r'^\| (os[A-Za-z]+) \|', section, re.M))
    for name in sorted(implemented - documented):
        problems.append("%s is a service the system implements and has no row in the"
                        " services table" % name)
    for name in sorted(documented - implemented):
        problems.append("the services table describes %s, which nothing implements: calling"
                        " it would dispatch through an empty vector and fault" % name)

# ---- Every program the manual describes is really there ----
#
# The table names what the shell can load. A program renamed or removed leaves a row
# describing something nobody can run, which is the same kind of quiet wrongness as a
# routine that no longer exists. The other direction is deliberately not checked: the ported
# programs are covered in the prose rather than given a row each.
import os
if "## Programs That Come With The System:" not in pm:
    problems.append("the Programming Manual has lost its list of programs")
else:
    listed = pm.split("## Programs That Come With The System:")[1].split("\n### ")[0]
    # After the separator, so the table's own heading row is not mistaken for a program.
    listed = listed.split("| --- |")[-1]
    for name in re.findall(r'^\| ([A-Z][A-Za-z0-9-]*) \|', listed, re.M):
        if not os.path.exists("Programs/CosmOS/Apps/%s.asm" % name):
            problems.append("the manual describes a program called %s, and there is no"
                            " Programs/CosmOS/Apps/%s.asm" % (name, name))

# ---- The monitor's instruction table is the assembler's ----
#
# The monitor disassembles, so it needs the same 64 instructions with the same names and the
# same lengths. A disassembler that disagreed about a length would not print one line wrong,
# it would lose its place and print everything after it wrong, which is the worst way for a
# tool like that to fail: confidently. So the table is generated from assembly.c by
# Tests/instructiontable.py, and what is in the monitor is checked against it here.
import subprocess
generated = subprocess.run([sys.executable, "Tests/instructiontable.py"],
                           capture_output=True, text=True)
if generated.returncode != 0:
    problems.append("the instruction table generator would not run")
else:
    wanted = [line.rstrip() for line in generated.stdout.splitlines() if line.strip()]
    # TWO copies now, and both are checked. The monitor has one and the assembler that
    # runs on the machine has another, because they are separate programs and there is no
    # linker to let them share: the monitor's lives in the system's data at an address
    # that moves every rebuild. Duplication is the cost of having no libraries, and a
    # check on every copy is what keeps the cost to bytes rather than to correctness.
    copies = [("the system", "Programs/CosmOS/Source/cosmos.asm", "\nInstructions:\n"),
              ("the native assembler", "Programs/CosmOS/Assembler/table.asm",
               "\nAsmInstructions:\n")]
    for who, path, marker in copies:
        text = read(path)
        if marker not in text:
            problems.append("%s has lost its instruction table" % who)
            continue
        block = text.split(marker)[1]
        have = []
        for line in block.splitlines():
            if not line.strip() or not line.startswith("  0x"):
                break
            have.append(line.rstrip())
        if have != wanted:
            problems.append("%s's instruction table is not what the assembler's"
                            " instruction set generates: %d entries against %d, first"
                            " difference at %s"
                            % (who, len(have), len(wanted),
                               next((a or b for a, b in zip(have + [None] * len(wanted),
                                                            wanted + [None] * len(have))
                                     if a != b), "the end")))

# ---- And the lengths that table implies are the ones the manual prints ----
#
# The generator works out how long each instruction is from rules written in it; the manual
# says so in a column somebody typed. They are independent accounts of the same fact, which
# is exactly the pair worth checking against each other.
sys.path.insert(0, "Tests")
import instructiontable
lengthOf = {0: 1, 1: 3, 2: 2, 3: 2, 4: 3, 5: 4, 6: 3}
printed = {}
for m in re.finditer(r'^\|\s*[0-9A-F]{2}\s*\|\s*([A-Z][A-Z0-9]*)\s*\|\s*(\d+)\s*\|', pm, re.M):
    printed[m.group(1)] = int(m.group(2))
for opcode, name in instructiontable.table():
    implied = lengthOf[instructiontable.shapeOf(opcode)]
    if name in printed and printed[name] != implied:
        problems.append("the manual says %s is %d bytes and the disassembler will read it"
                        " as %d" % (name, printed[name], implied))

# ---- Every directive the assembler knows is written down ----
for directive in sorted(set(re.findall(r'"(#[A-Za-z]+)"', util))):
    if directive not in am:
        problems.append("%s is a directive and is not in the Assembler Manual" % directive)

# ---- Every routine the manual promises exists ----
#
# The first column of the table in each of these sections names something the library has
# to define. A routine renamed in the source and not in the manual is caught here, which
# is what keeps the tables a description rather than a memory.
for heading, library in [("## Reading And Writing The Filesystem:", "Programs/CosmOS/Source/sbfs.asm"),
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

# BOTH ANCHORS ARE CHECKED BEFORE THEY ARE USED. Every other heading this script splits on
# says what it could not find; these two were the exception, and a rename here produced an
# IndexError and a traceback instead of a sentence. That is a worse answer than a stale
# manual, because whoever reads it learns nothing about which heading moved.
exampleAnchor = "### Example Program: Hello World"
dumpAnchor = "assembled and dumped as hex:"
if exampleAnchor not in pm:
    problems.append("the Programming Manual has lost its \"Example Program: Hello World\""
                    " heading, so the worked example cannot be found")
elif dumpAnchor not in pm:
    problems.append("the Programming Manual no longer says \"%s\" before the hex dump, so"
                    " there is nothing to compare the worked example against" % dumpAnchor)
else:
    source = pm.split(exampleAnchor)[1].split("```")[1]
    claimed = pm.split(dumpAnchor)[1].split("```")[1].split()
    with tempfile.TemporaryDirectory() as work:
        asm = os.path.join(work, "hello.asm")
        binary = os.path.join(work, "hello.bin")
        open(asm, "w").write(source)
        built = subprocess.run(["./Assembler", asm, "-o", binary], capture_output=True)
        if built.returncode != 0:
            problems.append("the hello world program in the manual no longer assembles")
        else:
            actual = ["%02x" % b for b in open(binary, "rb").read()]
            if [c.lower() for c in claimed] != actual:
                problems.append("the hex dump in the manual is not what that program"
                                " assembles to now: it prints %d bytes and the assembler"
                                " makes %d" % (len(claimed), len(actual)))

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
