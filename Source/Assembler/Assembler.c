 // Assembler.c
// Basic Assembler for programs written for the SplitBit CPU
// Written by Anachronaut
// 10/18/2024

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <libgen.h>
#include "Assm-util.h"
#include "firstPass.h"
#include "secondPass.h"

int programLength = 0;
int dataLength = 0;

uint8_t Program[0xFFFF], Data[0xFFFF];


char* createOutputFileName(const char *inputFilePath) {
    // Make a copy of inputFilePath, since basename may modify it
    char *pathCopy = strdup(inputFilePath);
    if (!pathCopy) {
        fprintf(stderr, "Error: Memory allocation failed for path copy.\n");
        exit(1);
    }

    // Get the filename from the path
    char *fileName = basename(pathCopy);

    // Find the length of the filename
    size_t len = strlen(fileName);

    // Check if the filename ends with ".asm"
    char *outputFileName;
    if (len > 4 && strcmp(fileName + len - 4, ".asm") == 0) {
        // Allocate memory for the new file name with ".bin" extension
        outputFileName = malloc(len - 4 + 5);  // Remove ".asm" (4 chars) and add ".bin" (4 chars + null terminator)
        if (!outputFileName) {
            fprintf(stderr, "Error: Memory allocation failed for output file name.\n");
            free(pathCopy);
            exit(1);
        }
        // Copy the filename up to ".asm" and add ".bin"
        strncpy(outputFileName, fileName, len - 4);
        strcpy(outputFileName + len - 4, ".bin");
    } else {
        // If there's no ".asm" extension, add ".bin" to the full filename
        outputFileName = malloc(len + 5);  // Original length + ".bin" + null terminator
        if (!outputFileName) {
            fprintf(stderr, "Error: Memory allocation failed for output file name.\n");
            free(pathCopy);
            exit(1);
        }
        strcpy(outputFileName, fileName);
        strcat(outputFileName, ".bin");
    }

    free(pathCopy);  // Free the temporary path copy
    return outputFileName;
}

// Remember to be a good programmer and free up all the allocated memory.
void assemblerCleanup(intermediateElement *intermediateArray, int arraySize, char *outputFileName) {
    // Free each token in intermediateArray.
    for (int i = 0; i < arraySize; i++) {
        if (intermediateArray[i].token) {
            free(intermediateArray[i].token);
        }
    }
    // Free the intermediateArray itself.
    free(intermediateArray);
    // Free the list of included files.
    freeIncludeList();
    // Free the list of labels.
    freeLabelList();
    // Free the output file name.
    free(outputFileName);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        exit(1);
    }
    // Allocate initial space for the intermediate array.
    size_t arraySize = 1024;
    intermediateElement *intermediateArray = malloc(arraySize * sizeof(intermediateElement));
    if (!intermediateArray) {
        fprintf(stderr, RED "Error: Memory allocation failed.\n" RESET);
        exit(1);
    }

    char *fileName = argv[1];
    int index = 0;
    loadFile(intermediateArray, fileName, &index, &arraySize);
    populateLabelTable(intermediateArray, index);
    fillInLabelAddresses(intermediateArray, index);
    populateOutputBuffers(intermediateArray, index, Program, &programLength, Data, &dataLength);
    char *outputFileName = createOutputFileName(fileName);
    writeOutputFile(outputFileName, Program, programLength, Data, dataLength);
    assemblerCleanup(intermediateArray, index, outputFileName);
    return 0;
}

