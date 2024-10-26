// Assm-util.h
// Utility functions for the SplitBit Assembler's first pass.
// Written by Anachronaut
// 10/25/2024

#ifndef ASSMUTL_H
#define ASSMUTL_H

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "Assm-util.h"

#define MAX_INCLUDES 128

// Type values.
#define UNKNOWN 0
#define KEYWORD 1
#define INSTRUCTION 2
#define LABEL 3
#define LABEL_DEFINITION 4
#define VALUE 5
#define STRING 6

// Keyword values.
#define KEYWORD_INCLUDE 1
#define KEYWORD_PROGRAM 2
#define KEYWORD_DATA 3

// Destination values.
#define NOWHERE 0
#define PROGRAM 1
#define DATA 2

// For colorful text.
#define RESET "\x1B[0m"
#define RED "\x1B[31m"
#define GREEN "\x1B[32m"
#define YELLOW "\x1B[33m"
#define BLUE "\x1B[34m"
#define MAGENTA "\x1B[35m"
#define CYAN "\x1B[36m"
#define WHITE "\x1B[37m"

typedef struct {
    char* token;
    char* fileName;
    int lineNumber;
    uint8_t byteValue;
    int byteLength;
    uint16_t address;
    int type; // "KEYWORD", "INSTRUCTION" , "LABEL" , "VALUE", "STRING"
    int destination; // "NOWHERE", "PROGRAM", "DATA"
} intermediateElement;

int checkIfKeyword(intermediateElement *currentElement);

int checkIfInstruction(intermediateElement *currentElement);

int checkIfLiteralValue(intermediateElement *currentElement);

int checkIfLabel(intermediateElement *currentElement);

int readToken(intermediateElement *currentElement, FILE *file, int *lineNumber);

#endif
