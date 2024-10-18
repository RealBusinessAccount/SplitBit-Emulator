// utility.c
// Utilities for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/15/2024

#include "utility.h"
#include <stdio.h>
#include <string.h>
#include <getopt.h>
#include "assembly.h"

void printHelp(const char *programName) {
    printf("Usage: %s [OPTIONS] <binaryfile>\n", programName);
    printf("\n");
    printf("Options:\n");
    printf("  -d, --debug       Enable debug mode.\n");
    printf("  -h, --help        Display this help message.\n");
}

uint8_t parseOptions(int argc, char *argv[]) {
    static struct option long_options[] = {
        {"debug", no_argument, 0, 'd'},
        {"help",  no_argument, 0, 'h'},
        {0,       0,           0,  0 }
        };
        int opt;
        int option_index = 0;

    // Parse options
    while ((opt = getopt_long(argc, argv, "dh", long_options, &option_index)) != -1) {
        switch (opt) {
            case 'd':
                return 1;
                break;
            case 'h':
                printHelp(argv[0]);
                return 2;
            case '?':
                printHelp(argv[0]);
                return 2;
            default:
                printHelp(argv[0]);
            return 2;
        }
    }
    return 0;
}

void printRegisters(CPURegisters *cpu, uint8_t *Program, uint8_t *Data) {
    printf("***** CPU Registers *****\n");
    printf("A: 0x%02X\tB: 0x%02X\tQ: 0x%02X\tStatus: 0b%08b\n", cpu->A, cpu->B, cpu->Q, cpu->Status);
    printf("Program Counter: 0x%04X     Current Instruction: 0x%02X (%s)\n", cpu->ProgramCounter, Program[cpu->ProgramCounter],getMnemonic(Program[cpu->ProgramCounter]));
    printf("   Data Pointer: 0x%04X      Current Data Value: 0x%02X\n", cpu->DataPointer, Data[cpu->DataPointer]);
    printf("  Stack Pointer: 0x%04X           Current Value: (0x%02X) (0x%02X)\n", Data[cpu->StackPointer], Data[cpu->StackPointer+1], Data[cpu->StackPointer+2]);
}

