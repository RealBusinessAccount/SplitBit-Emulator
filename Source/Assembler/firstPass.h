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

// Adds a directory to search when an #Include is not found beside the file that
// asked for it. Directories are searched in the order they were added.
void addIncludeDirectory(const char *directory);

// Records a source file and returns the copy the assembler will keep, which is what
// element fileNames point at. Returns NULL if this file has already been included.
char *recordSourceFile(char *path);

// Every source file that went into this assembly, for writing make dependencies.
int sourceFileCount();
const char *sourceFile(int index);

int loadFile(intermediateElement **intermediateArray, char *fileName, int *intermediateIndex, size_t *arraySize);

#endif // FIRSTPASS_H

