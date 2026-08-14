// utility.c
// Utilities for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/15/2024

#include "utility.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include "../Assembler/assembly.h"

void printHelp(const char *programName) {
    printf("Usage: %s [OPTIONS] <binaryfile>\n", programName);
    printf("\n");
    printf("Options:\n");
    printf("  -d, --debug       Enable debug mode.\n");
    printf("  -c, --cycles N    Stop after N cycles instead of running until the program halts.\n");
    printf("  -f, --fast        Run as fast as possible, ignoring the emulated cycle rate.\n");
    printf("  -h, --help        Display this help message.\n");
}

uint8_t parseOptions(int argc, char *argv[], EmulatorOptions *options) {
    static struct option long_options[] = {
        {"debug",  no_argument,       0, 'd'},
        {"cycles", required_argument, 0, 'c'},
        {"fast",   no_argument,       0, 'f'},
        {"help",   no_argument,       0, 'h'},
        {0,        0,                 0,  0 }
        };
        int opt;
        int option_index = 0;

    options->debug = 0;
    options->fast = 0;
    options->cycles = 0;

    // Parse options
    while ((opt = getopt_long(argc, argv, "dc:fh", long_options, &option_index)) != -1) {
        switch (opt) {
            case 'd':
                options->debug = 1;
            break;
            case 'c': {
                // The count has to be a plain positive number. Anything else is
                // almost certainly a mistyped command line rather than a request
                // to run zero cycles.
                char *end;
                long value = strtol(optarg, &end, 10);
                if (*end != '\0' || value <= 0) {
                    fprintf(stderr, "Error: --cycles needs a positive number, not \"%s\".\n", optarg);
                    return OPTIONS_ERROR;
                }
                options->cycles = (unsigned long)value;
            }
            break;
            case 'f':
                options->fast = 1;
            break;
            case 'h':
                printHelp(argv[0]);
                return OPTIONS_HELP;
            default:
                printHelp(argv[0]);
                return OPTIONS_ERROR;
        }
    }
    return OPTIONS_OK;
}

void printRegisters(CPURegisters *cpu, uint8_t *Program, uint8_t *Data) {
    printf("***** CPU Registers *****\n");
    printf("A: 0x%02X\tB: 0x%02X\tQ: 0x%02X\tStatus: 0b%08b\n", cpu->A, cpu->B, cpu->Q, cpu->Status);
    printf("Program Counter: 0x%04X     Current Instruction: 0x%02X (%s)\n", cpu->ProgramCounter, Program[cpu->ProgramCounter],getMnemonic(Program[cpu->ProgramCounter]));
    printf("   Data Pointer: 0x%04X      Current Data Value: 0x%02X\n", cpu->DataPointer[0], Data[cpu->DataPointer[0]]);
    printf("  Stack Pointer: 0x%04X           Current Value: (0x%02X) (0x%02X)\n", cpu->StackPointer, Data[cpu->StackPointer+1], Data[cpu->StackPointer+2]);
}

