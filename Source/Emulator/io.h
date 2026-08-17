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

// The console answers on three ports. The data port is the machine's oldest promise and
// does not change: writing sends a byte, reading takes one and waits for it. The other two
// are additions, so a program written before they existed cannot notice them.
#define PORT_CONSOLE      0x00
#define PORT_CONSOLE_TOP  0x02
#define CONSOLE_DATA      0x00
#define CONSOLE_STATUS    0x01
#define CONSOLE_CONTROL   0x02

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

// ---- The console ----
//
// Two modes, chosen by the program through the control port. The console starts in LINE
// mode, which is what the machine has always done: the terminal holds what is typed until
// Return, and does the echoing and the backspacing on the way. Reading the data port waits
// for a whole line to be finished somewhere else and then hands it over a byte at a time.
//
// KEY mode turns that off. Keys arrive as they are pressed, and nothing echoes them, so a
// program that wants them seen has to send them back out itself. That is not a choice this
// machine is making; it is what asking the terminal to stop holding a line means, and the
// editing goes away with it. A program that wants keys is expected to want that.
//
// READING THE DATA PORT WAITS IN BOTH MODES. The status port is how a program declines to
// wait, and keeping that in one place means the data port means one thing everywhere. A
// read that sometimes blocked and sometimes did not, depending on state set somewhere
// else, is the kind of thing that works until it does not.
//
// KEY MODE ONLY REACHES THE TERMINAL when there is one. With input coming from a pipe
// there is nothing to put into another mode, and the status port answers by asking the
// operating system whether anything is waiting, which is true of a pipe with bytes in it.
//
// A PROGRAM THAT INTERRUPTS ON INPUT MUST NOT BLOCK ON THE DATA PORT. Reading it waits,
// and the machine executes no instructions while it is waiting, so nothing is serviced
// and the line the console is about to raise goes nowhere until the read it was meant to
// replace has already finished. Interrupting and blocking are two answers to the same
// question and a program wants one of them.

// The control port's bits, which are independent of one another. Writing zero asks for
// line mode with no interrupts, which is how the console starts and what a program that
// knows nothing of any of this leaves behind it.
#define CONSOLE_MODE_LINE 0x00
#define CONSOLE_MODE_KEY  0x01

// Asks the console to put its line up when a byte arrives, instead of the program having
// to come and look. It composes with the mode rather than depending on it: in line mode
// the terminal still holds what is typed until Return, and then a whole line's worth of
// bytes arrive at once, each raising the line in turn as the one before it is taken.
// That is not especially useful, but a control bit that quietly did nothing depending on
// another control bit would be worse than a burst of interrupts somebody asked for.
#define CONSOLE_CONTROL_INTERRUPT 0x02

// Set when there is a byte to be had. NOT set at the end of input, although a read would
// answer at once there: what it answers is 0xFF standing in for nothing, and calling that
// ready would make a loop that reads while READY spin on imaginary bytes forever. A loop
// like that now stops when the input does, which is what anybody writing one intends.
#define CONSOLE_STATUS_READY   0x01
// Set once input has run out for good. The data port still answers 0xFF, which is what it
// always did and what every program written before this expects, but 0xFF is also an
// ordinary byte and this bit is the only thing that can tell the difference.
#define CONSOLE_STATUS_ENDED   0x02
// Which mode the console is in, so that a program can put it back the way it found it
// rather than assuming it knows.
#define CONSOLE_STATUS_KEYMODE 0x04
// Whether the console is set to interrupt, for the same reason: everything a program can
// ask the console to be, it can also ask the console what it currently is.
#define CONSOLE_STATUS_INTERRUPT 0x08

// Puts the terminal back the way it was found. Registered with atexit and called from the
// signal handlers, because a machine that stops in key mode and does not undo it leaves
// the shell that started it unusable, which is a far worse failure than anything the
// program was doing.
void consoleRestore(void);

// One byte from the console, waiting if it has to. Everything that reads standard input
// goes through here: the emulator owns one byte of pushback, and stdio holding a buffer
// of its own behind that would make the status port lie about what is waiting.
uint8_t consoleReadByte(void);

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

// Gives every device a moment to notice something the machine did not ask it about.
// Nothing here runs alongside the CPU: a device that waits on the outside world - the
// console is the only one so far - is never going to see a keystroke unless something
// asks it to look, and the CPU calling this between instructions is that something.
//
// It is called on every step and gets out of the way immediately when there is nothing to
// do, because there usually is not. A device that wants attention rarely is a device that
// must cost nothing when it does not.
void serviceDevices(void);

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
