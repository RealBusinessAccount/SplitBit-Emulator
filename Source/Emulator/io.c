// io.c
// I/O for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/16/2024

#include "io.h"
#include "../Assembler/assembly.h" // For the fault vector numbers.
#include "controller.h"
#include <stdio.h>
#include <string.h>

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

// ---- Refusing ----
//
// Set when a device will not do what it was asked, and read by the CPU immediately
// after the instruction that asked. It is not a queue: an instruction does one thing to
// one port, so there is only ever one refusal outstanding.

static uint8_t refusedVector = 0;
static uint8_t refusedPort = 0;

void refuseAccess(uint8_t faultVector) {
    refusedVector = faultVector;
}

uint8_t takeRefusal(void) {
    uint8_t vector = refusedVector;
    refusedVector = 0;
    return vector;
}

uint8_t refusingPort(void) {
    return refusedPort;
}

// ---- A device that brings memory ----
//
// The simplest thing that owns a bank. Writing to its port fills its memory with the
// byte written, which stands in for a disk controller reading a sector: the CPU asks for
// something and the memory it owns then holds the answer. The waiting is taken out so a
// test runs the same way every time.

#define DEVICE_MEMORY_BYTES 256

static uint8_t deviceMemoryBlock[DEVICE_MEMORY_BYTES];

uint8_t *deviceMemory(uint8_t port, uint32_t *capacity) {
    if (port != PORT_MEMORY) {
        return NULL;
    }
    *capacity = DEVICE_MEMORY_BYTES;
    return deviceMemoryBlock;
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
    { PORT_REFUSE,   DEVICE_REFUSE,   0 },
    { PORT_MEMORY,   DEVICE_MEMORY,   DEVICE_FLAG_HAS_MEMORY },
    { PORT_REGISTRY, DEVICE_REGISTRY, 0 },
};
static const int deviceCount = (int)(sizeof(deviceTable) / sizeof(deviceTable[0]));

// Which port the registry is currently being asked about, and how far through that
// port's record it has been read. Selecting a port starts the record again.
static uint8_t registrySelected = 0;
static uint8_t registryCursor = 0;

static const DeviceRecord controllerRecord = { CONTROLLER_PORT_BASE, DEVICE_CONTROLLER, 0 };

static const DeviceRecord *deviceOnPort(uint8_t port) {
    // The controller answers on a block of ports rather than one, so every port in the
    // block reports it. Its own memory is bank 2, which is already registered, so it
    // does not set the flag that means "this brings memory somebody has to register".
    if (port >= CONTROLLER_PORT_BASE && port <= CONTROLLER_PORT_TOP) {
        return &controllerRecord;
    }
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
    // Whichever port is being talked to is the one that would be doing any refusing.
    refusedPort = Address;
    // The controller answers on a block of ports, which is a range rather than a list.
    if (Address >= CONTROLLER_PORT_BASE && Address <= CONTROLLER_PORT_TOP) {
        return controllerWrite(DataByte, Address);
    }
    // This function sends the DataByte to the appropriate place based on the Port Address.
    switch(Address) {
        case PORT_CONSOLE:
            // If data is sent here, it should be written to STDOUT.
            // For now, I'll implement this so it simply writes each byte out as it comes in.
            // Later, I'll want to use a buffer for this for performance, probably.
            putchar(DataByte);
        break;
        case PORT_MEMORY:
            // Fills the memory this device owns with the byte written. Nothing is
            // reachable from here: to get at it, register it as a bank and go through
            // the controller, which is the only thing that can reach a device's memory.
            memset(deviceMemoryBlock, DataByte, DEVICE_MEMORY_BYTES);
        break;
        case PORT_REFUSE:
            // A device that refuses everything. It exists so that a device's ability to
            // stop the CPU can be tested before anything depends on it, and so that the
            // path stays tested once the memory controller is the only real user.
            refuseAccess(VECTOR_GUARD_VIOLATION);
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
    refusedPort = Address;
    if (Address >= CONTROLLER_PORT_BASE && Address <= CONTROLLER_PORT_TOP) {
        return controllerRead(Address);
    }
    switch(Address) {
        case PORT_CONSOLE:
            // If data is sent here, it should be read from STDIN.
            return getchar();
        break;
        case PORT_REFUSE:
            // Refuses reads as well, so both directions are covered.
            refuseAccess(VECTOR_GUARD_VIOLATION);
            return 0;
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
