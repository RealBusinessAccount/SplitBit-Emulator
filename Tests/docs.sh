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

# ---- Every directive the assembler knows is written down ----
for directive in sorted(set(re.findall(r'"(#[A-Za-z]+)"', util))):
    if directive not in am:
        problems.append("%s is a directive and is not in the Assembler Manual" % directive)

# ---- Every routine the manual promises exists ----
for library, names in [("Programs/Libraries/sbfs.asm", re.findall(r'\| (sbfs[A-Za-z]+) \|', pm))]:
    defined = set(re.findall(r'^([a-zA-Z][A-Za-z0-9]*):', read(library), re.M))
    for name in names:
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
        built = subprocess.run(["./Assembler", "-I", "Programs/Libraries", asm,
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
