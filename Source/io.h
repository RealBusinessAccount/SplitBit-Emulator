// io.h
// I/O for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/16/2024

#ifndef IO_H
#define IO_H

#include <stdint.h>
#include "cpu.h"

uint8_t OutputHandler(uint8_t DataByte, uint8_t Address);

uint8_t InputHandler(uint8_t Address);

#endif // IO_H
