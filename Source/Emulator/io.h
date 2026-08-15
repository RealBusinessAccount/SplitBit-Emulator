// io.h
// I/O for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/16/2024

#ifndef IO_H
#define IO_H

#include <stdint.h>
#include "cpu.h"

uint8_t OutputHandler(uint8_t DataByte, uint8_t Address);

uint8_t InputHandler(uint8_t Address);

// ---- Interrupt lines ----
//
// One line per port. A device puts its line up to ask for attention, and the CPU takes
// it down when it answers. Which line a device uses is not a choice: a device on port N
// interrupts on N, which is what saves the machine from needing any arbitration.
//
// These belong to the bus rather than to the CPU. Nothing here is saved in a frame, and
// a program cannot read them except by being interrupted.

void raiseInterrupt(uint8_t port);

void clearInterrupt(uint8_t port);

// The lowest numbered port with its line up, or -1 if none of them are.
int nextPendingInterrupt(void);

#endif // IO_H
