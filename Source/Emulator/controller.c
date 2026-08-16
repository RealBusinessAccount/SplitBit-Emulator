// controller.c
// The SplitBit Memory Controller.
//
// This is the only thing on the machine that can write Program Memory. That is the whole
// reason it exists: SplitBit is a Harvard machine and its instruction set cannot reach
// its own code, which is worth keeping true of the instructions. Routing it through a
// device instead makes writing code a capability, reached deliberately through a port,
// rather than something every instruction stream can do by accident.
//
// Written by Anachronaut

#include "controller.h"
#include "io.h"
#include "../Assembler/assembly.h" // For the fault vector numbers.
#include <string.h>

typedef struct {
    uint8_t *memory;    // Never published. See the note in controller.h.
    uint32_t capacity;  // In bytes. A full bank is 65536, which is why this is not 16 bit.
    uint8_t flags;
    uint8_t ownerPort;
    uint16_t guardStart;
    uint16_t guardEnd;
} Bank;

static Bank banks[BANK_COUNT];

// Bank 2's contents: the description of every bank, for anything that wants to read it.
static uint8_t bankTable[BANK_TABLE_BYTES];

// The registers, exactly as the ports name them.
static uint8_t sourceBank, destBank, guardBank;
static uint16_t sourceAddress, destAddress, length;
static uint16_t guardStart, guardEnd;
static uint8_t status;

// Writes a bank's description into the table that bank 2 publishes. Called whenever
// anything about a bank changes, so the published table and the real one cannot drift.
static void publishBank(int number) {
    uint8_t *record = bankTable + number * BANK_RECORD_BYTES;
    record[0] = banks[number].flags;
    record[1] = banks[number].ownerPort;
    // Zero means the whole 64K, the same convention Length uses, because a capacity of
    // nothing is never what anyone meant.
    record[2] = (uint8_t)((banks[number].capacity >> 8) & 0xFF);
    record[3] = (uint8_t)(banks[number].capacity & 0xFF);
    record[4] = (uint8_t)(banks[number].guardStart >> 8);
    record[5] = (uint8_t)(banks[number].guardStart & 0xFF);
    record[6] = (uint8_t)(banks[number].guardEnd >> 8);
    record[7] = (uint8_t)(banks[number].guardEnd & 0xFF);
}

static void defineBank(int number, uint8_t *memory, uint32_t capacity, uint8_t flags, uint8_t owner) {
    banks[number].memory = memory;
    banks[number].capacity = capacity;
    banks[number].flags = flags | BANK_FLAG_PRESENT;
    banks[number].ownerPort = owner;
    banks[number].guardStart = 0;
    banks[number].guardEnd = 0;
    publishBank(number);
}

void initializeController(uint8_t *programMemory, uint8_t *dataMemory) {
    memset(banks, 0, sizeof(banks));
    memset(bankTable, 0, sizeof(bankTable));
    for (int i = 0; i < BANK_COUNT; i++) {
        banks[i].ownerPort = BANK_OWNER_MACHINE;
        publishBank(i);
    }

    defineBank(BANK_PROGRAM, programMemory, 0x10000, 0, BANK_OWNER_MACHINE);
    defineBank(BANK_DATA, dataMemory, 0x10000, 0, BANK_OWNER_MACHINE);
    // The table describes itself, so a program that walks it finds bank 2 in there along
    // with everything else. It is read only, which is what keeps RegisterBank the only
    // way to change what the controller routes through.
    defineBank(BANK_TABLE, bankTable, BANK_TABLE_BYTES, BANK_FLAG_READ_ONLY, BANK_OWNER_MACHINE);

    sourceBank = destBank = guardBank = 0;
    sourceAddress = destAddress = length = 0;
    guardStart = guardEnd = 0;
    status = 0;
}

// Refuses, remembering why so that Status can be read afterwards.
static void refuse(uint8_t faultVector) {
    status = faultVector;
    refuseAccess(faultVector);
}

// Is this somewhere the controller can read? A bank has to be there, and the address has
// to be inside it.
static int canRead(uint8_t bank, uint16_t address) {
    if (!(banks[bank].flags & BANK_FLAG_PRESENT) || address >= banks[bank].capacity) {
        refuse(VECTOR_BANK_FAULT);
        return 0;
    }
    return 1;
}

// The same, and then the two reasons a write in particular gets turned away.
static int canWrite(uint8_t bank, uint16_t address) {
    if (!canRead(bank, address)) {
        return 0;
    }
    if (banks[bank].flags & BANK_FLAG_READ_ONLY) {
        refuse(VECTOR_GUARD_VIOLATION);
        return 0;
    }
    if ((banks[bank].flags & BANK_FLAG_GUARDED)
        && address >= banks[bank].guardStart && address <= banks[bank].guardEnd) {
        refuse(VECTOR_GUARD_VIOLATION);
        return 0;
    }
    return 1;
}

// A length of zero means the whole 64K, because a transfer of no bytes is never what
// anyone meant, and 65536 does not fit in the two bytes that carry it.
static uint32_t transferLength(void) {
    return (length == 0) ? 0x10000u : (uint32_t)length;
}

// Everything a transfer will touch is checked before any of it moves. A blit that ran
// out of bank halfway would leave memory in a state no program asked for, and the
// diagnostic would arrive after the damage rather than instead of it. So these answer
// for the whole range or refuse the whole thing.
static int rangeReadable(uint8_t bank, uint16_t address, uint32_t count) {
    if (!(banks[bank].flags & BANK_FLAG_PRESENT)
        || (uint32_t)address + count > banks[bank].capacity) {
        refuse(VECTOR_BANK_FAULT);
        return 0;
    }
    return 1;
}

static int rangeWritable(uint8_t bank, uint16_t address, uint32_t count) {
    if (!rangeReadable(bank, address, count)) {
        return 0;
    }
    if (banks[bank].flags & BANK_FLAG_READ_ONLY) {
        refuse(VECTOR_GUARD_VIOLATION);
        return 0;
    }
    if (banks[bank].flags & BANK_FLAG_GUARDED) {
        uint32_t last = (uint32_t)address + count - 1;
        // Any overlap at all with the fence, not just a write that starts inside it.
        if (!(last < banks[bank].guardStart || address > banks[bank].guardEnd)) {
            refuse(VECTOR_GUARD_VIOLATION);
            return 0;
        }
    }
    return 1;
}

static void doBlit(void) {
    uint32_t count = transferLength();
    if (!rangeReadable(sourceBank, sourceAddress, count)) {
        return;
    }
    if (!rangeWritable(destBank, destAddress, count)) {
        return;
    }
    // memmove rather than memcpy, because source and destination may be the same bank
    // and may overlap. Sliding a buffer along itself is an ordinary thing to want, and
    // getting it silently wrong is exactly the sort of failure this machine keeps
    // designing against.
    memmove(banks[destBank].memory + destAddress,
            banks[sourceBank].memory + sourceAddress, count);
    sourceAddress = (uint16_t)(sourceAddress + count);
    destAddress = (uint16_t)(destAddress + count);
    status = 0;
}

static void doFill(void) {
    uint32_t count = transferLength();
    if (!rangeWritable(destBank, destAddress, count)) {
        return;
    }
    // A fill has nowhere to read from, only a value, so SourceLow carries the byte and
    // the rest of the source registers mean nothing here.
    memset(banks[destBank].memory + destAddress, (int)(sourceAddress & 0xFF), count);
    destAddress = (uint16_t)(destAddress + count);
    status = 0;
}

// DestBank is the number being given out, and SourceLow says which port owns the memory.
// The capacity is asked of the device rather than supplied, because how big a bank is
// was settled when the machine was built.
static void doRegisterBank(void) {
    if (destBank <= BANK_TABLE) {
        // Banks 0 to 2 are the machine's own and are not anybody's to hand out.
        refuse(VECTOR_BANK_FAULT);
        return;
    }
    uint8_t port = (uint8_t)(sourceAddress & 0xFF);
    uint32_t capacity = 0;
    uint8_t *memory = deviceMemory(port, &capacity);
    if (memory == NULL) {
        // Either nothing is on that port or what is there brings no memory. Registering
        // it would put a bank in the table that leads nowhere.
        refuse(VECTOR_BANK_FAULT);
        return;
    }
    // Registering over a bank that already has something in it is allowed. Which number
    // a device's memory answers to is the OS's business, and nothing was allocated that
    // could be lost by changing its mind.
    defineBank(destBank, memory, capacity, 0, port);
    status = 0;
}

// The guard registers stage a range; this is what commits it. Raising a fence over a
// bank that is not there would protect nothing while looking like it protected
// something, so it is refused rather than quietly accepted.
static void doGuardOn(void) {
    if (!(banks[guardBank].flags & BANK_FLAG_PRESENT)) {
        refuse(VECTOR_BANK_FAULT);
        return;
    }
    if (guardStart > guardEnd) {
        // No address can be inside a range that ends before it starts, so this fence
        // would catch nothing. A program that raised one would believe it was protected
        // and would not be, which is worse than having no fence at all.
        refuse(VECTOR_BANK_FAULT);
        return;
    }
    banks[guardBank].guardStart = guardStart;
    banks[guardBank].guardEnd = guardEnd;
    banks[guardBank].flags |= BANK_FLAG_GUARDED;
    publishBank(guardBank);
    status = 0;
}

static void doGuardOff(void) {
    if (!(banks[guardBank].flags & BANK_FLAG_PRESENT)) {
        refuse(VECTOR_BANK_FAULT);
        return;
    }
    banks[guardBank].flags &= (uint8_t)~BANK_FLAG_GUARDED;
    publishBank(guardBank);
    status = 0;
}

uint8_t controllerWrite(uint8_t value, uint8_t port) {
    switch (port) {
        case CTRL_SOURCE_BANK: sourceBank = value; break;
        case CTRL_SOURCE_HIGH: sourceAddress = (uint16_t)(value << 8) | (sourceAddress & 0x00FF); break;
        case CTRL_SOURCE_LOW:  sourceAddress = (sourceAddress & 0xFF00) | value; break;
        case CTRL_DEST_BANK:   destBank = value; break;
        case CTRL_DEST_HIGH:   destAddress = (uint16_t)(value << 8) | (destAddress & 0x00FF); break;
        case CTRL_DEST_LOW:    destAddress = (destAddress & 0xFF00) | value; break;
        case CTRL_LENGTH_HIGH: length = (uint16_t)(value << 8) | (length & 0x00FF); break;
        case CTRL_LENGTH_LOW:  length = (length & 0xFF00) | value; break;

        case CTRL_GUARD_BANK:       guardBank = value; break;
        case CTRL_GUARD_START_HIGH: guardStart = (uint16_t)(value << 8) | (guardStart & 0x00FF); break;
        case CTRL_GUARD_START_LOW:  guardStart = (guardStart & 0xFF00) | value; break;
        case CTRL_GUARD_END_HIGH:   guardEnd = (uint16_t)(value << 8) | (guardEnd & 0x00FF); break;
        case CTRL_GUARD_END_LOW:    guardEnd = (guardEnd & 0xFF00) | value; break;

        case CTRL_DATA:
            // A byte into the destination, and the address steps on so that writing a
            // run of bytes is a loop over one instruction rather than four.
            if (canWrite(destBank, destAddress)) {
                banks[destBank].memory[destAddress] = value;
                if (destBank == BANK_TABLE) {
                    // Unreachable while the table is read only, and here so that it stays
                    // true if that ever changes: the published bytes are a description,
                    // and nothing may write through them into a real bank.
                    publishBank(BANK_TABLE);
                }
                destAddress++;
                status = 0;
            }
        break;

        case CTRL_COMMAND:
            // Both leave the addresses past whatever they touched and Length as it was,
            // so asking again carries straight on from where the last one stopped.
            switch (value) {
                case COMMAND_BLIT: doBlit(); break;
                case COMMAND_FILL: doFill(); break;
                case COMMAND_REGISTER_BANK: doRegisterBank(); break;
                case COMMAND_GUARD_ON: doGuardOn(); break;
                case COMMAND_GUARD_OFF: doGuardOff(); break;
                default:
                    // Refusing an unknown command is better than ignoring it, since a
                    // program that asked for something is entitled to find out that it
                    // did not happen.
                    refuse(VECTOR_BANK_FAULT);
                break;
            }
        break;

        default:
            // Status is read only.
        break;
    }
    return 0;
}

uint8_t controllerRead(uint8_t port) {
    switch (port) {
        case CTRL_SOURCE_BANK: return sourceBank;
        case CTRL_SOURCE_HIGH: return (uint8_t)(sourceAddress >> 8);
        case CTRL_SOURCE_LOW:  return (uint8_t)(sourceAddress & 0xFF);
        case CTRL_DEST_BANK:   return destBank;
        case CTRL_DEST_HIGH:   return (uint8_t)(destAddress >> 8);
        case CTRL_DEST_LOW:    return (uint8_t)(destAddress & 0xFF);
        case CTRL_LENGTH_HIGH: return (uint8_t)(length >> 8);
        case CTRL_LENGTH_LOW:  return (uint8_t)(length & 0xFF);
        case CTRL_STATUS:      return status;

        case CTRL_GUARD_BANK:       return guardBank;
        case CTRL_GUARD_START_HIGH: return (uint8_t)(guardStart >> 8);
        case CTRL_GUARD_START_LOW:  return (uint8_t)(guardStart & 0xFF);
        case CTRL_GUARD_END_HIGH:   return (uint8_t)(guardEnd >> 8);
        case CTRL_GUARD_END_LOW:    return (uint8_t)(guardEnd & 0xFF);

        case CTRL_DATA: {
            // A byte out of the source, stepping on the same way a write does.
            if (!canRead(sourceBank, sourceAddress)) {
                return 0;
            }
            uint8_t value = banks[sourceBank].memory[sourceAddress];
            sourceAddress++;
            status = 0;
            return value;
        }
    }
    return 0;
}
