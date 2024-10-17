// emulator.c

// SplitBit Emulator
// Small 8-Bit Harvard Architecture CPU
// Written by Anachronaut
// 10/15/2024

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "cpu.h"
#include "utility.h"
#include <string.h>
#include <getopt.h>

uint8_t debugEnable = 0;
int cycleCount = 0;
char *programFile = NULL;

// Memory Banks:
uint8_t Program[0x10000], Data[0x10000];

int main (int argc, char *argv[]) {
    uint8_t test = parseOptions(argc, argv);
    if (test == 1){
        // Enable the Debug Mode.
        debugEnable = 1;
    } else if (test == 2){
        // User asked for help or gave a bad option, don't execute.
        return 1;
    }
    if (optind < argc) {
        programFile = argv[optind];
        optind++;
    } else {
        fprintf(stderr, "Error: No binary file specified.\n");
        printHelp(argv[0]);
        return 1;
    }
    if (optind < argc) {
        fprintf(stderr, "Error: Unexpected argument: %s\n", argv[optind]);
        return 1;
    }
    if (loadFile(programFile, Program, Data)) {
        fprintf(stderr, "Error: Couldn't read file: %s\n", programFile);
        return 1;
    }
    CPURegisters cpu;
    initializeCPU(&cpu, Program, Data);
    if(debugEnable) {
        printRegisters(&cpu, Program, Data);
    }
    while (!(cpu.Status & 0x80)) {
        executeOperation(cpu.Program[cpu.ProgramCounter], &cpu);
        cpu.ProgramCounter++;
        cycleCount++;
        if (debugEnable) {
            getchar();
            printRegisters(&cpu, Program, Data);
        }
    }
    printf("Execution halted after %u cycles.\n", cycleCount);
}
