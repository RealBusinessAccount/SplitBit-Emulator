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
#define PORT_REFUSE   0x11
#define PORT_MEMORY   0x12

// The disk answers on a block of four ports and interrupts on the first of them. A device
// that spans more than one port raises its line on its base, which is the rule the
// machine has not needed until now: the controller spans sixteen and never interrupts.
#define PORT_DISK        0x20
#define PORT_DISK_TOP    0x23
#define DISK_BLOCK_HIGH  0x20
#define DISK_BLOCK_LOW   0x21
#define DISK_COMMAND     0x22
#define DISK_STATUS      0x23
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
#define DEVICE_CONTROLLER 0x03
#define DEVICE_TEST     0x10
#define DEVICE_REFUSE   0x11
#define DEVICE_MEMORY   0x12
#define DEVICE_DISK     0x13

// What a device brings besides itself. This means memory that somebody has to register
// with the controller, so the controller's own bank 2 does not count: it is already there.
#define DEVICE_FLAG_HAS_MEMORY 0x01

// ---- The disk ----
//
// Blocks are a page each, so a block number is the whole of a 16 bit address and the
// arithmetic never needs a multiply. Sixteen megabytes is absurd for this machine, which
// is the point: there is room for anything a filesystem might want to grow into later.

#define DISK_BLOCK_BYTES 256

// A fresh image is made the size of Program and Data together, which is a round number
// for this machine and small enough to read in a hex editor while it is being built.
#define DISK_DEFAULT_BLOCKS 512

#define DISK_COMMAND_READ  0x01
#define DISK_COMMAND_WRITE 0x02

// Set while an operation is still going. It always reads clear here, because the host
// finishes before the next instruction does, but a machine with a slower disk would set
// it and a program that ignores it would break there. Honour it anyway.
#define DISK_STATUS_BUSY  0x01
// Set when the disk cannot be written at all. Unlike the two bits above it, this is not
// about the last operation: it is a standing property of the medium, readable before
// anything is attempted. A write protected disk is barred here, in the device, rather
// than by anything in the filesystem, so writing blocks directly cannot get around it.
#define DISK_STATUS_PROTECTED 0x04

// Set when the last operation did not work: no image, or a block that is not on it.
// A disk that cannot read a block is an ordinary thing that happens to working programs,
// so it says so rather than stopping the machine.
#define DISK_STATUS_ERROR 0x02

// Attaches an image, making one if it is not there. A disk is read only if the host will
// not let the file be written, or if writeProtect asks for it, which is the emulated
// equivalent of the tab on the side of a floppy. Returns 1 if it could not attach.
uint8_t attachDisk(const char *path, uint8_t writeProtect);

void detachDisk(void);

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

// ---- Refusing ----
//
// A device can refuse what it was asked to do. Interrupting is a device asking for
// attention later; refusing is a device saying no to the instruction happening now, so
// it has to stop the machine where it stands rather than raise a line and let execution
// carry on past the mistake.
//
// The refusal names a software vector, so the cause is known from the entry it arrives
// through, the same way every other fault on this machine works.

void refuseAccess(uint8_t faultVector);

// ---- Memory a device brings ----
//
// Returns the memory owned by the device on this port, or NULL if it owns none, and
// fills in how much of it there is. This is how the controller finds out what a device
// brings when it is told to register a bank.
//
// It is a direct look at the machine's device table rather than a conversation through
// the registry's port. The port protocol remembers which port it was asked about, so a
// controller that used it would silently lose the place of any enumeration a program had
// in progress. Same table, two consumers, and only one of them needs the protocol.
uint8_t *deviceMemory(uint8_t port, uint32_t *capacity);

// The vector a device refused with, or 0 if none did. Reading it clears it, because a
// refusal is answered once.
uint8_t takeRefusal(void);

// Which port did the refusing. Only meaningful alongside a refusal.
uint8_t refusingPort(void);

#endif // IO_H
