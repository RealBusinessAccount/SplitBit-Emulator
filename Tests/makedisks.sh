#!/usr/bin/env bash
# Builds the disk images the tests read from.
#
# These are made with SplitDisk, which is the other implementation of the same format.
# That is the point of them: a SplitBit program reading one of these is being checked
# against something written by different code from a written specification, rather than
# against itself.
#
# Written by Anachronaut

set -eu
BUILD="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/SplitDisk"
DISKS="$BUILD/disks"
WORK="$BUILD/.diskwork"

[ -x "$TOOL" ] || { echo "SplitDisk is not built."; exit 1; }
mkdir -p "$DISKS" "$WORK"

# Two directory blocks, so that a file can be put beyond the first one and the walk from
# block to block gets exercised rather than assumed.
"$TOOL" format "$DISKS/sbfs.img" 64 2 >/dev/null

cd "$WORK"
printf 'hello from a file' > greeting.txt

# Eight files fill the first directory block exactly, so everything after this lands in
# the second one.
for i in 1 2 3 4 5 6 7 8; do printf 'filler %d' "$i" > "filler$i.txt"; done

# Longer than a block, so reading it has to cross from one to the next. The pattern
# repeats every twenty six bytes, which makes a misplaced block obvious to read.
awk 'BEGIN { for (i = 0; i < 700; i++) printf "%c", 65 + (i % 26) }' > across.txt

: > empty.txt
printf 'exactly twenty two!!!!' > longname.txt

"$TOOL" put "$DISKS/sbfs.img" greeting.txt >/dev/null
for i in 1 2 3 4 5 6 7 8; do "$TOOL" put "$DISKS/sbfs.img" "filler$i.txt" >/dev/null; done
"$TOOL" put "$DISKS/sbfs.img" across.txt >/dev/null
"$TOOL" put "$DISKS/sbfs.img" empty.txt >/dev/null
"$TOOL" put "$DISKS/sbfs.img" longname.txt aName22CharactersLong! >/dev/null

# A disk with a loadable program on it. The program is assembled here rather than kept as
# bytes, so that what gets loaded is always built from the source beside it.
"$TOOL" format "$DISKS/load.img" 64 2 >/dev/null
"$ROOT/Assembler" "$ROOT/Programs/loadable/hello.asm" -o "$WORK/hello.bin" >/dev/null
python3 "$ROOT/Source/DiskTool/wrap.py" "$WORK/hello.bin" "$WORK/hello.sbx" 0x2000 0x1000 0x2000 >/dev/null
"$TOOL" put "$DISKS/load.img" "$WORK/hello.sbx" >/dev/null

# A disk of its own for the writing test, with one file already on it so that what it
# writes has to be placed somewhere that does not tread on what is there.
"$TOOL" format "$DISKS/write.img" 32 1 >/dev/null
printf 'already here' > here.txt
"$TOOL" put "$DISKS/write.img" here.txt >/dev/null
