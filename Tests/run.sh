#!/usr/bin/env bash
# run.sh
# Test runner for the SplitBit Emulator and Assembler.
# Written by Anachronaut
#
# Assembles and runs every program listed in Tests/manifest and compares the
# output against the recorded results in Tests/expected.
#
#   ./Tests/run.sh            Run the suite.
#   ./Tests/run.sh --bless    Record current output as the expected results.
#   ./Tests/run.sh <name>...  Run only the named tests.
#
# Programs are built inside Tests/build so that running the suite never touches
# the binaries in Programs/.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/Tests"
BUILD="$TESTS/build"
EXPECTED="$TESTS/expected"
INPUT="$TESTS/input"
MANIFEST="$TESTS/manifest"

ASSEMBLER="$ROOT/Assembler"
EMULATOR="$ROOT/SplitBit"

RUN_TIMEOUT=10

BLESS=0
ONLY=()

for arg in "$@"; do
    case "$arg" in
        --bless) BLESS=1 ;;
        -h|--help)
            sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) echo "run.sh: unknown option $arg" >&2; exit 2 ;;
        *) ONLY+=("$arg") ;;
    esac
done

for tool in "$ASSEMBLER" "$EMULATOR"; do
    if [ ! -x "$tool" ]; then
        echo "run.sh: $tool is missing. Run 'make' first." >&2
        exit 2
    fi
done

PROGRAMS="$ROOT/Programs"

rm -rf "$BUILD"
mkdir -p "$BUILD" "$EXPECTED"

# Disk images the tests read from are built here, with the host tool, before anything
# runs. The build directory is thrown away above, so they are always freshly made.
if [ -x "$TESTS/makedisks.sh" ]; then
    "$TESTS/makedisks.sh" "$BUILD" || { echo "Couldn't build the test disks."; exit 1; }
fi

PASS=0
FAIL=0
BLESSED=0
FAILED_NAMES=()

wanted() {
    [ ${#ONLY[@]} -eq 0 ] && return 0
    local n
    for n in "${ONLY[@]}"; do [ "$n" = "$1" ] && return 0; done
    return 1
}

report() {
    # report <status> <name> <detail>
    printf '  [%-4s] %-20s %s\n' "$1" "$2" "$3"
}

trim() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "$v"
}

# Takes the cycle count out of the emulator's last line, in place.
#
# HOW MANY CYCLES A PROGRAM TOOK IS NOT WHAT ANY OF THESE TESTS ARE ABOUT, and having it in
# every recorded result made every one of them fragile in the same way: two instructions
# added to CosmOS moved the count in six unrelated files at once, so a real difference
# would have arrived in a crowd of meaningless ones and had to be picked out by hand.
#
# WHETHER a program stopped on its own or ran into its limit is kept, because that is
# behaviour and several tests exist to check it. Only the number goes.
#
# Anything that genuinely wants to measure cycles should say so out loud in a test of its
# own rather than every test carrying the measurement and nothing asserting anything about
# it.
settle() {
    sed -i -E 's/^Execution halted after [0-9]+ cycles\.$/Execution halted./;
               s/^Execution stopped after [0-9]+ cycles\. \(cycle limit reached\)$/Execution stopped. (cycle limit reached)/' "$1"
}

check() {
    # check <name> <actual-file>
    local name="$1" actual="$2" golden="$EXPECTED/$1.out"
    if [ "$BLESS" -eq 1 ]; then
        cp "$actual" "$golden"
        BLESSED=$((BLESSED + 1))
        report "rec" "$name" "$(wc -c < "$golden" | tr -d ' ') bytes recorded"
        return 0
    fi
    if [ ! -f "$golden" ]; then
        FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
        report "FAIL" "$name" "no recorded output; run with --bless"
        return 1
    fi
    if cmp -s "$actual" "$golden"; then
        PASS=$((PASS + 1))
        report "ok" "$name" ""
        return 0
    fi
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
    report "FAIL" "$name" "output differs"
    diff -u "$golden" "$actual" 2>/dev/null | head -20 | sed 's/^/         /'
    return 1
}

assemble() {
    # assemble <name> <source>; echoes the built binary path on success.
    # Everything builds from Programs/ with Libraries/ and CosmOS/ on the include path,
    # and the binary goes to Tests/build, so the source tree is never written to.
    # CosmOS is there because it owns the filesystem library and the service names, which
    # test programs outside it include.
    local name="$1" src="$2"
    local bin="$BUILD/$name.bin"
    if ( cd "$PROGRAMS" && "$ASSEMBLER" -I Libraries -I CosmOS/Source -o "$bin" "$src" ) >"$BUILD/.assemble.log" 2>&1; then
        echo "$bin"
        return 0
    fi
    return 1
}

while IFS='|' read -r name src mode stdin limit disk; do
    name="$(trim "$name")"
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    src="$(trim "$src")"
    mode="$(trim "$mode")"; stdin="$(trim "$stdin")"
    limit="$(trim "$limit")"; disk="$(trim "$disk")"
    [ -z "$disk" ] && disk="-"

    wanted "$name" || continue

    if [ "$mode" = "xfail" ]; then
        if assemble "$name" "$src" >/dev/null; then
            FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
            report "FAIL" "$name" "expected assembly to fail, but it succeeded"
        else
            PASS=$((PASS + 1))
            report "ok" "$name" "fails as recorded: $(head -1 "$BUILD/.assemble.log" | tr -d '\033' | sed 's/\[[0-9;]*m//g')"
        fi
        continue
    fi

    if ! BIN="$(assemble "$name" "$src")"; then
        FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
        report "FAIL" "$name" "assembly failed"
        head -3 "$BUILD/.assemble.log" | tr -d '\033' | sed 's/\[[0-9;]*m//g' | sed 's/^/         /'
        continue
    fi

    if [ "$mode" = "assemble" ]; then
        PASS=$((PASS + 1))
        report "ok" "$name" "assembles"
        continue
    fi

    if [ "$stdin" != "-" ] && [ ! -f "$INPUT/$stdin" ]; then
        FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
        report "FAIL" "$name" "missing input fixture $stdin"
        continue
    fi
    IN=/dev/null
    [ "$stdin" != "-" ] && IN="$INPUT/$stdin"

    OUT="$BUILD/.out"
    case "$mode" in
        run)
            # --fast because there is nothing to learn from waiting out the emulated
            # clock, and --cycles for programs that never halt on their own, which
            # bounds them by cycle count rather than by wall clock.
            EMUARGS=(--fast)
            [ "$limit" != "-" ] && EMUARGS+=(--cycles "$limit")
            # A disk starts fresh for every run, so a test cannot pass because of what a
            # previous one left lying on it. The emulator makes the image if it is
            # missing, which is what removing it first arranges for.
            if [ "$disk" != "-" ]; then
                # A trailing :ro attaches the image write protected, so that a test can
                # check the device bars writes rather than the filesystem asking nicely.
                DISKFILE="${disk%:ro}"
                # A name with a directory in it is one of the images makedisks.sh built,
                # and is used as it stands. A bare name is scratch: it is removed first so
                # that nothing a test writes can be seen by the next one, and the emulator
                # makes a blank image in its place.
                case "$DISKFILE" in
                    */*) ;;
                    *) rm -f "$BUILD/$DISKFILE" ;;
                esac
                EMUARGS+=(--disk "$BUILD/$DISKFILE")
                [ "$disk" != "$DISKFILE" ] && EMUARGS+=(--write-protect)
            fi
            timeout "$RUN_TIMEOUT" "$EMULATOR" "${EMUARGS[@]}" "$BIN" <"$IN" >"$OUT" 2>&1
            STATUS=$?
            if [ "$STATUS" -eq 124 ]; then
                FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
                report "FAIL" "$name" "did not finish within ${RUN_TIMEOUT}s"
                continue
            fi
            # What a program exits with is part of what it does, so it is recorded
            # with the output rather than thrown away. A program that faults is
            # supposed to exit non zero, and that should be just as pinned down as
            # what it printed.
            printf '[exit %d]\n' "$STATUS" >> "$OUT"
            settle "$OUT"
            check "$name" "$OUT"
            ;;
        *)
            FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
            report "FAIL" "$name" "unknown mode '$mode' in manifest"
            ;;
    esac
done < "$MANIFEST"

echo
if [ "$BLESS" -eq 1 ]; then
    echo "Recorded $BLESSED expected results into Tests/expected."
    exit 0
fi
if [ "$FAIL" -eq 0 ]; then
    echo "All $PASS tests passed."
    exit 0
fi
echo "$PASS passed, $FAIL failed: ${FAILED_NAMES[*]}"
exit 1
