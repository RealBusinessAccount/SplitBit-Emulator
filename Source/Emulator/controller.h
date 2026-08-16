// controller.h
// The SplitBit Memory Controller.
// Written by Anachronaut

#ifndef CONTROLLER_H
#define CONTROLLER_H

#include <stdint.h>

// ---- Ports ----
//
// Sixteen registers, one to a port, written and read directly. A register file behind a
// single port would be smaller but stateful, and losing your place in a device that
// moves memory corrupts memory rather than an answer.

#define CONTROLLER_PORT_BASE 0xE0
#define CONTROLLER_PORT_TOP  0xEF

#define CTRL_SOURCE_BANK     0xE0
#define CTRL_SOURCE_HIGH     0xE1
#define CTRL_SOURCE_LOW      0xE2
#define CTRL_DEST_BANK       0xE3
#define CTRL_DEST_HIGH       0xE4
#define CTRL_DEST_LOW        0xE5
#define CTRL_LENGTH_HIGH     0xE6
#define CTRL_LENGTH_LOW      0xE7
#define CTRL_COMMAND         0xE8
#define CTRL_DATA            0xE9
#define CTRL_STATUS          0xEA
#define CTRL_GUARD_BANK      0xEB
#define CTRL_GUARD_START_HIGH 0xEC
#define CTRL_GUARD_START_LOW  0xED
#define CTRL_GUARD_END_HIGH   0xEE
#define CTRL_GUARD_END_LOW    0xEF

// ---- Commands ----
//
// Written to the Command port, which performs them at once. A blit is instantaneous from
// the CPU's point of view: waiting belongs to the peripheral that has something to wait
// for, not to the moving of bytes.

#define COMMAND_BLIT 0x01
#define COMMAND_FILL 0x02

// Gives a bank number to the memory owned by a device. How big it is comes from the
// device, not from software: a program asserting a hardware fact could only ever be
// wrong about it.
#define COMMAND_REGISTER_BANK 0x03

// Raises and lowers the fence over the bank named by GuardBank. Any program may do
// either: this is a fence rather than a wall, and nobody is ever told no. What it stops
// is walking into something by accident, not walking into it on purpose.
#define COMMAND_GUARD_ON  0x10
#define COMMAND_GUARD_OFF 0x11

// ---- Banks ----
//
// Program and Data are banks like any other; being banks 0 and 1 is the only thing
// special about them. Bank 2 is the controller's own memory, and the bank table lives
// in it, which is how anything finds out what banks exist without a second protocol.

#define BANK_PROGRAM 0
#define BANK_DATA    1
#define BANK_TABLE   2
#define BANK_COUNT   256

// Eight bytes each, so bank n's record begins at n * 8.
//
//   0      Flags
//   1      The port that owns it, or the machine itself for banks 0 to 2
//   2 - 3  Capacity, where zero means the whole 64K
//   4 - 5  First guarded address
//   6 - 7  Last guarded address
//
// What is published is a description. The pointer a bank really holds is never in here:
// a program that could write one would be setting a host address, which means nothing on
// hardware and everything to the emulator running it.
#define BANK_RECORD_BYTES 8
#define BANK_TABLE_BYTES  (BANK_COUNT * BANK_RECORD_BYTES)

#define BANK_FLAG_PRESENT   0x01
#define BANK_FLAG_READ_ONLY 0x02
#define BANK_FLAG_GUARDED   0x04

// Banks 0 to 2 belong to the machine rather than to any device.
#define BANK_OWNER_MACHINE 0xFF

void initializeController(uint8_t *programMemory, uint8_t *dataMemory);

uint8_t controllerWrite(uint8_t value, uint8_t port);

uint8_t controllerRead(uint8_t port);

#endif // CONTROLLER_H
