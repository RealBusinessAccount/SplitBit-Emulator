// utility.h
// Utilities for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/15/2024


#ifndef UTILITY_H
#define UTILITY_H

#include <stdint.h>
#include "cpu.h"

// Results of reading the command line.
#define OPTIONS_OK    0 // Carry on and run the program.
#define OPTIONS_HELP  1 // The user asked for help, so stop, but not because of an error.
#define OPTIONS_ERROR 2 // The command line was no good, stop and complain.

typedef struct {
    uint8_t debug;         // Step one instruction at a time, printing the registers.
    uint8_t fast;          // Ignore the cycle rate and run as fast as the host allows.
    unsigned long cycles;  // Stop after this many cycles. Zero means run until the program halts.
} EmulatorOptions;

uint8_t parseOptions(int argc, char *argv[], EmulatorOptions *options);

void printHelp(const char *programName);

uint8_t loadFile(char *path, uint8_t *Program, uint8_t *Data);

void bootStrap(uint8_t *Program, uint8_t *Data);

void printRegisters(CPURegisters *cpu, uint8_t *Program, uint8_t *Data);

#endif // UTILITY_H
