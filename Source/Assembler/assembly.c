// assembly.c
// These are functions useful for translating assembly mnemonics to hex and vice-versa for the SplitBit CPU.
// Written by Anachronaut
// 10/18/2024

#include "assembly.h"
#include <string.h>

typedef struct {
    uint8_t opcode;
    const char* mnemonic;
} Instruction;

Instruction instruction_set[] = {
    // Arithmetic and Logic Operations:
    {0x00, "ADD"},
    {0x01, "SUB"},
    {0x02, "AND"},
    {0x03, "OR"},
    {0x04, "NOR"},
    {0x05, "NAND"},
    {0x06, "XOR"},
    {0x07, "NOTA"},
    {0x08, "NOTB"},
    {0x09, "SHL"},
    {0x0A, "SHR"},
    // Branch Operations:
    {0x10, "BRI"},
    {0x11, "BRQ"},
    {0x12, "BRA"},
    {0x13, "BRB"},
    {0x14, "BRC"},
    {0x17, "CALL"},
    {0x18, "CALLA"},
    {0x19, "CALLB"},
    {0x1A, "CALLQ"},
    {0x1B, "CALLCF"},
    {0x1F, "RET"},
    // Register Operations:
    {0x20, "RSTA"},
    {0x21, "RSTB"},
    {0x22, "INCA"},
    {0x23, "INCB"},
    {0x24, "DECA"},
    {0x25, "DECB"},
    {0x26, "LDA"},
    {0x27, "LDB"},
    {0x28, "INIA"},
    {0x29, "INIB"},
    {0x2F, "CCF"},
    // Stack Operations:
    {0x30, "PSHQ"},
    {0x31, "PSHA"},
    {0x32, "PSHB"},
    {0x33, "PSHD"},
    {0x34, "POPA"},
    {0x35, "POPB"},
    {0x36, "POPD"},
    // Data Operations:
    {0x40, "INCD"},
    {0x41, "DECD"},
    {0x42, "LDA"},
    {0x43, "LDB"},
    {0x44, "STQ"},
    {0x45, "STA"},
    {0x46, "STB"},
    {0x47, "SETD"},
    // Output Operations:
    {0xD0, "OUTQ"},
    {0xD1, "OUTA"},
    {0xD2, "OUTB"},
    // Input Operations:
    {0xE0, "INA"},
    {0xE1, "INB"},
    {0xE2, "IND"},
    // Special Operations:
    {0xF0, "NOP"},
    {0xFF, "HALT"}
};

int num_instructions = sizeof(instruction_set) / sizeof(Instruction);

const char* getMnemonic(uint8_t opcode) {
    for (int i = 0; i < num_instructions; i++) {
        if (instruction_set[i].opcode == opcode) {
            return instruction_set[i].mnemonic;
        }
    }
    return "---";
}

uint8_t getOpcode(char* mnemonic) {
    for (int i = 0; i < num_instructions; i++) {
        if (strcmp(instruction_set[i].mnemonic, mnemonic) == 0) {
            return instruction_set[i].opcode;
        }
    }
    return 0xFE; // FE is an unused instruction, we'll use it to indicate an error.
}


