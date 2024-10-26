// assembly.h
// These are functions useful for translating assembly mnemonics to hex and vice-versa for the SplitBit CPU.
// Written by Anachronaut
// 10/18/2024

#include <stdint.h>

#ifndef ASSEMBLY_H
#define ASSEMBLY_H

const char* getMnemonic(uint8_t opcode);

uint8_t getOpcode(char* mnemonic);

#endif // CPU_H
