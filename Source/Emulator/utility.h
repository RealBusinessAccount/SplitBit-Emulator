// utility.h
// Utilities for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/15/2024


#ifndef UTILITY_H
#define UTILITY_H

#include <stdint.h>
#include "cpu.h"

uint8_t parseOptions(int argc, char *argv[]);

void printHelp(const char *programName);

uint8_t loadFile(char *path, uint8_t *Program, uint8_t *Data);

void bootStrap(uint8_t *Program, uint8_t *Data);

void printRegisters(CPURegisters *cpu, uint8_t *Program, uint8_t *Data);

#endif // UTILITY_H
