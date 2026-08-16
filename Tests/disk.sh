#!/usr/bin/env bash
# Checks SplitDisk against the SBFS format.
#
# The tool and the SplitBit side are two implementations of one written specification,
# and nothing but that document keeps them the same. This checks the host half on its
# own: that a file put onto a disk comes back off it byte for byte, that the sizes which
# exercise the block and tail arithmetic all survive, and that the things the format
# says cannot happen are refused rather than half done.
#
# Written by Anachronaut

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/SplitDisk"
WORK="$ROOT/Tests/build/disk"

PASS=0
FAIL=0
FAILED_NAMES=()

GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
[ -t 1 ] || { GREEN=""; RED=""; RESET=""; }

check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS + 1)); printf "  [%sok  %s] %s\n" "$GREEN" "$RESET" "$name"
    else
        FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
        printf "  [%sFAIL%s] %s\n" "$RED" "$RESET" "$name"
    fi
}

# The opposite: the command is supposed to fail, and passing would be the bug.
refuses() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
        printf "  [%sFAIL%s] %s (it was allowed)\n" "$RED" "$RESET" "$name"
    else
        PASS=$((PASS + 1)); printf "  [%sok  %s] %s\n" "$GREEN" "$RESET" "$name"
    fi
}

if [ ! -x "$TOOL" ]; then
    echo "SplitDisk is not built."
    exit 1
fi

rm -rf "$WORK"; mkdir -p "$WORK"
cd "$WORK" || exit 1

echo "Checking SplitDisk against the SBFS format."

check "format a disk"                     "$TOOL" format work.img 64 2
refuses "refuse a disk with no room"      "$TOOL" format tiny.img 2 4
refuses "refuse an unformatted disk"      "$TOOL" list /dev/null

# The sizes that exercise every corner of blocks-plus-tail: nothing at all, less than a
# block, exactly a block, a part block, and an exact multiple.
: > empty.bin
printf 'x' > one.bin
head -c 256 /dev/urandom > exact.bin
head -c 700 /dev/urandom > part.bin
head -c 768 /dev/urandom > whole.bin

for f in empty.bin one.bin exact.bin part.bin whole.bin; do
    check "put $f" "$TOOL" put work.img "$f"
done

roundTrip() {
    "$TOOL" get work.img "$1" "got_$1" >/dev/null 2>&1 || return 1
    cmp -s "$1" "got_$1"
}
for f in empty.bin one.bin exact.bin part.bin whole.bin; do
    check "$f comes back byte for byte" roundTrip "$f"
done

refuses "refuse a name of 29 characters"  "$TOOL" put work.img part.bin 16bitSegmentedSieveModern.asm
refuses "refuse a duplicate name"         "$TOOL" put work.img one.bin
refuses "refuse a file that is not there" "$TOOL" get work.img nosuch.bin out.bin
check   "delete"                          "$TOOL" delete work.img one.bin
refuses "the deleted file is gone"        "$TOOL" get work.img one.bin out.bin
check   "the name can be used again"      "$TOOL" put work.img one.bin

# Contiguous files mean a disk can have room without having room in one piece. That is a
# consequence of the format rather than a bug, so it is checked rather than worked around.
"$TOOL" format frag.img 16 1 >/dev/null 2>&1
head -c 1024 /dev/urandom > a.bin; cp a.bin b.bin; cp a.bin c.bin
"$TOOL" put frag.img a.bin >/dev/null 2>&1
"$TOOL" put frag.img b.bin >/dev/null 2>&1
"$TOOL" put frag.img c.bin >/dev/null 2>&1
"$TOOL" delete frag.img a.bin >/dev/null 2>&1
"$TOOL" delete frag.img c.bin >/dev/null 2>&1
head -c 2048 /dev/urandom > big.bin
refuses "refuse a file with no run long enough" "$TOOL" put frag.img big.bin
head -c 512 /dev/urandom > fits.bin
check   "but one that fits the gap goes on"     "$TOOL" put frag.img fits.bin

echo
if [ "$FAIL" -eq 0 ]; then
    echo "All $PASS disk tool checks passed."
    exit 0
fi
echo "$PASS passed, $FAIL failed: ${FAILED_NAMES[*]}"
exit 1
