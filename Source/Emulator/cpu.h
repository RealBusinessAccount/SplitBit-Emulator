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

// The bits of the Status register that mean something.
#define STATUS_CARRY     0x01 // An arithmetic result carried out of, or borrowed into, a byte.
#define STATUS_FAULT     0x02 // The CPU met a byte it could not decode, and stopped.
#define STATUS_INTERRUPT 0x04 // Hardware interrupts are enabled. Nothing reads this yet.
#define STATUS_HALT      0x80 // Execution has stopped, either from HALT or from a fault.

// What an interrupt puts on the Stack: the resume address, every Data Pointer, and
// every register the CPU has. The CALL frame leaves Q and DP3 alone, but that is a
// convention between a caller and the subroutine it called. An interrupt arrives in
// code that never agreed to give anything up, so it saves the lot.
#define INTERRUPT_FRAME_BYTES (2 + DATA_POINTERS * 2 + 4)

// Why the CPU stopped, when the Fault Flag is set. This is not something a program can
// read, and it is deliberately not a register: when a handler is installed, the vector
// it arrived through already says what happened, which is why the ISA has no fault
// cause. This exists for the case where nothing is installed and the machine is dead,
// so that whatever examines the wreckage can say something better than "it stopped".
typedef enum {
    FAULT_NONE = 0,
    FAULT_BAD_OPCODE,  // A byte that does not decode to an instruction.
    FAULT_NO_HANDLER,  // Dispatched through a software vector with nothing in it.
    FAULT_NO_DEVICE_HANDLER, // A device interrupted, and its vector was empty.
    FAULT_DEVICE_REFUSED     // A device refused, and nothing was installed to catch it.
} FaultCause;

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
    // Set alongside the Fault Flag, and read only by whatever reports the stop.
    uint8_t Fault;        // A FaultCause.
    uint8_t FaultVector;  // Which vector was empty, when Fault is FAULT_NO_HANDLER.
} CPURegisters;

uint8_t executeOperation(uint8_t instruction, CPURegisters *cpu);

void initializeCPU(CPURegisters *cpu, uint8_t *programMemory, uint8_t *dataMemory);

void stepCPU(CPURegisters *cpu);

#endif // CPU_H
