# SplitBit Emulator and Assembler Makefile
# Anachronaut
# 10/16/2024

# Compiler and flags
CC ?= gcc
CFLAGS ?= -Wall -Os
PREFIX ?= /usr/local

# Have the compiler write out which headers each object depends on, so that
# editing a header rebuilds everything that includes it.
DEPFLAGS = -MMD -MP

# The emulator and the assembler use POSIX interfaces that ISO C does not have:
# realpath, clock_gettime,
# strdup, dirname and getopt. Asking for POSIX.1-2008 by name means the build does
# not rely on the compiler happening to default to a mode where those are visible,
# and it survives someone overriding CFLAGS, which is why it is kept separate.
#
# _XOPEN_SOURCE=700 IS POSIX.1-2008, plus the XSI extensions. The plain
# _POSIX_C_SOURCE=200809L was here and is not quite enough: realpath is an XSI interface,
# so under -std=c11 -pedantic it went undeclared and the assembler would not compile. The
# ordinary build never noticed, because without -std=c11 the compiler's own default
# already declares it. The README makes a claim about the strict build, so 'make strict'
# below settles it rather than leaving it to be discovered.
POSIXFLAGS = -D_XOPEN_SOURCE=700

# Directories
SRC_DIR_EMU = Source/Emulator
SRC_DIR_ASM = Source/Assembler
SRC_DIR_DSK = Source/DiskTool
OBJ_DIR = Object

# Source files
EMU_SRCS = emulator.c io.c controller.c utility.c cpu.c bootstrap.c assembly.c
ASM_SRCS = Assembler.c assembly.c firstPass.c Assm-util.c secondPass.c
DSK_SRCS = SplitDisk.c

EMU_OBJS = $(EMU_SRCS:%.c=$(OBJ_DIR)/%.o)
ASM_OBJS = $(ASM_SRCS:%.c=$(OBJ_DIR)/%.o)
DSK_OBJS = $(DSK_SRCS:%.c=$(OBJ_DIR)/%.o)

# Output binary names
EMU_TARGET = SplitBit
ASM_TARGET = Assembler
DSK_TARGET = SplitDisk

# Default target: build both emulator and assembler
all: $(EMU_TARGET) $(ASM_TARGET) $(DSK_TARGET)

# Emulator binary
$(EMU_TARGET): $(EMU_OBJS)
	$(CC) $(CFLAGS) -o $(EMU_TARGET) $(EMU_OBJS)

# Assembler binary
$(ASM_TARGET): $(ASM_OBJS)
	$(CC) $(CFLAGS) -o $(ASM_TARGET) $(ASM_OBJS)

# Compile emulator source files to object files
$(OBJ_DIR)/%.o: $(SRC_DIR_EMU)/%.c
	mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) $(POSIXFLAGS) $(DEPFLAGS) -c $< -o $@

# Disk tool binary
$(DSK_TARGET): $(DSK_OBJS)
	$(CC) $(CFLAGS) -o $(DSK_TARGET) $(DSK_OBJS)

# Compile disk tool source files to object files
$(OBJ_DIR)/%.o: $(SRC_DIR_DSK)/%.c
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) $(POSIXFLAGS) $(DEPFLAGS) -c $< -o $@

# Compile assembler source files to object files
$(OBJ_DIR)/%.o: $(SRC_DIR_ASM)/%.c
	mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) $(POSIXFLAGS) $(DEPFLAGS) -c $< -o $@

# Pull in the header dependencies written out by the compiler above.
-include $(EMU_OBJS:.o=.d) $(ASM_OBJS:.o=.d) $(DSK_OBJS:.o=.d)

# ---- The strict build the README promises ----
#
# "The sources are ISO C and build clean under -std=c11 -pedantic with -Wall -Wextra."
# That is a claim somebody may check by typing it, so the suite checks it first. It was
# false when this target was written: realpath went undeclared under a feature test macro
# that did not reach far enough, which the ordinary -Os build never saw.
STRICT = -std=c11 -pedantic -Wall -Wextra -Werror $(POSIXFLAGS)

strict:
	@for source in $(SRC_DIR_EMU)/*.c $(SRC_DIR_ASM)/*.c $(SRC_DIR_DSK)/*.c; do \
		$(CC) $(STRICT) -c $$source -o /dev/null || exit 1; \
	done
	@echo "The sources build clean under -std=c11 -pedantic."

# Run the test suite against the programs in Programs/
test: $(EMU_TARGET) $(ASM_TARGET) $(DSK_TARGET) strict
	@echo
	@./Tests/run.sh
	@echo
	@./Tests/disk.sh
	@echo
	@./Tests/terminal.sh
	@echo
	@./Tests/native.sh
	@echo
	@./Tests/docs.sh

# Rebuild all three tools with the address and undefined behaviour sanitizers and run
# the test suite under them. Slower than 'make test', and worth running before a
# release or after anything that touches memory handling.
#
# THE WHOLE SUITE, which it did not used to be: it built all three tools sanitized and
# then ran only run.sh and terminal.sh, so SplitDisk was compiled with the sanitizers and
# never exercised, and native.sh - which drives the assembler and the emulator harder than
# anything else here - was skipped. Those are the parts where block arithmetic on disk
# images and buffer indexing in two assemblers live, which is exactly what the sanitizers
# are for. Adding the three of them costs about six seconds.
#
# The sanitizers catch reads and writes off the end of an array, use after free,
# leaks, and undefined arithmetic. They also fill fresh allocations with a junk
# pattern, which is what turns a read of uninitialised memory from something that
# quietly works into something the tests notice.
#
# If the suite fails, the sanitizer binaries are deliberately left in place so
# that the failing case can be run again by hand. 'make' puts the normal ones back.
SANITIZE_FLAGS = -Wall -Wextra -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer

sanitize:
	@$(MAKE) --no-print-directory clean
	@$(MAKE) --no-print-directory CFLAGS="$(SANITIZE_FLAGS)"
	@echo "Running the test suite under AddressSanitizer and UndefinedBehaviorSanitizer."
	@./Tests/run.sh
	@echo
	@./Tests/disk.sh
	@echo
	@./Tests/terminal.sh
	@echo
	@./Tests/native.sh
	@echo
	@./Tests/docs.sh
	@$(MAKE) --no-print-directory clean
	@$(MAKE) --no-print-directory
	@echo "Sanitizer run finished cleanly. Normal binaries rebuilt."

# Record the current output of every test as the expected result.
# Only do this when the current output is known to be correct.
bless: $(EMU_TARGET) $(ASM_TARGET)
	@./Tests/run.sh --bless

# Clean up object and binary files
clean:
	rm -rf $(OBJ_DIR)
	rm -rf Tests/build
	rm -f $(EMU_TARGET) $(ASM_TARGET) $(DSK_TARGET)

# Install compiled binaries
install: $(EMU_TARGET) $(ASM_TARGET) $(DSK_TARGET)
	mkdir -p "$(PREFIX)/bin"
	install -m 755 $^ "$(PREFIX)/bin/"

# Phony targets
.PHONY: all clean install test bless sanitize
