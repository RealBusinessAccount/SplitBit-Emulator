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
# The assembler writes a loadable program itself, because the source says where it goes.
"$ROOT/Assembler" "$ROOT/Programs/loadable/hello.asm" -o "$WORK/hello.sbx" >/dev/null
"$TOOL" put "$DISKS/load.img" "$WORK/hello.sbx" >/dev/null

# A disk for CosmOS. greet.sbx asks the system for everything it does rather than talking
# to the hardware itself, so loading and running it exercises the whole path: the loader,
# the vector table, the service handlers, and giving the machine back at the end.
#
# hello.sbx is the opposite case, and that is why it is here: it is the original
# hello.asm, written before any of this existed, and it still writes straight to port
# 0x00 rather than calling osPrintString. A program is allowed to reach past the system
# to the hardware, so something has to check that one still gives the machine back.
#
# notes.txt is there so that loading something that is not a program can be tried too.
"$TOOL" format "$DISKS/cosmos.img" 32 1 >/dev/null
"$ROOT/Assembler" -I "$ROOT/Programs/CosmOS/Source" \
    "$ROOT/Programs/CosmOS/Apps/greet.asm" -o "$WORK/greet.sbx" >/dev/null
"$TOOL" put "$DISKS/cosmos.img" "$WORK/greet.sbx" >/dev/null
# Assembled to a different working name so it cannot tread on load.img's hello.sbx above,
# then put under the name the shell asks for.
"$ROOT/Assembler" -I "$ROOT/Programs/CosmOS/Source" \
    "$ROOT/Programs/CosmOS/Apps/hello.asm" -o "$WORK/appHello.sbx" >/dev/null
"$TOOL" put "$DISKS/cosmos.img" "$WORK/appHello.sbx" hello.sbx >/dev/null
# Life.sbx is the one that had to be taught to stop. It runs to a still life and returns
# on its own, so the test needs no cycle limit: whether it ends is the thing being checked
# and a limit would hide the answer by supplying one.
"$ROOT/Assembler" -I "$ROOT/Programs/Libraries" -I "$ROOT/Programs/CosmOS/Source" \
    "$ROOT/Programs/CosmOS/Apps/Life.asm" -o "$WORK/Life.sbx" >/dev/null
"$TOOL" put "$DISKS/cosmos.img" "$WORK/Life.sbx" >/dev/null
# Snake.sbx is the one that is played rather than watched. It reads the console a key at a
# time without ever waiting for one, so a script of moves drives it a move to a frame, and
# what is recorded is a whole game: turning, eating, growing, and running into a wall.
"$ROOT/Assembler" -I "$ROOT/Programs/Libraries" -I "$ROOT/Programs/CosmOS/Source" \
    "$ROOT/Programs/CosmOS/Apps/Snake.asm" -o "$WORK/Snake.sbx" >/dev/null
"$TOOL" put "$DISKS/cosmos.img" "$WORK/Snake.sbx" >/dev/null
# Keys.sbx brings a vector of its own, which is what the version two format exists for. It
# is the only program here the system has to install anything for, so it is what says the
# whole path works: written into the file, installed at run, taken back out at exit.
"$ROOT/Assembler" -I "$ROOT/Programs/Libraries" -I "$ROOT/Programs/CosmOS/Source" \
    "$ROOT/Programs/CosmOS/Apps/Keys.asm" -o "$WORK/Keys.sbx" >/dev/null
"$TOOL" put "$DISKS/cosmos.img" "$WORK/Keys.sbx" >/dev/null
printf 'this is not a program' > notes.txt
"$TOOL" put "$DISKS/cosmos.img" notes.txt >/dev/null

# A disk of its own for the writing test, with one file already on it so that what it
# writes has to be placed somewhere that does not tread on what is there.
"$TOOL" format "$DISKS/write.img" 32 1 >/dev/null
printf 'already here' > here.txt
"$TOOL" put "$DISKS/write.img" here.txt >/dev/null
