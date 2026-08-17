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
#include "assembly.h"

#define MAX_INCLUDES 128

// Type values.
#define UNKNOWN 0
#define KEYWORD 1
#define INSTRUCTION 2
#define LABEL 3
#define LABEL_DEFINITION 4
#define VALUE 5
#define STRING 6
// A name from the Vector Segment, used as the operand of SWI. It stands for a vector
// number rather than an address, so it emits one byte where a label emits two.
#define VECTOR_REFERENCE 7
// Zero bytes put down to move the cursor along, from #Reserve. How many is known as
// soon as it is read.
#define PADDING 8
// The same, from #Align, where how many depends on where the cursor has got to. The
// count is worked out in the second pass and the alignment itself is kept in address.
#define ALIGNMENT 9

// Keyword values.
#define KEYWORD_INCLUDE 1
#define KEYWORD_PROGRAM 2
#define KEYWORD_DATA 3
#define KEYWORD_VECTORS 4
#define KEYWORD_ALIGN 5
#define KEYWORD_RESERVE 6
#define KEYWORD_BASE 7

// Destination values.
#define NOWHERE 0
#define PROGRAM 1
#define DATA 2
// The Vector Segment does not become bytes at an address the way the other two do. It
// says which handler belongs to which vector, and the assembler works out the rest.
#define VECTORS 3

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
    uint8_t dataPointer[MAX_DATA_POINTER_OPERANDS]; // Which Data Pointers this instruction works through, if any.
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

// Reads a count written the way a literal is, but allowing the full range of an address
// rather than a single byte. #Align and #Reserve both take one, and neither number is
// ever emitted as a byte, so there is no reason to hold them to a byte's range.
uint16_t readCount(intermediateElement *currentElement, const char *what);

// The same, but zero is allowed. #Base takes one of these: a segment deliberately based
// at the bottom of memory is a thing a program is entitled to say, and saying it out loud
// is how it is told apart from a segment nobody based at all.
uint16_t readAddress(intermediateElement *currentElement, const char *what);

// ---- Where a segment is based ----
//
// A program that says nothing about this is a boot image: both its segments begin at
// zero, and the machine loads them there. A program that gives either segment a base is
// meant to be loaded somewhere else, so it is written out as a loadable program instead,
// with its addresses in front of it and none of the space below them in the file.
//
// Nothing relocates anything, so the base a program is assembled for has to be the one it
// is loaded at.

void setSegmentBase(int segment, uint16_t base);

uint16_t segmentBase(int segment);

// Whether this particular segment was given one. A segment left at zero because nobody
// said otherwise cannot be told from one deliberately based at zero by its value alone,
// and the difference is what the mismatch check below is about.
int segmentBaseWasGiven(int segment);

// Whether either segment was given one, which is what decides the kind of file written.
int programIsLoadable(void);

#endif
