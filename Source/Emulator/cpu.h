// cpu.h
// SplitBit CPU Emulator Core
// Written by Anachronaut
// 10/16/2024

#ifndef CPU_H
#define CPU_H

#include <stdint.h>

// How many Data Pointers the CPU has. The instructions that name one take a full
// byte to do it, so the encoding would allow up to 256. The limit here is the size
// of the register file and the cost of saving pointers across a CALL, not the
// instruction format. Must be a power of two, so that the selector can be masked
// down to a valid pointer.
#define DATA_POINTERS 4

// How many Data Pointers survive a CALL. The low numbered pointers are saved and
// restored around a subroutine; the rest are left alone, so a subroutine can use
// one to hand a pointer back to its caller the way Q hands back a byte. This is
// deliberately independent of DATA_POINTERS: adding more pointers should not make
// every CALL more expensive.
#define PRESERVED_DATA_POINTERS 3

#if PRESERVED_DATA_POINTERS > DATA_POINTERS
#error "Cannot preserve more Data Pointers than the CPU has."
#endif

// The struct containing the CPU registers.
typedef struct {
    uint8_t A;
    uint8_t B;
    uint8_t Q;
    uint8_t Status;
    uint16_t ProgramCounter;
    uint16_t DataPointer[DATA_POINTERS];
    uint16_t StackPointer;
    uint8_t *Program;
    uint8_t *Data;
} CPURegisters;

uint8_t executeOperation(uint8_t instruction, CPURegisters *cpu);

void initializeCPU(CPURegisters *cpu, uint8_t *programMemory, uint8_t *dataMemory);

void stepCPU(CPURegisters *cpu);

#endif // CPU_H
