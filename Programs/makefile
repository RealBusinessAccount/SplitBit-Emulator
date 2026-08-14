# SplitBit Programs Makefile
# Anachronaut
#
# Builds every SplitBit program into build/, and keeps track of which libraries
# each one includes so that editing a library reassembles whatever depends on it.
#
#   make            Assemble everything.
#   make clean      Throw away build/.
#   make run-hello  Assemble and run one program.

ASM ?= ../Assembler
EMU ?= ../SplitBit
BUILD ?= build

# Libraries are included by bare name, so the assembler is told where to find them.
INCLUDES = -I Libraries

# The programs worth building. Files in Libraries/ are left out because they have no
# entry point of their own, and the ones in testPrograms/ are covered by 'make test'
# in the parent directory.
PROGRAMS = \
	hello.asm \
	printHello.asm \
	inputTest.asm \
	replCalculator.asm \
	Fibonacci/8bitFibonacci.asm \
	Fibonacci/16bitFibonacci.asm \
	Fibonacci/32bitFibonacci.asm \
	primeSieve/8bitSieve.asm \
	primeSieve/16bitSegmentedSieve.asm \
	gameOfLife/16x16Life.asm

BINARIES = $(PROGRAMS:%.asm=$(BUILD)/%.bin)
DEPENDENCIES = $(BINARIES:.bin=.d)

all: $(BINARIES)

# -M writes out which source files went into the binary, in the form of a make rule.
$(BUILD)/%.bin: %.asm
	@mkdir -p $(@D)
	$(ASM) $(INCLUDES) -M $(@:.bin=.d) -o $@ $<

# Assemble and run a single program, as in 'make run-hello'.
run-%: $(BUILD)/%.bin
	$(EMU) $<

clean:
	rm -rf $(BUILD)

# Pull in the dependency rules written by -M above, so that touching a library
# reassembles every program that includes it.
-include $(DEPENDENCIES)

.PHONY: all clean
