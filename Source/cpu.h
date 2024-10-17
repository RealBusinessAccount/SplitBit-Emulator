// cpu.h
// SplitBit CPU Emulator Core
// Written by Anachronaut
// 10/16/2024

#ifndef CPU_H
#define CPU_H

#include <stdint.h>

// The struct containing the CPU registers.
typedef struct {
    uint8_t A;
    uint8_t B;
    uint8_t Q;
    uint8_t Status;
    uint16_t ProgramCounter;
    uint16_t DataPointer;
    uint16_t StackPointer;
    uint8_t *Program;
    uint8_t *Data;
} CPURegisters;

uint8_t executeOperation(uint8_t instruction, CPURegisters *cpu);

void initializeCPU(CPURegisters *cpu, uint8_t *programMemory, uint8_t *dataMemory);

#endif // CPU_H
