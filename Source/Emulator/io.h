// io.h
// I/O for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/16/2024

#ifndef IO_H
#define IO_H

#include <stdint.h>
#include "cpu.h"

// ---- Ports ----
//
// Which port a device answers on is a property of the machine rather than of any
// program, so the numbers live here and everything else refers to them by name.

#define PORT_CONSOLE  0x00
#define PORT_TEST     0x10
#define PORT_REGISTRY 0xFF

// ---- Device classes ----
//
// What kind of thing is plugged into a port. Class 0 is not a device: reading an
// unimplemented port already gives zero, so "nothing there" needs no special case and a
// machine with no registry at all answers correctly by doing nothing.
//
// Classes 0x01 to 0x0F belong to the machine itself. Peripherals start at 0x10.

#define DEVICE_NONE     0x00
#define DEVICE_REGISTRY 0x01
#define DEVICE_CONSOLE  0x02
#define DEVICE_TEST     0x10

// What a device brings besides itself. The memory controller will want the first of
// these to find out which ports own memory it can reach.
#define DEVICE_FLAG_HAS_MEMORY 0x01

// How many bytes a device's entry in the registry runs to. Reading past the end gives
// zero, so the record can grow later without anything already written having to change.
#define DEVICE_RECORD_BYTES 2

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
