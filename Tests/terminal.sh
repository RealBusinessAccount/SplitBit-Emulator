#!/usr/bin/env bash
# Checks the things a recorded output cannot see.
#
# Every other test in this suite pipes standard input in and standard output to a file, and
# compares what came out against what came out last time. That answers "what does this
# program print", which is the right question almost always, and it is blind to two whole
# classes of behaviour:
#
#   WHEN something is printed. Piped output is fully buffered and flushed when the process
#   ends, so a prompt that appears before input is read and a prompt that appears an hour
#   later produce byte-identical files. A prompt printed after the answer it was asking for
#   is invisible to every other test here.
#
#   WHAT HAPPENS TO THE TERMINAL. Key mode only touches a terminal when there is one, so
#   with input from a file there is nothing to put into another state and nothing to put
#   back. A machine that leaves the terminal without echo passes all 92 other tests.
#
# Both of those have gone wrong in this repository, and both were found by a person whose
# terminal stopped working rather than by anything here. So this runs the emulator under a
# pseudo-terminal, which is what makes those questions askable at all.
#
# Written by Anachronaut

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

BUILD="$ROOT/Tests/build/terminal"
mkdir -p "$BUILD"

[ -x "$ROOT/SplitBit" ] || { echo "The emulator is not built."; exit 1; }
[ -x "$ROOT/Assembler" ] || { echo "The assembler is not built."; exit 1; }

# A program that asks for key mode and then waits for a key that never comes. Every check
# below needs a machine that is sitting in key mode with the terminal in its hands.
cat > "$BUILD/keywait.asm" <<'ASM'
#Program
start:
  INIA 0x01
  OUTA 0x02
  INA 0x00
  HALT
ASM

# A program that prints something with no newline after it and then waits, which is the
# shape of a prompt and the shape the buffering problem hides in.
cat > "$BUILD/prompt.asm" <<'ASM'
#Program
start:
  INIA 0d62             ; '>'
  OUTA 0x00
  INIA 0x20
  OUTA 0x00
  INA 0x00
  HALT
ASM

"$ROOT/Assembler" "$BUILD/keywait.asm" -o "$BUILD/keywait.bin" >/dev/null 2>&1 || {
    echo "Could not assemble the terminal test programs."; exit 1; }
"$ROOT/Assembler" "$BUILD/prompt.asm" -o "$BUILD/prompt.bin" >/dev/null 2>&1 || {
    echo "Could not assemble the terminal test programs."; exit 1; }

python3 - "$ROOT" "$BUILD" <<'PY'
import os
import pty
import select
import signal
import sys
import time

root, build = sys.argv[1], sys.argv[2]
emulator = os.path.join(root, "SplitBit")

passed = 0
problems = []


def report(ok, what, detail=""):
    global passed
    if ok:
        passed += 1
        print("  [ok  ] %s" % what)
    else:
        problems.append(what if not detail else "%s: %s" % (what, detail))
        print("  [FAIL] %s%s" % (what, (" - " + detail) if detail else ""))


def underPty(script, seconds=10):
    """Runs a shell script with a pseudo-terminal for its controlling terminal, and
    gives back everything the terminal saw."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execv("/bin/bash", ["/bin/bash", "-c", script])
    seen = b""
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            seen += chunk
        if os.waitpid(pid, os.WNOHANG)[0]:
            break
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    os.close(fd)
    return seen


# ---- A prompt is shown before the answer to it is asked for ----
#
# The machine writes "> " and then waits. Nothing more will ever be printed, so if the two
# characters have not arrived after a second of waiting, they are sitting in a buffer and
# the person at the terminal is looking at nothing and being asked to answer it.
#
# This is exactly the bug that getchar used to hide: reading through stdio flushed the line
# buffered streams first, and reading with read() does not.
pid, fd = pty.fork()
if pid == 0:
    os.execv(emulator, [emulator, "--fast", os.path.join(build, "prompt.bin")])
seen = b""
end = time.time() + 1.5
while time.time() < end:
    ready, _, _ = select.select([fd], [], [], 0.2)
    if ready:
        try:
            seen += os.read(fd, 1024)
        except OSError:
            break
report(b">" in seen, "a prompt is shown before its answer is read",
       "" if b">" in seen else "nothing arrived in 1.5s, so it is stuck in a buffer")
try:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
except (ProcessLookupError, ChildProcessError):
    pass
os.close(fd)


# ---- A key arrives without Return ----
#
# Which is the whole of what key mode is for. In line mode the terminal holds what is typed
# until Return, so a machine that failed to ask for key mode would wait here for ever.
pid, fd = pty.fork()
if pid == 0:
    os.execv(emulator, [emulator, "--fast", os.path.join(build, "keywait.bin")])
time.sleep(0.5)
os.write(fd, b"x")                      # No newline, on purpose.
finished = False
end = time.time() + 2
while time.time() < end:
    if os.waitpid(pid, os.WNOHANG)[0]:
        finished = True
        break
    time.sleep(0.05)
report(finished, "a single keystroke arrives without Return",
       "" if finished else "the machine was still waiting, so the key was held by the terminal")
try:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
except (ProcessLookupError, ChildProcessError):
    pass
os.close(fd)


# ---- The terminal is handed back however the machine dies ----
#
# atexit covers stopping on purpose and nothing else: it does not run when a process is
# killed by a signal. SIGHUP is the one that matters most, because it is what arrives when
# whatever launched the machine dies and takes the terminal with it - and a terminal left
# in key mode has no echo and no line editing, which is a far worse failure than anything
# the program was doing.
for name in ("HUP", "INT", "QUIT", "ABRT", "SEGV", "TERM"):
    # Cleared first. Without this a run that dies before it can measure leaves the PREVIOUS
    # signal's files in place, and the check compares those and passes - which is how the
    # SIGQUIT case came to be reporting success while proving nothing at all.
    for leftover in ("before.txt", "after.txt"):
        try:
            os.remove(os.path.join(build, leftover))
        except FileNotFoundError:
            pass
    script = (
        # No core files. Two of these signals dump core by default, and a test suite has no
        # business leaving those around every time it runs. It also keeps the measuring
        # shell alive through SIGQUIT, which otherwise takes it down before it can look.
        "ulimit -c 0\n"
        "stty -g > {b}/before.txt\n"
        "{e} --fast {b}/keywait.bin < /dev/tty &\n"
        "P=$!\n"
        "sleep 0.5\n"
        "kill -{s} $P 2>/dev/null\n"
        "wait $P 2>/dev/null\n"
        "sleep 0.3\n"
        "stty -g > {b}/after.txt\n"
    ).format(b=build, e=emulator, s=name)
    # < /dev/tty is load bearing. A background job in a non-interactive shell gets its
    # standard input from /dev/null, so without it the machine never sees a terminal, never
    # enters key mode, and has nothing to fail to put back - and this check would pass
    # against a machine that restores nothing at all.
    underPty(script)
    try:
        before = open(os.path.join(build, "before.txt")).read().strip()
        after = open(os.path.join(build, "after.txt")).read().strip()
    except FileNotFoundError:
        # A failure, and for SIGQUIT this is the shape the failure takes: a machine that
        # does not handle it dies in a way that takes the measuring shell with it, so what
        # is reported is not "the terminal was left wrong" but "nothing got as far as
        # looking". Both mean the same thing here, which is that the signal is unhandled.
        report(False, "the terminal is restored after SIG%s" % name, "could not measure")
        continue
    report(before == after, "the terminal is restored after SIG%s" % name,
           "" if before == after else "left as %s, was %s" % (after[:24], before[:24]))


# ---- Suspending is not dying ----
#
# Ctrl-Z has to hand the terminal back while the machine is stopped, because whoever gets it
# next is entitled to find it as they left it, and take key mode again on resume, because
# the machine has not finished with it.
script = (
    "ulimit -c 0\n"
    "stty -g > {b}/t0.txt\n"
    "{e} --fast {b}/keywait.bin < /dev/tty &\n"
    "P=$!\n"
    "sleep 0.5\n"
    "kill -TSTP $P; sleep 0.4\n"
    "stty -g > {b}/t1.txt\n"
    "kill -CONT $P; sleep 0.4\n"
    "stty -g > {b}/t2.txt\n"
    "kill -TERM $P; sleep 0.2\n"
).format(b=build, e=emulator)
underPty(script)
try:
    t0 = open(os.path.join(build, "t0.txt")).read().strip()
    t1 = open(os.path.join(build, "t1.txt")).read().strip()
    t2 = open(os.path.join(build, "t2.txt")).read().strip()
    report(t1 == t0, "the terminal is handed back while suspended")
    report(t2 != t0, "key mode is taken again on resume")
except FileNotFoundError:
    report(False, "suspending and resuming", "could not measure")

print()
if problems:
    print("The terminal does not survive everything it should:")
    for p in problems:
        print("  " + p)
    sys.exit(1)
print("All %d terminal checks passed." % passed)
PY
