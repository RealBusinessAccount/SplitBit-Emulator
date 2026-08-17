// io.c
// I/O for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/16/2024

#include "io.h"
#include "../Assembler/assembly.h" // For the fault vector numbers.
#include "controller.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <termios.h>
#include <unistd.h>
#include <poll.h>

// ---- The console ----
//
// The console owns its own reading rather than going through getchar. stdio keeps a
// buffer, and the status port asks the operating system what is waiting; those two
// disagree the moment stdio has read ahead, and the status port would then swear nothing
// was there while a read returned instantly. One byte of pushback here is enough, because
// nothing needs to look further ahead than the byte it is about to take.

static int consoleKeyMode = 0;
static int consoleEnded = 0;
static int consolePushback = -1;          // A byte already taken from the host, or -1.
static struct termios consoleSavedTerminal;
static int consoleTerminalSaved = 0;

void consoleRestore(void) {
    if (consoleTerminalSaved) {
        tcsetattr(STDIN_FILENO, TCSANOW, &consoleSavedTerminal);
        consoleTerminalSaved = 0;
    }
    consoleKeyMode = 0;
}

// Restores the terminal and then dies the way it would have died anyway, so that the
// shell sees the signal it was expecting rather than a machine that exited quietly.
static void consoleSignalHandler(int signalNumber) {
    consoleRestore();
    signal(signalNumber, SIG_DFL);
    raise(signalNumber);
}

static void consoleSetMode(uint8_t mode) {
    int wantKeys = (mode & CONSOLE_MODE_KEY) != 0;
    if (wantKeys == consoleKeyMode) {
        return;
    }
    if (!wantKeys) {
        consoleRestore();
        return;
    }
    // Nothing to configure when input is not a terminal, but the mode is still recorded:
    // a program asking the status port what mode it is in should be told what it asked
    // for, whether or not there was a terminal to carry it out on.
    consoleKeyMode = 1;
    if (!isatty(STDIN_FILENO)) {
        return;
    }
    if (!consoleTerminalSaved) {
        if (tcgetattr(STDIN_FILENO, &consoleSavedTerminal) != 0) {
            return;
        }
        consoleTerminalSaved = 1;
        // Registered on the first use rather than at startup, so a run that never asks
        // for key mode installs nothing at all.
        atexit(consoleRestore);
        signal(SIGINT, consoleSignalHandler);
        signal(SIGTERM, consoleSignalHandler);
    }
    struct termios raw = consoleSavedTerminal;
    raw.c_lflag &= (tcflag_t)~(ICANON | ECHO);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);
}

// Everything already written is put where it can be seen before the machine asks the host
// anything. Standard output is line buffered on a terminal, so a prompt with no newline
// after it - "> " is exactly that, and exactly why this matters - would sit in the buffer
// while the machine waited for an answer to a question nobody had been shown.
//
// getchar used to do this by accident, because reading through stdio flushes the line
// buffered streams first. Reading with read() does not, so what was a side effect of the
// old way is done deliberately here.
static void consoleShowWhatIsWritten(void) {
    fflush(stdout);
}

uint8_t consoleReadByte(void) {
    if (consolePushback >= 0) {
        uint8_t byte = (uint8_t)consolePushback;
        consolePushback = -1;
        return byte;
    }
    consoleShowWhatIsWritten();
    unsigned char byte;
    for (;;) {
        ssize_t got = read(STDIN_FILENO, &byte, 1);
        if (got == 1) {
            return byte;
        }
        if (got == 0) {
            // End of input. Still 0xFF, which is what getchar's EOF became when this was
            // the only answer available, so nothing written against the old behaviour
            // changes. The ENDED bit is the new way to know it was not a real byte.
            consoleEnded = 1;
            return 0xFF;
        }
        if (errno != EINTR) {
            consoleEnded = 1;
            return 0xFF;
        }
        // Interrupted before anything arrived, so ask again.
    }
}

// Asking the host whether anything is waiting, and TAKING IT IF THERE IS. The byte goes
// into the pushback and the next read of the data port hands it over, so nothing is lost
// and no program can tell that it was fetched early.
//
// Fetching it early is what makes the answer worth having. The operating system will say a
// pipe is readable when what is waiting is the end of it, so asking without reading can
// only report that SOMETHING is there. Reading settles which: a byte, or the end. Without
// this, ENDED could not go up until a program had already read the 0xFF that stands for
// it, and every program would have to swallow one imaginary byte to find out there were
// none.
static void consoleFetch(void) {
    if (consolePushback >= 0 || consoleEnded) {
        return;
    }
    // Flushed here too. A program that draws something and then polls rather than reads is
    // just as entitled to have the drawing appear, and it never reaches the read that
    // would otherwise have flushed for it.
    consoleShowWhatIsWritten();
    struct pollfd waiting = { .fd = STDIN_FILENO, .events = POLLIN, .revents = 0 };
    if (poll(&waiting, 1, 0) <= 0 || (waiting.revents & (POLLIN | POLLHUP)) == 0) {
        return;
    }
    unsigned char byte;
    ssize_t got = read(STDIN_FILENO, &byte, 1);
    if (got == 1) {
        consolePushback = byte;
    } else if (got == 0) {
        consoleEnded = 1;
    }
    // A read that failed for any other reason is left alone: the next attempt asks again,
    // and an interrupted poll is not news.
}

static uint8_t consoleStatus(void) {
    uint8_t status = consoleKeyMode ? CONSOLE_STATUS_KEYMODE : 0;
    consoleFetch();
    if (consoleEnded) {
        // READY IS NOT SET HERE, although a read would answer immediately. The bit means
        // "there is a byte to be had", and at the end of input there is not; what a read
        // returns then is 0xFF standing in for nothing. A program looping while READY
        // stops on its own at the end, which is the behaviour worth having, and one that
        // wants to know why asks ENDED.
        return status | CONSOLE_STATUS_ENDED;
    }
    if (consolePushback >= 0) {
        status |= CONSOLE_STATUS_READY;
    }
    return status;
}

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

// ---- The disk ----
//
// A block device and nothing more. It knows numbered blocks and has never heard of a
// file, which is the whole point: a filesystem is software this machine will run, not
// something the host does on its behalf. A disk that understood filenames would be the
// emulator doing the work and the machine pretending it had.

static FILE *diskImage = NULL;
static uint32_t diskBlockCount = 0;
static uint8_t diskBuffer[DISK_BLOCK_BYTES];
static uint16_t diskBlock = 0;
static uint8_t diskStatus = 0;
static uint8_t diskProtected = 0;

uint8_t attachDisk(const char *path, uint8_t writeProtect) {
    diskProtected = writeProtect ? 1 : 0;
    diskImage = fopen(path, "r+b");
    if (diskImage == NULL) {
        // It may be there and simply not writable, which is a read only disk rather than
        // a missing one. Try that before deciding to make a new one.
        diskImage = fopen(path, "rb");
        if (diskImage != NULL) {
            diskProtected = 1;
        }
    }
    if (diskImage == NULL) {
        // Nothing there, so make one. A fresh image is zeroes, which is what an unwritten
        // block should read as.
        diskImage = fopen(path, "w+b");
        if (diskImage == NULL) {
            fprintf(stderr, "Error: Couldn't open or create the disk image: %s\n", path);
            return 1;
        }
        static const uint8_t empty[DISK_BLOCK_BYTES] = {0};
        for (uint32_t i = 0; i < DISK_DEFAULT_BLOCKS; i++) {
            if (fwrite(empty, 1, DISK_BLOCK_BYTES, diskImage) != DISK_BLOCK_BYTES) {
                fprintf(stderr, "Error: Couldn't write the disk image: %s\n", path);
                fclose(diskImage);
                diskImage = NULL;
                return 1;
            }
        }
    }
    if (fseek(diskImage, 0, SEEK_END) != 0) {
        fprintf(stderr, "Error: Couldn't measure the disk image: %s\n", path);
        fclose(diskImage);
        diskImage = NULL;
        return 1;
    }
    long size = ftell(diskImage);
    // A part written block at the end is not a block, so it is not counted.
    diskBlockCount = (size > 0) ? (uint32_t)(size / DISK_BLOCK_BYTES) : 0;
    // The protect bit is a standing property, so it reads true before anything has been
    // asked of the disk rather than only after a write has been turned away.
    diskStatus = diskProtected ? DISK_STATUS_PROTECTED : 0;
    return 0;
}

void detachDisk(void) {
    if (diskImage != NULL) {
        fclose(diskImage);
        diskImage = NULL;
    }
}

// Reads or writes the block the block registers name. The line goes up either way: the
// operation finished, and whether it worked is what Status is for.
static void diskCommand(uint8_t command) {
    // The protect bit describes the disk rather than the operation, so it survives.
    diskStatus = diskProtected ? DISK_STATUS_PROTECTED : 0;
    if (command == DISK_COMMAND_WRITE && diskProtected) {
        diskStatus |= DISK_STATUS_ERROR;
        raiseInterrupt(PORT_DISK);
        return;
    }
    if (diskImage == NULL || diskBlock >= diskBlockCount) {
        diskStatus |= DISK_STATUS_ERROR;
        raiseInterrupt(PORT_DISK);
        return;
    }
    long offset = (long)diskBlock * DISK_BLOCK_BYTES;
    if (fseek(diskImage, offset, SEEK_SET) != 0) {
        diskStatus |= DISK_STATUS_ERROR;
        raiseInterrupt(PORT_DISK);
        return;
    }
    size_t moved = 0;
    if (command == DISK_COMMAND_READ) {
        moved = fread(diskBuffer, 1, DISK_BLOCK_BYTES, diskImage);
    } else if (command == DISK_COMMAND_WRITE) {
        moved = fwrite(diskBuffer, 1, DISK_BLOCK_BYTES, diskImage);
        fflush(diskImage);
    } else {
        diskStatus |= DISK_STATUS_ERROR;
        raiseInterrupt(PORT_DISK);
        return;
    }
    if (moved != DISK_BLOCK_BYTES) {
        diskStatus |= DISK_STATUS_ERROR;
    }
    raiseInterrupt(PORT_DISK);
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
    if (port == PORT_MEMORY) {
        *capacity = DEVICE_MEMORY_BYTES;
        return deviceMemoryBlock;
    }
    if (port == PORT_DISK) {
        // The disk's buffer is one block. Reading fills it and writing takes what is in
        // it, and the only way to reach it is to register it as a bank and go through the
        // controller.
        *capacity = DISK_BLOCK_BYTES;
        return diskBuffer;
    }
    return NULL;
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
    { PORT_DISK,     DEVICE_DISK,     DEVICE_FLAG_HAS_MEMORY },
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
    if (port > PORT_CONSOLE && port <= PORT_CONSOLE_TOP) {
        // The status and control ports are the same device as the data port, which is the
        // one in the table and the one that would raise a line if the console ever did.
        return deviceOnPort(PORT_CONSOLE);
    }
    if (port > PORT_DISK && port <= PORT_DISK_TOP) {
        // The base port is in the table proper, since that is the one that owns the
        // memory and raises the line. The rest of the block reports the same device.
        return deviceOnPort(PORT_DISK);
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
        case CONSOLE_DATA:
            // If data is sent here, it should be written to STDOUT.
            // For now, I'll implement this so it simply writes each byte out as it comes in.
            // Later, I'll want to use a buffer for this for performance, probably.
            putchar(DataByte);
        break;
        case CONSOLE_CONTROL: consoleSetMode(DataByte); break;
        case CONSOLE_STATUS:
            // Read only. A device saying how it is does not take instructions through the
            // same hole, so a write here is ignored rather than meaning something.
        break;
        case DISK_BLOCK_HIGH: diskBlock = (uint16_t)(DataByte << 8) | (diskBlock & 0x00FF); break;
        case DISK_BLOCK_LOW:  diskBlock = (diskBlock & 0xFF00) | DataByte; break;
        case DISK_COMMAND:    diskCommand(DataByte); break;
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
        case CONSOLE_DATA:
            // If data is sent here, it should be read from STDIN.
            return consoleReadByte();
        break;
        case CONSOLE_STATUS: return consoleStatus();
        case CONSOLE_CONTROL:
            // Write only. Reading it gives zero rather than the mode, because the mode is
            // a bit in the status port and one fact wants one place to live.
            return 0;
        break;
        case DISK_BLOCK_HIGH: return (uint8_t)(diskBlock >> 8);
        case DISK_BLOCK_LOW:  return (uint8_t)(diskBlock & 0xFF);
        case DISK_STATUS:     return diskStatus;
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
