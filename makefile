# SplitBit Emulator and Assembler Makefile
# Anachronaut
# 10/16/2024

# Compiler and flags
CC = gcc
CFLAGS = -Wall

# Directories
SRC_DIR_EMU = Source/Emulator
SRC_DIR_ASM = Source/Assembler
OBJ_DIR = Object

# Source files
EMU_SRCS = emulator.c io.c utility.c cpu.c bootstrap.c assembly.c
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
	$(CC) $(CFLAGS) -c $< -o $@

# Compile assembler source files to object files
$(OBJ_DIR)/%.o: $(SRC_DIR_ASM)/%.c
	mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Clean up object and binary files
clean:
	rm -rf $(OBJ_DIR)
	rm -f $(EMU_TARGET) $(ASM_TARGET)

# Phony targets
.PHONY: all clean
