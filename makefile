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

# Both tools use POSIX interfaces that ISO C does not have: realpath, clock_gettime,
# strdup, dirname and getopt. Asking for POSIX.1-2008 by name means the build does
# not rely on the compiler happening to default to a mode where those are visible,
# and it survives someone overriding CFLAGS, which is why it is kept separate.
POSIXFLAGS = -D_POSIX_C_SOURCE=200809L

# Directories
SRC_DIR_EMU = Source/Emulator
SRC_DIR_ASM = Source/Assembler
OBJ_DIR = Object

# Source files
EMU_SRCS = emulator.c io.c controller.c utility.c cpu.c bootstrap.c assembly.c
ASM_SRCS = Assembler.c assembly.c firstPass.c Assm-util.c secondPass.c

EMU_OBJS = $(EMU_SRCS:%.c=$(OBJ_DIR)/%.o)
ASM_OBJS = $(ASM_SRCS:%.c=$(OBJ_DIR)/%.o)

# Output binary names
EMU_TARGET = SplitBit
ASM_TARGET = Assembler

# Default target: build both emulator and assembler
all: $(EMU_TARGET) $(ASM_TARGET)

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

# Compile assembler source files to object files
$(OBJ_DIR)/%.o: $(SRC_DIR_ASM)/%.c
	mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) $(POSIXFLAGS) $(DEPFLAGS) -c $< -o $@

# Pull in the header dependencies written out by the compiler above.
-include $(EMU_OBJS:.o=.d) $(ASM_OBJS:.o=.d)

# Run the test suite against the programs in Programs/
test: $(EMU_TARGET) $(ASM_TARGET)
	@./Tests/run.sh

# Rebuild both tools with the address and undefined behaviour sanitizers and run
# the test suite under them. Slower than 'make test', and worth running before a
# release or after anything that touches memory handling.
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
	rm -f $(EMU_TARGET) $(ASM_TARGET)

# Install compiled binaries
install: $(EMU_TARGET) $(ASM_TARGET)
	mkdir -p "$(PREFIX)/bin"
	install -m 755 $^ "$(PREFIX)/bin/"

# Phony targets
.PHONY: all clean install test bless sanitize
