#!/usr/bin/env bash
# Checks the assembler that runs on SplitBit against the one that runs on the host.
#
# THE ONLY HONEST TEST OF AN ASSEMBLER IS THE BYTES IT PRODUCES. "It ran" and "the sizes
# look right" both pass for a binary with a label one byte out, which is a program that
# jumps into the middle of an instruction. So this assembles the same source both ways and
# compares the two files byte for byte, the same discipline SplitDisk and sbfs.asm work
# under: two implementations of one written specification, each one checking the other.
#
# Then it runs what the machine built, because a file that matches and does not work would
# mean both assemblers were wrong together.
#
# It checks a boot image and three loadable programs. The loadable ones are the harder case
# and the interesting one: they include another file, they are based somewhere other than
# zero, and every service they call is a name declared in that included file.
#
# Written by Anachronaut

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/Tests/build/native"
ASM="$ROOT/Assembler"
TOOL="$ROOT/SplitDisk"
EMU="$ROOT/SplitBit"

PASS=0
FAIL=0
FAILED_NAMES=()

check() {
    local name="$1"
    shift
    if "$@"; then
        printf '  [ok  ] %-22s %s\n' "$name" "${REPORT:-}"
        PASS=$((PASS + 1))
    else
        printf '  [FAIL] %-22s %s\n' "$name" "${REPORT:-}"
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$name")
    fi
    REPORT=""
}

for tool in "$ASM" "$TOOL" "$EMU"; do
    [ -x "$tool" ] || { echo "$(basename "$tool") is not built."; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK"

# The system it runs under, and the assembler itself, both built by the host assembler.
# Bootstrapping has to start somewhere, and this is the last place it does.
"$ASM" -I "$ROOT/Programs/Libraries" -I "$ROOT/Programs/CosmOS/Source" \
    -o "$WORK/cosmos.bin" "$ROOT/Programs/CosmOS/Source/cosmos.asm" >/dev/null || exit 1
"$ASM" -I "$ROOT/Programs/CosmOS/Source" -I "$ROOT/Programs/CosmOS/Assembler" \
    -o "$WORK/Asm.sbx" "$ROOT/Programs/CosmOS/Assembler/Asm.asm" >/dev/null || exit 1

"$TOOL" format "$WORK/native.img" 2048 4 >/dev/null
"$TOOL" put "$WORK/native.img" "$ROOT/Programs/hello.asm" hello.asm >/dev/null
"$TOOL" put "$WORK/native.img" "$WORK/Asm.sbx" Asm.sbx >/dev/null

# The applications, and the file of service names they all include. These are the reason
# the second milestone exists: an assembler that cannot follow an #Include cannot build
# anything that asks the system for anything.
APPS="Say greet Files"
"$TOOL" put "$WORK/native.img" "$ROOT/Programs/CosmOS/Source/services.asm" services.asm >/dev/null
for app in $APPS; do
    "$TOOL" put "$WORK/native.img" "$ROOT/Programs/CosmOS/Apps/$app.asm" "$app.asm" >/dev/null
done

{
    echo "load Asm.sbx"
    echo "run hello.asm"
    for app in $APPS; do echo "run $app.asm"; done
    echo "exit"
} | "$EMU" --fast --cycles 600000000 -D "$WORK/native.img" "$WORK/cosmos.bin" \
    > "$WORK/session.txt" 2>&1

# ---- It got as far as writing something ----
check "it wrote a file" grep -q "wrote hello.bin" "$WORK/session.txt"

# ---- And the file is the one the host assembler makes ----
"$ASM" -o "$WORK/reference.bin" "$ROOT/Programs/hello.asm" >/dev/null
"$TOOL" get "$WORK/native.img" hello.bin "$WORK/native.bin" >/dev/null 2>&1
if [ -f "$WORK/native.bin" ]; then
    REPORT="$(wc -c < "$WORK/native.bin" | tr -d ' ') bytes"
fi
check "byte for byte" cmp -s "$WORK/native.bin" "$WORK/reference.bin"

# ---- And what it built actually runs ----
"$EMU" --fast --cycles 100000 "$WORK/native.bin" > "$WORK/ran.txt" 2>&1
check "and it runs" grep -q "^Hello, World!$" "$WORK/ran.txt"

# ---- The report it printed says what it did ----
REPORT="$(grep -o 'program [0-9]*, data [0-9]*, labels [0-9]*' "$WORK/session.txt" | head -1 || true)"
check "it counted right" grep -q "program 17, data 14, labels 2" "$WORK/session.txt"

# ---- And the applications, which need an include, a base and the service names ----
#
# A loadable program is the harder case and the one that matters: #Include splices another
# file in, #Base moves every label to where the program will really live, and every SWI in
# them names a vector declared in a file the source never mentions by number.
for app in $APPS; do
    "$ASM" -I "$ROOT/Programs/CosmOS/Source" -o "$WORK/ref-$app.sbx" \
        "$ROOT/Programs/CosmOS/Apps/$app.asm" >/dev/null
    rm -f "$WORK/got-$app.sbx"
    "$TOOL" get "$WORK/native.img" "$app.sbx" "$WORK/got-$app.sbx" >/dev/null 2>&1
    if [ -f "$WORK/got-$app.sbx" ]; then
        REPORT="$(wc -c < "$WORK/got-$app.sbx" | tr -d ' ') bytes"
    fi
    check "$app byte for byte" cmp -s "$WORK/got-$app.sbx" "$WORK/ref-$app.sbx"
done

echo
if [ "$FAIL" -eq 0 ]; then
    echo "All $PASS native assembler checks passed."
else
    echo "$PASS passed, $FAIL failed: ${FAILED_NAMES[*]}"
    echo
    echo "The session was:"
    sed 's/^/    /' "$WORK/session.txt"
    exit 1
fi
