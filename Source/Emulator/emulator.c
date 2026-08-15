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
#include <time.h>

// nanoseconds per second
#define NS_PER_SEC 1000000000LL
#define CYCLE_RATE 1000000

typedef struct {
    long long  cycles_per_sec;   // e.g. 1000000 for 1 MHz
    long long  accumulator_ns;   // unspent nanoseconds
    struct timespec prev;
} CycleTimer;

static inline long long timespec_diff_ns(struct timespec a, struct timespec b) {
    return (a.tv_sec - b.tv_sec) * NS_PER_SEC + (a.tv_nsec - b.tv_nsec);
}

void cycle_timer_init(CycleTimer *t, long long cycles_per_sec) {
    t->cycles_per_sec  = cycles_per_sec;
    t->accumulator_ns  = 0;
    clock_gettime(CLOCK_MONOTONIC, &t->prev);
}

// Call once per host frame. Returns how many SplitBit cycles to execute.
int cycle_timer_tick(CycleTimer *t) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);

    long long elapsed = timespec_diff_ns(now, t->prev);
    t->prev = now;

    // optional: clamp to avoid spiral-of-death on hitches
    if (elapsed > NS_PER_SEC / 10) elapsed = NS_PER_SEC / 10;

    t->accumulator_ns += elapsed;

    long long period_ns = NS_PER_SEC / t->cycles_per_sec;
    int cycles = (int)(t->accumulator_ns / period_ns);
    t->accumulator_ns %= period_ns;
    return cycles;
}

// How many cycles to run between glances at the wall clock. In fast mode there is
// no clock to keep pace with, so run a large batch before looking up.
#define FAST_BATCH 65536

unsigned long cycleCount = 0;
char *programFile = NULL;

// Memory Banks:
uint8_t Program[0x10000], Data[0x10000];

int main (int argc, char *argv[]) {
    EmulatorOptions options;
    uint8_t result = parseOptions(argc, argv, &options);
    if (result == OPTIONS_HELP) {
        // The user asked for help and got it, which is not a failure.
        return 0;
    } else if (result == OPTIONS_ERROR) {
        // Bad command line, don't execute.
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
    if(options.debug) {
        printRegisters(&cpu, Program, Data);
    }

    CycleTimer timer;
    cycle_timer_init(&timer, CYCLE_RATE);

    uint8_t limitReached = 0;
    while (!(cpu.Status & STATUS_HALT) && !limitReached) {
        if (options.debug) {
            // Wait before advancing, not after, so that a keypress is what moves the
            // machine on rather than something that happens once it already has.
            getchar();
        }
        int cycles;
        if (options.debug) {
            // Debug mode advances one instruction per keypress, so the wall clock
            // has no say in how many cycles to run.
            cycles = 1;
        } else if (options.fast) {
            cycles = FAST_BATCH;
        } else {
            cycles = cycle_timer_tick(&timer);
        }
        for (int i = 0; i < cycles; i++) {
            stepCPU(&cpu);
            cycleCount++;
            if (cpu.Status & STATUS_HALT) {
                // We've halted.
                break;
            }
            if (options.cycles && cycleCount >= options.cycles) {
                limitReached = 1;
                break;
            }
        }
        if (options.debug) {
            printRegisters(&cpu, Program, Data);
            printf("Cycle: %lu\n", cycleCount);
        }
    }
    if (limitReached) {
        printf("Execution stopped after %lu cycles. (cycle limit reached)\n", cycleCount);
    } else if (cpu.Status & STATUS_FAULT) {
        // The Program Counter is still pointing at whatever the CPU could not get past.
        printf("Execution halted after %lu cycles.\n", cycleCount);
        if (cpu.Fault == FAULT_NO_HANDLER) {
            fprintf(stderr, "Fault: Software vector %u, dispatched from Program Address 0x%04X, has no handler installed.\n",
                    cpu.FaultVector, cpu.ProgramCounter);
        } else if (cpu.Fault == FAULT_NO_DEVICE_HANDLER) {
            fprintf(stderr, "Fault: The device on port %u interrupted at Program Address 0x%04X, and hardware vector %u has no handler installed.\n",
                    cpu.FaultVector, cpu.ProgramCounter, cpu.FaultVector);
        } else {
            fprintf(stderr, "Fault: 0x%02X at Program Address 0x%04X is not an instruction.\n",
                    Program[cpu.ProgramCounter], cpu.ProgramCounter);
        }
        return 1;
    } else {
        printf("Execution halted after %lu cycles.\n", cycleCount);
    }
    return 0;
}
