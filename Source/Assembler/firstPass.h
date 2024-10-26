// firstPass.h
// Utility functions for the SplitBit Assembler.
// Written by Anachronaut
// 10/22/2024

#ifndef FIRSTPASS_H
#define FIRSTPASS_H

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "Assm-util.h"

void freeIncludeList();

int loadFile(intermediateElement *intermediateArray, char *fileName, int *intermediateIndex, size_t *arraySize);

#endif // FIRSTPASS_H

