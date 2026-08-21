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

# The assembler that runs on the machine. It is not in Apps/ because it is not one file:
# it has a directory of its own, the way the C assembler does. Its own pieces are found
# beside it without being told, since an include is looked for next to the file that asked
# for it before anywhere else; only services.asm needs the include path.
NATIVE_ASM = $(BUILD)/CosmOS/Assembler/Asm.sbx
DEPENDENCIES += $(NATIVE_ASM:.sbx=.d)

$(NATIVE_ASM): CosmOS/Assembler/Asm.asm
	@mkdir -p $(@D)
	$(ASM) $(INCLUDES) -M $(@:.sbx=.d) -o $@ $<

cosmos: $(COSMOS) $(APPS) $(NATIVE_ASM)

# Made from scratch every time, so that what is on it is what is in Apps/ now and not
# also whatever used to be.
$(COSMOS_DISK): $(APPS) $(NATIVE_ASM) testPrograms/stringKeyword.asm \
                CosmOS/Apps/hello.asm CosmOS/Apps/Say.asm CosmOS/Source/services.asm
	@mkdir -p $(@D)
	rm -f $@
	$(DISKTOOL) format $@ 2048 4
	@for app in $(APPS); do $(DISKTOOL) put $@ $$app; done
	$(DISKTOOL) put $@ $(NATIVE_ASM)
	@# SOURCE goes on as well, because an assembler with nothing to assemble is a
	@# demonstration of nothing.
	@#
	@# hello.asm and Say.asm are the APPLICATION versions, so each assembles to a .sbx
	@# written straight over the one the host tool put there - which means the next
	@# thing loaded is a program the machine built itself, in the same breath.
	@#
	@# strings.asm is the odd one out on purpose: it has no #Include and no #Base, so it
	@# comes out as a boot image rather than a loadable program, and the difference
	@# between the two is visible on one disk.
	$(DISKTOOL) put $@ CosmOS/Apps/hello.asm
	$(DISKTOOL) put $@ CosmOS/Apps/Say.asm
	$(DISKTOOL) put $@ CosmOS/Source/services.asm
	$(DISKTOOL) put $@ testPrograms/stringKeyword.asm strings.asm

# The system as well as the disk. Building only the image leaves whatever cosmos.bin was
# there before, or none at all, and then the disk is booted with a system that does not
# match the programs on it.
cosmos-disk: $(COSMOS) $(COSMOS_DISK)

run-cosmos: $(COSMOS) $(COSMOS_DISK)
	$(EMU) --disk $(COSMOS_DISK) $(COSMOS)

clean:
	rm -rf $(BUILD)

# Pull in the dependency rules written by -M above, so that touching a library
# reassembles every program that includes it.
-include $(DEPENDENCIES)

.PHONY: all clean cosmos cosmos-disk run-cosmos
