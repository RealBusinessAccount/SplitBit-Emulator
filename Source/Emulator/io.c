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

// ---- The bus registry ----
//
// What is plugged into this machine. The table is fixed when the machine is built: a
// program cannot write to it, because writing would only let a program lie to itself
// about what hardware exists. Which routine handles a device is a different question,
// and the vector table already answers it.
//
// Nothing here touches the device being asked about. That matters more than it looks:
// reading a port is a real operation, and asking the console what it is by reading it
// would take a character off standard input and block waiting for one.

typedef struct {
    uint8_t port;
    uint8_t deviceClass;
    uint8_t flags;
} DeviceRecord;

static const DeviceRecord deviceTable[] = {
    { PORT_CONSOLE,  DEVICE_CONSOLE,  0 },
    { PORT_TEST,     DEVICE_TEST,     0 },
    { PORT_REGISTRY, DEVICE_REGISTRY, 0 },
};
static const int deviceCount = (int)(sizeof(deviceTable) / sizeof(deviceTable[0]));

// Which port the registry is currently being asked about, and how far through that
// port's record it has been read. Selecting a port starts the record again.
static uint8_t registrySelected = 0;
static uint8_t registryCursor = 0;

static const DeviceRecord *deviceOnPort(uint8_t port) {
    for (int i = 0; i < deviceCount; i++) {
        if (deviceTable[i].port == port) {
            return &deviceTable[i];
        }
    }
    return NULL;
}

// One byte of the selected port's record. Everything about a port that is not there
// reads as zero, which is the same answer an absent registry would give.
static uint8_t readRegistry(void) {
    const DeviceRecord *device = deviceOnPort(registrySelected);
    uint8_t answer = 0;
    if (device != NULL && registryCursor < DEVICE_RECORD_BYTES) {
        answer = (registryCursor == 0) ? device->deviceClass : device->flags;
    }
    if (registryCursor < DEVICE_RECORD_BYTES) {
        registryCursor++;
    }
    return answer;
}

uint8_t OutputHandler(uint8_t DataByte, uint8_t Address) {
    // This function sends the DataByte to the appropriate place based on the Port Address.
    switch(Address) {
        case PORT_CONSOLE:
            // If data is sent here, it should be written to STDOUT.
            // For now, I'll implement this so it simply writes each byte out as it comes in.
            // Later, I'll want to use a buffer for this for performance, probably.
            putchar(DataByte);
        break;
        case PORT_REGISTRY:
            // Names the port the registry is being asked about. This is the only thing
            // that can be written to the registry, and it changes nothing about the
            // machine: it selects a question, it does not give an answer.
            registrySelected = DataByte;
            registryCursor = 0;
        break;
        case PORT_TEST:
            // A test device, and about the simplest one that can exist: writing to it
            // puts its own line up. It stands in for the shape a real device has, where
            // the CPU asks for something and is interrupted once the answer is ready,
            // with the waiting taken out so that a test runs the same way every time.
            // The byte written is ignored; only the asking matters.
            raiseInterrupt(PORT_TEST);
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
        case PORT_CONSOLE:
            // If data is sent here, it should be read from STDIN.
            return getchar();
        break;
        case PORT_REGISTRY:
            // One byte of the selected port's record, then the next, and zero once the
            // record has run out.
            return readRegistry();
        break;
        default:
            // Reading from an unused port is ignored.
            return 0;
        break;
    }
}
