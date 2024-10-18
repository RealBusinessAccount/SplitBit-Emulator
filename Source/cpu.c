// cpu.c
// SplitBit CPU Emulator Core
// Written by Anachronaut
// 10/16/2024

#include "cpu.h"
#include "io.h"

void initializeCPU(CPURegisters *cpu, uint8_t *programMemory, uint8_t *dataMemory) {
    cpu->A = 0;
    cpu->B = 0;
    cpu->Q = 0;
    cpu->Status = 0;
    cpu->ProgramCounter = 0x0000;
    cpu->DataPointer = 0x0000;
    cpu->StackPointer = 0xFFFF;
    cpu->Program = programMemory;
    cpu->Data = dataMemory;
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

uint8_t executeOperation(uint8_t Instruction, CPURegisters *cpu) {
    switch(Instruction) {
        // 0x - Arithmetic and Logic Operations.
        case 0x00:
            // ADD - A + B + Carry -> Q
            uint16_t result = (uint16_t)cpu->A + (uint16_t)cpu->B + (cpu->Status & 0x01);
            if (result > 255) {
                cpu->Status |= 0x01;
            } else {
                cpu->Status &= ~0x01;
            }
            cpu->Q = result & 0xFF;
        break;
        case 0x01:
            // SUB - A - B - Carry -> Q
            result = (uint16_t)cpu->A - (uint16_t)cpu->B - (cpu->Status & 0x01);
            if (result > 255) {
                cpu->Status |= 0x01;
            } else {
                cpu->Status &= ~0x01;
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
            // NAND - A nand B -> Q
            cpu->Q = ~(cpu->A&cpu->B);
        break;
        case 0x05:
            // NOR - A nor B -> Q
            cpu->Q = ~(cpu->A|cpu->B);
        break;
        case 0x06:
            // XOR - A xor B -> Q
            cpu->Q = cpu->A^cpu->B;
        break;
        case 0x07:
            // NOTA - not A -> Q
            cpu->Q = ~cpu->A;
        break;
        case 0x08:
            // NOTB - not B -> Q
            cpu->Q = ~cpu->B;
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
            cpu->A++;
        break;
        case 0x23:
            // INCB - Add 1 to B.
            cpu->B++;
        break;
        case 0x24:
            // DECA - Subtract 1 from A.
            cpu->A--;
        break;
        case 0x25:
            // DECB - Subtract 1 from B.
            cpu->B--;
        break;
        case 0x26:
            // LDA - Load the byte referenced by the Data Pointer to A.
            cpu->A = cpu->Data[cpu->DataPointer];
        break;
        case 0x27:
            // LDB - Load the byte referenced by the Data Pointer to B.
            cpu->B = cpu->Data[cpu->DataPointer];
        break;
        case 0x28:
            // INIA - Initialize A Immediately from Program Memory.
            cpu->ProgramCounter++;
            cpu->A = cpu->Data[cpu->ProgramCounter];
        break;
        case 0x29:
            // INIB - Initialize A Immediately from Program Memory.
            cpu->ProgramCounter++;
            cpu->B = cpu->Data[cpu->ProgramCounter];
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
        case 0x33:
            // PSHP - Push the Program Counter to the Stack.
            // Order, low byte, high byte
            cpu->Data[cpu->StackPointer] = cpu->ProgramCounter & 0xFF;
            cpu->StackPointer--;
            cpu->Data[cpu->StackPointer] = (cpu->ProgramCounter >> 8) & 0xFF;
            cpu->StackPointer--;
        break;
        case 0x34:
            // PSHD - Push the Data Pointer to the Stack.
            // Order, low byte, high byte
            cpu->Data[cpu->StackPointer] = cpu->DataPointer & 0xFF;
            cpu->StackPointer--;
            cpu->Data[cpu->StackPointer] = (cpu->DataPointer >> 8) & 0xFF;
            cpu->StackPointer--;
        break;
        case 0x35:
            // POPA - Pop Data to A.
            cpu->StackPointer++;
            cpu->A = cpu->Data[cpu->StackPointer];

        break;
        case 0x36:
            // POPB - Pop Data to B.
            cpu->StackPointer++;
            cpu->B = cpu->Data[cpu->StackPointer];
        break;
        case 0x37:
            // POPP - Pop Data to the Program Counter
            cpu->ProgramCounter = (uint16_t)cpu->Data[cpu->StackPointer] << 8;
            cpu->StackPointer++;
            cpu->ProgramCounter = cpu->ProgramCounter | (uint16_t)cpu->Data[cpu->StackPointer];
            cpu->ProgramCounter += 3; // Because it needs to skip over the subsequent branch instruction on return.
            cpu->StackPointer++;
        break;
        case 0x38:
            // POPD - Pop Data to the Data Pointer
            cpu->DataPointer = (uint16_t)cpu->Data[cpu->StackPointer] << 8;
            cpu->StackPointer++;
            cpu->DataPointer |= (uint16_t)cpu->Data[cpu->StackPointer];
            cpu->StackPointer++;
        break;
        //
        // 4x - Data Operations:
        //
        case 0x40:
            // INCD - Increment Data Pointer.
            cpu->DataPointer++;
        break;
        case 0x41:
            // DECD - Decrement Data Pointer.
            cpu->DataPointer--;
        break;
        case 0x42:
            // LDA - Load A from Data.
            cpu->A = cpu->Data[cpu->DataPointer];
        break;
        case 0x43:
            // LDB - Load B from Data.
            cpu->B = cpu->Data[cpu->DataPointer];
        break;
        case 0x44:
            // STQ - Store Q into Data.
            cpu->Data[cpu->DataPointer] = cpu->Q;
        break;
        case 0x45:
            // STA - Store A into Data.
            cpu->Data[cpu->DataPointer] = cpu->A;
        break;
        case 0x46:
            // STB - Store B into Data.
            cpu->Data[cpu->DataPointer] = cpu->B;
        break;
        case 0x47:
            // SETD - Set the Data Pointer.
            cpu->ProgramCounter++;
            uint16_t Address;
            Address = (uint16_t)cpu->Program[cpu->ProgramCounter] << 8; // Cast the 8 bits to a 16 bit value and shift them to the high byte.
            cpu->ProgramCounter++;
            Address |= (uint16_t)cpu->Program[cpu->ProgramCounter];
            cpu-> DataPointer = Address;
        break;
        //
        // Dx - Output Operations:
        //
        case 0xD0:
            // OUTQ - Write the value of Q to an output port.
            cpu->ProgramCounter++;
            OutputHandler(cpu->Q, cpu->Program[cpu->ProgramCounter]);
        break;
        case 0xD1:
            // OUTA - Write the value of A to an output port.
            cpu->ProgramCounter++;
            OutputHandler(cpu->A, cpu->Program[cpu->ProgramCounter]);
        break;
        case 0xD2:
            // OUTB - Write the value of B to an output port.
            cpu->ProgramCounter++;
            OutputHandler(cpu->B, cpu->Program[cpu->ProgramCounter]);
        break;
        //
        // Ex - Input Operations:
        //
        case 0xE0:
            // CIN - Read Input Select to A.
            // cpu->A = InputSelect;
        break;
        case 0xE1:
            // RDA - Read an Input to A.
            cpu->ProgramCounter++;
            cpu->A = InputHandler(cpu->Program[cpu->ProgramCounter]);
        break;
        case 0xE2:
            // RDB - Read an Input to B.
            cpu->ProgramCounter++;
            cpu->B = InputHandler(cpu->Program[cpu->ProgramCounter]);
        break;
        case 0xE3:
            // RDD - Read an Input to Data Memory.
            cpu->ProgramCounter++;
            cpu->Data[cpu->DataPointer] = InputHandler(cpu->Program[cpu->ProgramCounter]);
        break;
        //
        // Fx - Special Operations:
        //
        case 0xF0:
            // NOP - Do nothing.
        break;
        case 0xFF:
            // HALT - Set the Halt Bit of the Status Register.
            cpu->Status |= 0x80;
        break;
        default:
            // Unknown Instruction.
            return 1;
    }
    if (cpu->DataPointer >= cpu->StackPointer) {
        // A Stack Collision was detected.
        cpu->Status |= 0x82; // Set Stack Collision Flag and Halt . (Bits 7 and 1 of the Status Register);
        return 2;
    }
    return 0;
}
