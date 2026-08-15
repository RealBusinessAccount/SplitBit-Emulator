// io.c
// I/O for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/16/2024

#include "io.h"
#include <stdio.h>

// One bit per port, so a device can ask for attention without anything having to poll
// it. Eight ports to the byte, low bit first.
#define INTERRUPT_LINE_BYTES 32

static uint8_t pendingInterrupts[INTERRUPT_LINE_BYTES];

void raiseInterrupt(uint8_t port) {
    pendingInterrupts[port >> 3] |= (uint8_t)(1u << (port & 7));
}

void clearInterrupt(uint8_t port) {
    pendingInterrupts[port >> 3] &= (uint8_t)~(1u << (port & 7));
}

int nextPendingInterrupt(void) {
    // Lowest numbered port wins. This is a scan rather than a priority encoder, which
    // means there is no arbitration to explain and a programmer can work out what
    // happens next by reading the port numbers.
    for (int group = 0; group < INTERRUPT_LINE_BYTES; group++) {
        if (pendingInterrupts[group] == 0) {
            continue;
        }
        for (int bit = 0; bit < 8; bit++) {
            if (pendingInterrupts[group] & (1u << bit)) {
                return group * 8 + bit;
            }
        }
    }
    return -1;
}

uint8_t OutputHandler(uint8_t DataByte, uint8_t Address) {
    // This function sends the DataByte to the appropriate place based on the Port Address.
    switch(Address) {
        case 0x00:
            // If data is sent here, it should be written to STDOUT.
            // For now, I'll implement this so it simply writes each byte out as it comes in.
            // Later, I'll want to use a buffer for this for performance, probably.
            putchar(DataByte);
        break;
        case 0x10:
            // A test device, and about the simplest one that can exist: writing to it
            // puts its own line up. It stands in for the shape a real device has, where
            // the CPU asks for something and is interrupted once the answer is ready,
            // with the waiting taken out so that a test runs the same way every time.
            // The byte written is ignored; only the asking matters.
            raiseInterrupt(0x10);
        break;
        default:
            // Writes to unused Output Ports are ignored.
            return 1;
        break;
    }
    return 0;
}

uint8_t InputHandler(uint8_t Address) {
    switch(Address) {
        case 0x00:
            // If data is sent here, it should be read from STDIN.
            return getchar();
        break;
        default:
            // Reading from an unused port is ignored.
            return 0;
        break;
    }
}
