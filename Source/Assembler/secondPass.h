// secondPass.c
// Functions for the 'second pass' of the SplitBit Assembler.
// Written by Anachronaut
// 10/25/2024

#ifndef SECONDPASS_H
#define SECONDPASS_H


#include <stdint.h>
#include <ctype.h>
#include "Assm-util.h"

#define MAX_LABELS 256

typedef struct {
    char* label;
    uint16_t address;
    int type;
} Label;

void freeLabelList();

void populateLabelTable(intermediateElement *intermediateArray, int arraySize);

void fillInLabelAddresses(intermediateElement *intermediateArray, int arraySize);

void populateOutputBuffers(intermediateElement *intermediateArray, int arraySize, uint8_t *Program, int *programCount, uint8_t *Data, int *dataCount);

void writeOutputFile(const char *outputFileName, uint8_t *Program, int programCount, uint8_t *Data, int dataCount);

#endif
