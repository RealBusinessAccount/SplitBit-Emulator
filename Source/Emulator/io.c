// io.c
// I/O for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/16/2024

#include "io.h"
#include <stdio.h>

uint8_t OutputHandler(uint8_t DataByte, uint8_t Address) {
    // This function sends the DataByte to the appropriate place based on the Port Address.
    switch(Address) {
        case 0x00:
            // If data is sent here, it should be written to STDOUT.
            // For now, I'll implement this so it simply writes each byte out as it comes in.
            // Later, I'll want to use a buffer for this for performance, probably.
            putchar(DataByte);
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
