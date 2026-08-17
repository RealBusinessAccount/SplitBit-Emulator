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
# CosmOS owns the filesystem library and the service names, so it is a place to look too.
INCLUDES = -I Libraries -I CosmOS/Source

# The programs worth building. Files in Libraries/ are left out because they have no
# entry point of their own, and the ones in testPrograms/ are covered by 'make test'
# in the parent directory.
PROGRAMS = \
	CosmOS/Source/cosmos.asm \
	hello.asm \
	printHello.asm \
	inputTest.asm \
	replCalculator.asm \
	Fibonacci/8bitFibonacci.asm \
	Fibonacci/16bitFibonacci.asm \
	Fibonacci/32bitFibonacci.asm \
	primeSieve/8bitSieve.asm \
	primeSieve/16bitSegmentedSieve.asm \
	primeSieve/16bitSegmentedSieveModern.asm \
	gameOfLife/16x16Life.asm \
	gameOfLife/16x16LifeModern.asm

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

# ---- CosmOS ----
#
#   make cosmos       Assemble the system and everything it can load.
#   make cosmos-disk  ... and put the loadable programs on a disk image.
#   make run-cosmos   ... and boot the machine with that disk in the drive.
#
# Programs in Apps/ say where they live with #Base, so the assembler writes them out as
# loadable programs rather than as boot images. They are named .sbx to keep that
# difference visible: a .bin is something the machine boots, a .sbx is something a
# running system loads.

DISKTOOL ?= ../SplitDisk
COSMOS = $(BUILD)/CosmOS/Source/cosmos.bin
APPS = $(patsubst CosmOS/Apps/%.asm,$(BUILD)/CosmOS/Apps/%.sbx,$(wildcard CosmOS/Apps/*.asm))
COSMOS_DISK = $(BUILD)/cosmos.img
DEPENDENCIES += $(APPS:.sbx=.d)

$(BUILD)/CosmOS/Apps/%.sbx: CosmOS/Apps/%.asm
	@mkdir -p $(@D)
	$(ASM) $(INCLUDES) -M $(@:.sbx=.d) -o $@ $<

cosmos: $(COSMOS) $(APPS)

# Made from scratch every time, so that what is on it is what is in Apps/ now and not
# also whatever used to be.
$(COSMOS_DISK): $(APPS)
	@mkdir -p $(@D)
	rm -f $@
	$(DISKTOOL) format $@ 64 2
	@for app in $(APPS); do $(DISKTOOL) put $@ $$app; done

cosmos-disk: $(COSMOS_DISK)

run-cosmos: $(COSMOS) $(COSMOS_DISK)
	$(EMU) --disk $(COSMOS_DISK) $(COSMOS)

clean:
	rm -rf $(BUILD)

# Pull in the dependency rules written by -M above, so that touching a library
# reassembles every program that includes it.
-include $(DEPENDENCIES)

.PHONY: all clean cosmos cosmos-disk run-cosmos
