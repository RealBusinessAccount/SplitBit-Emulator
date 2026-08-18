// secondPass.c
// Functions for the 'second pass' of the SplitBit Assembler.
// Written by Anachronaut
// 10/25/2024

#ifndef SECONDPASS_H
#define SECONDPASS_H


#include <stdint.h>
#include <ctype.h>
#include "Assm-util.h"

// Every label in a program and in everything it includes shares one table, because they
// share one namespace: a name may only be defined once across the whole assembly. So this
// is not the size of one file but the size of a program and its libraries together, and
// CosmOS with its four libraries went past 256 while still being a small system.
#define MAX_LABELS 1024
#define MAX_VECTORS 256

typedef struct {
    char* label;
    uint16_t address;
    int type;
} Label;

// One line of the Vector Segment, once it has been worked out.
typedef struct {
    char* name;        // What it was called, or NULL for a device, which is named by its port.
    uint8_t index;     // Which vector in its table.
    uint16_t base;     // Which table: software or hardware.
    uint16_t handler;  // Where the handler ended up.
    int declaredOnly;  // Named and numbered, with nobody implementing it here.
} VectorEntry;

void freeLabelList();

void freeVectorList();

// Reads the Vector Segment: allocates a number to every named vector, works out which
// vector each device line means, and resolves the handlers. Runs after the labels are
// known, because a handler is named by its label.
void populateVectorTable(intermediateElement *intermediateArray, int arraySize);

// Turns each vector name used as an operand of SWI into the number it was given.
void fillInVectorReferences(intermediateElement *intermediateArray, int arraySize);

int vectorCount();

void populateLabelTable(intermediateElement *intermediateArray, int arraySize);

void fillInLabelAddresses(intermediateElement *intermediateArray, int arraySize);

void populateOutputBuffers(intermediateElement *intermediateArray, int arraySize, uint8_t *Program, int *programCount, uint8_t *Data, int *dataCount);

void writeOutputFile(const char *outputFileName, uint8_t *Program, int programCount, uint8_t *Data, int dataCount);

#endif
