// cpu.c
// SplitBit CPU Emulator Core
// Written by Anachronaut
// 10/16/2024

#include "cpu.h"
#include "io.h"
#include "../Assembler/assembly.h" // For the vector table layout, which both tools share.

uint16_t shiftRegister;

// Reads one entry out of a vector table. Most significant byte first, matching the
// branch instructions and the binary format.
static uint16_t readVector(const uint8_t *programMemory, uint16_t base, uint8_t index) {
    uint16_t address = base + (uint16_t)index * VECTOR_ENTRY_BYTES;
    return ((uint16_t)programMemory[address] << 8) | (uint16_t)programMemory[address + 1];
}

// Builds an interrupt frame and dispatches through a vector. The resume address is the
// address execution should carry on from once the handler returns, and it goes into the
// frame as a real address so that a handler can read it and make sense of it.
//
// Returns 0 if it dispatched. If the vector is empty there is nothing to dispatch to, so
// it raises a fault and returns 1 rather than jumping to the bottom of Program Memory
// and running whatever happens to be there.
//
// Note that a zero entry means "no handler" to everything that dispatches, including the
// two entries the CPU treats as start addresses when it reads them at reset. The
// exemption belongs to that one read, not to the entries themselves.
static uint8_t enterInterrupt(CPURegisters *cpu, uint16_t base, uint8_t index, uint16_t resumeAddress) {
    uint16_t handler = readVector(cpu->Program, base, index);
    if (handler == 0x0000) {
        cpu->Fault = FAULT_NO_HANDLER;
        cpu->FaultVector = index;
        cpu->Status |= STATUS_FAULT;
        cpu->Status |= STATUS_HALT;
        return 1;
    }
    // Order mirrors genericCall exactly: low byte then high byte, lowest numbered Data
    // Pointer first, so that anything walking the Stack sees a familiar shape.
    cpu->Data[cpu->StackPointer] = resumeAddress & 0xFF;
    cpu->StackPointer--;
    cpu->Data[cpu->StackPointer] = (resumeAddress >> 8) & 0xFF;
    cpu->StackPointer--;
    for (int i = 0; i < DATA_POINTERS; i++) {
        cpu->Data[cpu->StackPointer] = cpu->DataPointer[i] & 0xFF;
        cpu->StackPointer--;
        cpu->Data[cpu->StackPointer] = (cpu->DataPointer[i] >> 8) & 0xFF;
        cpu->StackPointer--;
    }
    cpu->Data[cpu->StackPointer] = cpu->B;
    cpu->StackPointer--;
    cpu->Data[cpu->StackPointer] = cpu->A;
    cpu->StackPointer--;
    cpu->Data[cpu->StackPointer] = cpu->Q;
    cpu->StackPointer--;
    cpu->Data[cpu->StackPointer] = cpu->Status;
    cpu->StackPointer--;
    // A handler runs with hardware interrupts held off unless it says otherwise, so an
    // interrupt cannot arrive inside the handler for another one and grow the Stack
    // without bound. The old setting rode into the frame inside the Status register, so
    // RETI puts it back without anything having to remember it separately.
    cpu->Status &= ~STATUS_INTERRUPT;
    // The Program Counter is stepped after every instruction, so land one short of the
    // handler and let that step land on its first byte. genericBranch does the same.
    cpu->ProgramCounter = handler - 1;
    return 0;
}

// A device that refused what it was asked stops the machine where it stands, rather than
// raising a line and letting execution carry on past the mistake. The frame carries the
// address of the instruction that asked, so a handler can see which one it was, and so a
// bare RETI meets it again the way every other fault on this machine does.
//
// Returns 1 if the machine has stopped because nothing was installed to catch it.
static uint8_t answerRefusal(CPURegisters *cpu, uint16_t site) {
    uint8_t refusal = takeRefusal();
    if (refusal == 0) {
        return 0;
    }
    if (enterInterrupt(cpu, SOFTWARE_VECTOR_BASE, refusal, site)) {
        cpu->Fault = FAULT_DEVICE_REFUSED;
        cpu->FaultVector = refusingPort();
        cpu->ProgramCounter = site - 1;
    }
    return 0;
}

void initializeCPU(CPURegisters *cpu, uint8_t *programMemory, uint8_t *dataMemory) {
    cpu->A = 0;
    cpu->B = 0;
    cpu->Q = 0;
    cpu->Status = 0;
    // Execution begins wherever the boot vector points. It is a start address rather
    // than a handler, so a zero there is not "nothing installed" but the address
    // 0x0000, which is where a program carrying no vector table of its own begins.
    // That is what lets everything written before the table existed still run.
    cpu->ProgramCounter = readVector(programMemory, SOFTWARE_VECTOR_BASE, VECTOR_BOOT);
    // Every Data Pointer starts at the bottom of Data Memory.
    for (int i = 0; i < DATA_POINTERS; i++) {
        cpu->DataPointer[i] = 0x0000;
    }
    cpu->StackPointer = 0xFFFF;
    cpu->Program = programMemory;
    cpu->Data = dataMemory;
    cpu->Fault = FAULT_NONE;
    cpu->FaultVector = 0;
}

void genericBranch(CPURegisters *cpu){
    // Load the next two bytes from program memory into the Program Counter.
    // Byte order is imporant. Most Significant first, then Least Significant.
    cpu->ProgramCounter++; // Move to the next byte. (MSB)
    uint16_t DestinationAddress;
    DestinationAddress = (uint16_t)cpu->Program[cpu->ProgramCounter] << 8; // Cast the 8 bit value to a 16 bit value and shifts it up to the high byte.
    cpu->ProgramCounter++; // Move to the next byte. (LSB)
    DestinationAddress = DestinationAddress | (uint16_t)cpu->Program[cpu->ProgramCounter]; // Cast the 8 bit value to a 16 bit value and or it to add it to the desination.
    cpu->ProgramCounter = DestinationAddress-1;
}

void genericCall(CPURegisters *cpu){
    // Order, low byte, high byte
    cpu->Data[cpu->StackPointer] = cpu->ProgramCounter & 0xFF;
    cpu->StackPointer--;
    cpu->Data[cpu->StackPointer] = (cpu->ProgramCounter >> 8) & 0xFF;
    cpu->StackPointer--;
    // Push the preserved Data Pointers to the Stack, lowest numbered first.
    // Order within each one, low byte, high byte.
    // The pointers above PRESERVED_DATA_POINTERS are deliberately left alone, so a
    // subroutine can use one to hand an address back to whoever called it.
    for (int i = 0; i < PRESERVED_DATA_POINTERS; i++) {
        cpu->Data[cpu->StackPointer] = cpu->DataPointer[i] & 0xFF;
        cpu->StackPointer--;
        cpu->Data[cpu->StackPointer] = (cpu->DataPointer[i] >> 8) & 0xFF;
        cpu->StackPointer--;
    }
    // Push B to the Stack.
    cpu->Data[cpu->StackPointer] = cpu->B;
    cpu->StackPointer--;
    // Push A to the Stack.
    cpu->Data[cpu->StackPointer] = cpu->A;
    cpu->StackPointer--;
    // Perform a Generic Branch to the Address.
    genericBranch(cpu);
}

uint16_t *selectDataPointer(CPURegisters *cpu) {
    // Every instruction that works through a Data Pointer names which one in the
    // byte immediately after the opcode. Out of range selectors are masked down
    // rather than rejected, the way a narrow field in hardware would be. It is the
    // assembler's job to refuse to emit one in the first place.
    cpu->ProgramCounter++;
    return &cpu->DataPointer[cpu->Program[cpu->ProgramCounter] & (DATA_POINTERS - 1)];
}

uint8_t executeOperation(uint8_t Instruction, CPURegisters *cpu) {
    // ADD and SUB share this. It is declared here rather than after a case label
    // because a label may only be followed by a statement in ISO C, and a
    // declaration is not one.
    uint16_t result;
    switch(Instruction) {
        // 0x - Arithmetic and Logic Operations.
        case 0x00:
            // ADD - A + B + Carry -> Q
            result = (uint16_t)cpu->A + (uint16_t)cpu->B + (cpu->Status & STATUS_CARRY);
            if (result > 255) {
                cpu->Status |= STATUS_CARRY;
            } else {
                cpu->Status &= ~STATUS_CARRY;
            }
            cpu->Q = result & 0xFF;
        break;
        case 0x01:
            // SUB - A - B - Carry -> Q
            result = (uint16_t)cpu->A - (uint16_t)cpu->B - (cpu->Status & STATUS_CARRY);
            if (result > 255) {
                cpu->Status |= STATUS_CARRY;
            } else {
                cpu->Status &= ~STATUS_CARRY;
            }
            cpu->Q = result & 0xFF;
        break;
        case 0x02:
            // AND - A and B -> Q
            cpu->Q = cpu->A&cpu->B;
        break;
        case 0x03:
            // OR - A or B -> Q
            cpu->Q = cpu->A|cpu->B;
        break;
        case 0x04:
            // XOR - A xor B -> Q
            cpu->Q = cpu->A^cpu->B;
        break;
        case 0x05:
            // NOTA - not A -> Q
            cpu->Q = ~cpu->A;
        break;
        case 0x06:
            // NOTB - not B -> Q
            cpu->Q = ~cpu->B;
        break;
        case 0x07:
            // SHL - Shift AB left.
            shiftRegister = ((uint16_t)cpu->A << 8) | cpu->B;
            shiftRegister = (shiftRegister << 1) | (shiftRegister >> 15);
            cpu->A = shiftRegister >> 8;
            cpu->B = shiftRegister & 0xFF;
        break;
        case 0x08:
            // SHR - Shift AB right.
            shiftRegister = ((uint16_t)cpu->A << 8) | cpu->B;
            shiftRegister = (shiftRegister >> 1) | (shiftRegister << 15);
            cpu->A = shiftRegister >> 8;
            cpu->B = shiftRegister & 0xFF;
        break;
        //
        // 1x - Branch Operations:
        //
        case 0x10:
            // BRI - Branch Immediately
            genericBranch(cpu);
        break;
        case 0x11:
            // BRQ - Branch if Q = 0
            if(cpu->Q == 0) {
                genericBranch(cpu);
            } else {

                cpu->ProgramCounter+=2;
            }
        break;
        case 0x12:
            // BRA - Branch if A = 0
            if(cpu->A == 0) {
                genericBranch(cpu);

            } else {
                cpu->ProgramCounter+=2;
            }
        break;
        case 0x13:
            // BRB -  if B = 0
            if(cpu->B == 0) {

                genericBranch(cpu);
            } else {
                cpu->ProgramCounter+=2;
            }
        break;
        case 0x14:
            // BRC - Do an immediate branch if the Carry Flag is set.
            if (cpu->Status & STATUS_CARRY) {
                genericBranch(cpu);
            } else {
                cpu->ProgramCounter+=2;
            }
        break;
        case 0x15: {
            // BRD - Branch to the address held in a Data Pointer.
            // This is the only branch whose destination is not written into the
            // program, which is what makes a table of addresses something a program
            // can dispatch through rather than only read.
            uint16_t destination = *selectDataPointer(cpu);
            // stepCPU adds one after every instruction, so aim one short.
            cpu->ProgramCounter = destination - 1;
        }
        break;
        case 0x17:
            // CALL - Push the Program Counter to the Stack, and perform an immediate branch.
            genericCall(cpu);
        break;
        case 0x1A:
            // BNQ - Branch if Q is not 0.
            if(cpu->Q != 0) {
                genericBranch(cpu);
            } else {
                cpu->ProgramCounter+=2;
            }
        break;
        case 0x1B:
            // BNA - Branch if A is not 0.
            if(cpu->A != 0) {
                genericBranch(cpu);
            } else {
                cpu->ProgramCounter+=2;
            }
        break;
        case 0x1C:
            // BNB - Branch if B is not 0.
            if(cpu->B != 0) {
                genericBranch(cpu);
            } else {
                cpu->ProgramCounter+=2;
            }
        break;
        case 0x1D:
            // BNC - Branch if the Carry Flag is clear.
            if (!(cpu->Status & STATUS_CARRY)) {
                genericBranch(cpu);
            } else {
                cpu->ProgramCounter+=2;
            }
        break;
        case 0x18: {
            // SWI - Software Interrupt. The byte after the opcode names the vector.
            // Never masked: this is an instruction the program deliberately ran, not
            // something a device asked for.
            uint16_t site = cpu->ProgramCounter;
            cpu->ProgramCounter++;
            uint8_t vector = cpu->Program[cpu->ProgramCounter];
            // Execution resumes after the operand, which the Program Counter is sitting
            // on, so the resume address is one further on than that.
            if (enterInterrupt(cpu, SOFTWARE_VECTOR_BASE, vector, cpu->ProgramCounter + 1)) {
                // No handler. Leave the Program Counter on the SWI itself rather than
                // its operand, so the report names the instruction that failed.
                cpu->ProgramCounter = site - 1;
            }
        } break;
        case 0x19: {
            // RETI - Return from an interrupt. Pops the frame in the exact reverse of
            // the order enterInterrupt pushed it.
            cpu->StackPointer++;
            cpu->Status = cpu->Data[cpu->StackPointer];
            cpu->StackPointer++;
            cpu->Q = cpu->Data[cpu->StackPointer];
            cpu->StackPointer++;
            cpu->A = cpu->Data[cpu->StackPointer];
            cpu->StackPointer++;
            cpu->B = cpu->Data[cpu->StackPointer];
            for (int i = DATA_POINTERS - 1; i >= 0; i--) {
                cpu->StackPointer++;
                cpu->DataPointer[i] = (uint16_t)cpu->Data[cpu->StackPointer] << 8;
                cpu->StackPointer++;
                cpu->DataPointer[i] |= (uint16_t)cpu->Data[cpu->StackPointer];
            }
            uint16_t resumeAddress;
            cpu->StackPointer++;
            resumeAddress = (uint16_t)cpu->Data[cpu->StackPointer] << 8;
            cpu->StackPointer++;
            resumeAddress = resumeAddress | (uint16_t)cpu->Data[cpu->StackPointer];
            // The frame holds the address to carry on from. The Program Counter is
            // stepped after every instruction, so land one short of it. RET does the
            // same job with its +2, for the same reason.
            cpu->ProgramCounter = resumeAddress - 1;
        } break;
        case 0x1F:
            // RET - Return from subroutine, restore the registers and set the Program Counter to the Return Address.
            // Pop A from the Stack.
            cpu->StackPointer++;
            cpu->A = cpu->Data[cpu->StackPointer];
            // Pop B from the Stack.
            cpu->StackPointer++;
            cpu->B = cpu->Data[cpu->StackPointer];
            // Pop the preserved Data Pointers from the Stack. This walks the pointers
            // in the opposite order to genericCall, and takes the high byte before the
            // low byte, so that it exactly mirrors the way they were pushed.
            for (int i = PRESERVED_DATA_POINTERS - 1; i >= 0; i--) {
                cpu->StackPointer++;
                cpu->DataPointer[i] = (uint16_t)cpu->Data[cpu->StackPointer] << 8;
                cpu->StackPointer++;
                cpu->DataPointer[i] |= (uint16_t)cpu->Data[cpu->StackPointer];
            }
            // Pop the Return Address from the Stack.
            cpu->StackPointer++;
            cpu->ProgramCounter = (uint16_t)cpu->Data[cpu->StackPointer] << 8;
            cpu->StackPointer++;
            cpu->ProgramCounter = cpu->ProgramCounter | (uint16_t)cpu->Data[cpu->StackPointer];
            // Add 2 to the Program Counter to skip over the address when it returns.
            cpu->ProgramCounter += 2;

        break;
        //
        // 2x - Register Operations:
        //
        case 0x20:
            // RSTA - Reset A to 0.
            cpu->A = 0;
        break;
        case 0x21:
            // RSTB - Reset B to 0.
            cpu->B = 0;
        break;
        case 0x22:
            // INCA - Add 1 to A.
            // Set the Carry Flag if the register overflows.
            if (cpu->A == 0xFF) {
                cpu->Status |= STATUS_CARRY;
            } else {
                cpu->Status &= ~STATUS_CARRY;
            }
            cpu->A++;
        break;
        case 0x23:
            // INCB - Add 1 to B.
            // Set the Carry Flag if the register overflows.
            if (cpu->B == 0xFF) {
                cpu->Status |= STATUS_CARRY;
            } else {
                cpu->Status &= ~STATUS_CARRY;
            }
            cpu->B++;
        break;
        case 0x24:
            // DECA - Subtract 1 from A.
            // Set the Carry Flag if the register underflows.
            if (cpu->A == 0x00) {
                cpu->Status |= STATUS_CARRY;
            } else {
                cpu->Status &= ~STATUS_CARRY;
            }
            cpu->A--;
        break;
        case 0x25:
            // DECB - Subtract 1 from B.
            // Set the Carry Flag if the register underflows.
            if (cpu->B == 0x00) {
                cpu->Status |= STATUS_CARRY;
            } else {
                cpu->Status &= ~STATUS_CARRY;
            }
            cpu->B--;
        break;
        case 0x26:
            // INIA - Initialize A Immediately from Program Memory.
            cpu->ProgramCounter++;
            cpu->A = cpu->Program[cpu->ProgramCounter];
        break;
        case 0x27:
            // INIB - Initialize A Immediately from Program Memory.
            cpu->ProgramCounter++;
            cpu->B = cpu->Program[cpu->ProgramCounter];
        break;
        case 0x28:
            // CCF - Clear the Carry Flag.
            cpu->Status &= ~STATUS_CARRY;
        break;
        case 0x29:
            // MVQA - Copy Q into A.
            cpu->A = cpu->Q;
        break;
        case 0x2A:
            // MVQB - Copy Q into B.
            cpu->B = cpu->Q;
        break;
        case 0x2B:
            // SIF - Set the Interrupt Flag, enabling hardware interrupts.
            cpu->Status |= STATUS_INTERRUPT;
        break;
        case 0x2C:
            // CIF - Clear the Interrupt Flag, disabling hardware interrupts.
            // Software interrupts and faults are delivered either way, so this
            // only ever holds off a device.
            cpu->Status &= ~STATUS_INTERRUPT;
        break;
        //
        // 3x - Stack Operations:
        //
        case 0x30:
            // PSHQ - Push Q to the Stack.
            cpu->Data[cpu->StackPointer] = cpu->Q;
            cpu->StackPointer--;
        break;
        case 0x31:
            // PSHA - Push A to the Stack.
            cpu->Data[cpu->StackPointer] = cpu->A;
            cpu->StackPointer--;
        break;
        case 0x32:
            // PSHB - Push B to the Stack.
            cpu->Data[cpu->StackPointer] = cpu->B;
            cpu->StackPointer--;
        break;
        case 0x33: {
            // PSHD - Push the selected Data Pointer Address to the Stack.
            // Order, high byte, low byte
            // This ordering makes it easier to add offsets with register math.
            uint16_t pushed = *selectDataPointer(cpu);
            cpu->Data[cpu->StackPointer] = (pushed >> 8) & 0xFF;
            cpu->StackPointer--;
            cpu->Data[cpu->StackPointer] = pushed & 0xFF;
            cpu->StackPointer--;
        }
        break;
        case 0x34:
            // POPA - Pop A from the Stack.
            cpu->StackPointer++;
            cpu->A = cpu->Data[cpu->StackPointer];

        break;
        case 0x35:
            // POPB - Pop B from the Stack.
            cpu->StackPointer++;
            cpu->B = cpu->Data[cpu->StackPointer];
        break;
        case 0x36: {
            // POPD - Pop a Data Address from the Stack into the selected Data Pointer.
            uint16_t *popped = selectDataPointer(cpu);
            cpu->StackPointer++;
            *popped = (uint16_t)cpu->Data[cpu->StackPointer];
            cpu->StackPointer++;
            *popped |= (uint16_t)cpu->Data[cpu->StackPointer] << 8;
        }
        break;
        //
        // 4x - Data Operations:
        //
        case 0x40:
            // INCD - Increment the selected Data Pointer.
            (*selectDataPointer(cpu))++;
        break;
        case 0x41:
            // DECD - Decrement the selected Data Pointer.
            (*selectDataPointer(cpu))--;
        break;
        case 0x42:
            // LDA - Load A from Data.
            cpu->A = cpu->Data[*selectDataPointer(cpu)];
        break;
        case 0x43:
            // LDB - Load B from Data.
            cpu->B = cpu->Data[*selectDataPointer(cpu)];
        break;
        case 0x44:
            // STQ - Store Q into Data.
            cpu->Data[*selectDataPointer(cpu)] = cpu->Q;
        break;
        case 0x45:
            // STA - Store A into Data.
            cpu->Data[*selectDataPointer(cpu)] = cpu->A;
        break;
        case 0x46:
            // STB - Store B into Data.
            cpu->Data[*selectDataPointer(cpu)] = cpu->B;
        break;
        case 0x47: {
            // SETD - Set the selected Data Pointer.
            uint16_t *destination = selectDataPointer(cpu);
            cpu->ProgramCounter++;
            uint16_t Address;
            Address = (uint16_t)cpu->Program[cpu->ProgramCounter] << 8; // Cast the 8 bits to a 16 bit value and shift them to the high byte.
            cpu->ProgramCounter++;
            Address |= (uint16_t)cpu->Program[cpu->ProgramCounter];
            *destination = Address;
        }
        break;
        case 0x48: {
            // DPUP - Offset the selected Data Pointer up by the value of the next byte of Program Memory.
            uint16_t *target = selectDataPointer(cpu);
            cpu->ProgramCounter++;
            *target += cpu->Program[cpu->ProgramCounter];
        }
        break;
        case 0x49: {
            // DPDN - Offset the selected Data Pointer down by the value of the next byte of Program Memory.
            uint16_t *target = selectDataPointer(cpu);
            cpu->ProgramCounter++;
            *target -= cpu->Program[cpu->ProgramCounter];
        }
        break;
        case 0x4A: {
            // LDD - Load the first Data Pointer from the two bytes of Data Memory
            // addressed by the second. Byte order matches everywhere else an address
            // is stored: most significant first, then least significant.
            // The source is taken by value before anything is written, so LDD.0.0
            // follows the pointer in DP0 rather than tripping over itself.
            uint16_t *destination = selectDataPointer(cpu);
            uint16_t source = *selectDataPointer(cpu);
            *destination = (uint16_t)cpu->Data[source] << 8;
            *destination |= (uint16_t)cpu->Data[(uint16_t)(source + 1)];
        }
        break;
        case 0x4B: {
            // STD - Store the first Data Pointer into the two bytes of Data Memory
            // addressed by the second. The cast on the second address keeps it inside
            // Data Memory when the pointer sits at the very top of it.
            uint16_t value = *selectDataPointer(cpu);
            uint16_t address = *selectDataPointer(cpu);
            cpu->Data[address] = (value >> 8) & 0xFF;
            cpu->Data[(uint16_t)(address + 1)] = value & 0xFF;
        }
        break;
        case 0x4C: {
            // MVSD - Copy the Stack Pointer into the selected Data Pointer.
            //
            // The Stack Pointer still cannot be written, so this does not let a program
            // move the Stack. It lets a program find it, which is what reading anything
            // already on the Stack requires. An interrupt handler needs this to reach
            // its own frame, and so does anything that wants to walk back through the
            // calls that led to where it is.
            uint16_t *target = selectDataPointer(cpu);
            *target = cpu->StackPointer;
        }
        break;
        case 0x4D: {
            // MVDS - Copy the selected Data Pointer into the Stack Pointer.
            //
            // This one is dangerous and is meant to be used rarely. Moving the Stack
            // under a running program abandons every return address on it, so a RET
            // after this goes wherever the new Stack happens to say.
            //
            // It exists because a system that runs other programs has no other way to
            // get its Stack back. A program that gives up part way through leaves
            // whatever it pushed behind, and the interrupt frame that carried the
            // request to stop is on there too. Without this the Stack only ever grows
            // downward, one abandoned program at a time, and a shell cannot outlive
            // many of them.
            uint16_t *source = selectDataPointer(cpu);
            cpu->StackPointer = *source;
        }
        break;
        //
        // Dx - Output Operations:
        //
        case 0xD0: {
            // OUTQ - Write the value of Q to an output port.
            uint16_t site = cpu->ProgramCounter;
            cpu->ProgramCounter++;
            OutputHandler(cpu->Q, cpu->Program[cpu->ProgramCounter]);
            answerRefusal(cpu, site);
        }
        break;
        case 0xD1: {
            // OUTA - Write the value of A to an output port.
            uint16_t site = cpu->ProgramCounter;
            cpu->ProgramCounter++;
            OutputHandler(cpu->A, cpu->Program[cpu->ProgramCounter]);
            answerRefusal(cpu, site);
        }
        break;
        case 0xD2: {
            // OUTB - Write the value of B to an output port.
            uint16_t site = cpu->ProgramCounter;
            cpu->ProgramCounter++;
            OutputHandler(cpu->B, cpu->Program[cpu->ProgramCounter]);
            answerRefusal(cpu, site);
        }
        break;
        //
        // Ex - Input Operations:
        //
        case 0xE0: {
            // INA - Read an Input to A.
            uint16_t site = cpu->ProgramCounter;
            cpu->ProgramCounter++;
            cpu->A = InputHandler(cpu->Program[cpu->ProgramCounter]);
            answerRefusal(cpu, site);
        }
        break;
        case 0xE1: {
            // INB - Read an Input to B.
            uint16_t site = cpu->ProgramCounter;
            cpu->ProgramCounter++;
            cpu->B = InputHandler(cpu->Program[cpu->ProgramCounter]);
            answerRefusal(cpu, site);
        }
        break;
        //
        // Fx - Special Operations:
        //
        case 0xF0:
            // NOP - Do nothing.
        break;
        case 0xFF:
            // HALT - Set the Halt Bit of the Status Register.
            cpu->Status |= STATUS_HALT;
        break;
        default:
            // Unknown Instruction.
            return 1;
    }
    return 0;
}

void stepCPU(CPURegisters *cpu) {
    if (!(cpu->Status & STATUS_HALT)) {
        // A device asking for attention is answered between instructions and never
        // inside one, so the address that goes into the frame is always the start of an
        // instruction and RETI always lands somewhere meaningful.
        //
        // A line that is up while the Interrupt Flag is clear stays up. Masking holds a
        // device off; it does not lose what the device was asking for.
        if (cpu->Status & STATUS_INTERRUPT) {
            int port = nextPendingInterrupt();
            if (port >= 0) {
                clearInterrupt((uint8_t)port);
                if (enterInterrupt(cpu, HARDWARE_VECTOR_BASE, (uint8_t)port, cpu->ProgramCounter)) {
                    // The device asked and nobody was listening. enterInterrupt has
                    // already stopped the machine; correct the cause, because the empty
                    // entry is in the hardware table rather than the software one.
                    cpu->Fault = FAULT_NO_DEVICE_HANDLER;
                    return;
                }
                // Entering the handler is what this cycle did, so no instruction runs.
                // The step puts the Program Counter on the handler's first byte, the
                // same way it does everywhere else.
                cpu->ProgramCounter++;
                return;
            }
        }
        // The CPU is not halted, so do a cycle.
        if (executeOperation(cpu->Program[cpu->ProgramCounter], cpu)) {
            // Nothing decodes that byte. Hand it to the fault vector, which gets the
            // address of the offending byte itself rather than the one after it, so
            // that a handler can read the byte that failed and say what it was.
            //
            // A handler returning with a bare RETI will therefore meet the same byte
            // again. That is the documented behaviour: resuming past a fault means
            // deciding where to resume, which is the handler's business and not the
            // CPU's guess.
            uint16_t faultingAddress = cpu->ProgramCounter;
            if (enterInterrupt(cpu, SOFTWARE_VECTOR_BASE, VECTOR_INVALID_OPCODE, faultingAddress)) {
                // Nothing is installed, so stop where we are. The Program Counter is
                // still on the offending byte, which is what the report wants. The
                // cause is the byte, not the empty vector, so say so.
                cpu->Fault = FAULT_BAD_OPCODE;
                return;
            }
            // Dispatched. Fall through, so the step below lands on the handler.
        }
        cpu->ProgramCounter++;
    }
}
