// firstPass.c
// Functions for the 'first pass' of the SplitBit Assembler.
// The first pass' primary goal is to get all the assembly files loaded into the Intermediate Array.
// Because I want included files to load and assemble in-line with the current file, that needs to be handled at this stage.
// Written by Anachronaut
// 10/25/2024

#include <stdlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include "firstPass.h"
#include "Assm-util.h"
#include "assembly.h"

char *includeList[MAX_INCLUDES];
int includeCount = 0;

void freeIncludeList() {
    for (int i = 0; i < includeCount; i++) {
        if (includeList[i]) {
            free(includeList[i]);
        }
    }
    includeCount = 0;
}

int isFileIncluded(const char *fileName) {
    for (int i = 0; i < includeCount; i++) {
        if (strcmp(includeList[i], fileName) == 0) {
            return 1;
        }
    }
    return 0;
}

void addIncludedFile(const char *fileName) {
    if (includeCount < MAX_INCLUDES) {
        includeList[includeCount] = strdup(fileName);
        includeCount++;
    } else {
        fprintf(stderr, RED "Error: Too many included files.\n" RESET);
        exit(1);
    }
}

int loadFile(intermediateElement *intermediateArray, char *fileName, int *intermediateIndex, size_t *arraySize){
    // Initial setup.
    addIncludedFile(fileName);
    int status = NOWHERE;
    int lineNumber = 1; // Line numbers start at 1.
    // Open the file.
    FILE *file = fopen(fileName, "r");
    if (!file) {
        fprintf(stderr, RED "Error: Couldn't open file \"%s\"\n" RESET, fileName);
        exit(1);
    }
    // Read off tokens.
    while (readToken(&intermediateArray[*intermediateIndex], file, &lineNumber)) {
        if (*intermediateIndex >= *arraySize - 1) {
            *arraySize *= 2;  // Double the size of the array
            intermediateArray = realloc(intermediateArray, *arraySize * sizeof(intermediateElement));
            if (!intermediateArray) {
                fprintf(stderr, RED "Error: Memory reallocation failed.\n" RESET);
                exit(1);
            }
        }
        //printf("Token number %d\n", intermediateIndex);
        // Go ahead and mark what we already know about this token.
        intermediateArray[*intermediateIndex].fileName = fileName;
        intermediateArray[*intermediateIndex].lineNumber = lineNumber;
        // Take a look at it and determine what it is.
        int testValue = checkIfKeyword(&intermediateArray[*intermediateIndex]);
        if(testValue > 0) {
            switch (testValue){
                case KEYWORD_INCLUDE:
                    // We need to load another file and process it before continuing.
                    status = NOWHERE;
                    // Get the filename and load up the file.
                    (*intermediateIndex)++;
                    readToken(&intermediateArray[*intermediateIndex], file, &lineNumber);
                    char *includeFile = intermediateArray[*intermediateIndex].token;
                    if (isFileIncluded(includeFile)) {
                        fprintf(stderr, RED "Error: File %s is included more than once.\n" RESET, includeFile);
                        printf(" File: %s at line %d.\n", fileName, lineNumber);
                        exit(1);
                    }
                    loadFile(intermediateArray, includeFile, intermediateIndex, arraySize);
                break;
                case KEYWORD_PROGRAM:
                    // Set the state PROGRAM so we mark additional tokens for inclusion into Program Memory.
                    status = PROGRAM;
                break;
                case KEYWORD_DATA:
                    // Set the state to DATA so we mark additional tokens for inclusion into Data Memory.
                    status = DATA;
                break;
            }
        // Next, check to see if it's an instruction.
        } else if (checkIfInstruction(&intermediateArray[*intermediateIndex])) {
            // We should check if we're set up to mark this for the Program Segment.
            if (status != PROGRAM) {
                fprintf(stderr, RED "Error: Attempting to assemble outside the Program Segment.\n Did you forget to use the #Program keyword?\n" RESET);
                printf(" File: %s at line %d.\n", fileName, lineNumber);
                exit(1);
            }
        // Next, check if it's a literal value.
        } else if (checkIfLiteralValue(&intermediateArray[*intermediateIndex])) {
            // We should check to make sure we have a destination for it.
            if (status == NOWHERE) {
                fprintf(stderr, RED "Error: Attempting to write a value to nowhere!\n Did you forget to use the #Program or #Data keyword?\n" RESET);
                printf(" File: %s at line %d.\n", fileName, lineNumber);
                exit(1);
            }
        // Finally, check if it's a label or label definition.
        // First, make sure it hasn't already been marked as a string literal.
        } else if (intermediateArray[*intermediateIndex].type != STRING) {
            if (checkIfLabel(&intermediateArray[*intermediateIndex])) {
                if (status == NOWHERE) {
                    fprintf(stderr, RED "Error: Attempting to create or use a label nowhere!\n Did you forget to use the #Program or #Data keyword?\n" RESET);
                    printf(" File: %s at line %d.\n", fileName, lineNumber);
                    exit(1);
                }
            }
        }
        intermediateArray[*intermediateIndex].destination = status;
        (*intermediateIndex)++;
    }
    return 0;
}
