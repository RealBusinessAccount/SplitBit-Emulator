# SplitBit Emulator Makefile
# Anachronaut
# 10/16/2024

# Compiler and flags
CC = gcc
CFLAGS = -Wall

# Directories
SRC_DIR = Source
OBJ_DIR = Object

# Source files
SRCS = emulator.c io.c utility.c assembly.c cpu.c bootstrap.c
OBJS = $(SRCS:%.c=$(OBJ_DIR)/%.o)

# Output binary name
TARGET = SplitBit

# Default target
all: $(TARGET)

# Create binary by linking object files
$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $(TARGET) $(OBJS)

# Compile source files to object files
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Clean up object and binary files
clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR)

# Phony targets
.PHONY: all clean
