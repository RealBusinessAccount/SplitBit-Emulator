// boostrap.c
// Boostrapping Functions for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/16/2024

#include "bootstrap.h"
#include <stdio.h>
#include <string.h>

    int byte = 0;
    const uint8_t HEADER_LENGTH = 3; // Number of bytes for the header.
    const uint8_t LENGTH_SIZE = 2; // Number of bytes for the segment length.

uint32_t readLength(FILE *file) {
    uint16_t length = 0;
    for (int i = 0; i < LENGTH_SIZE; i++) {
        int byte = fgetc(file);
        if (byte == EOF) {
            fprintf(stderr, "Error: Unexpected end of file while reading a segment length.\n");
            return UINT32_MAX;
        }
        length = (length << 8) | (uint8_t)byte;
    }
    return length;
}

uint32_t readHeader(FILE *file, const char *expectedHeader) {
    char header[HEADER_LENGTH];
    for (int i = 0; i < HEADER_LENGTH; i++) {
        int byte = fgetc(file);
        if (byte == EOF) {
            fprintf(stderr, "Error: Unexpected end of file while reading a header.\n");
            return UINT32_MAX;
        }
        header[i] = (uint8_t)byte;
    }
    if (strncmp(header, expectedHeader, 3)) {
        fprintf(stderr, "Error: Bad header.\n");
        printf("Header: %s\nExpected Header: %s\n", header, expectedHeader);
        return UINT32_MAX;
    }
    return 0;
}

uint8_t loadSegment(FILE *file, uint8_t *Memory, uint16_t length) {
    for (int16_t i = 0; i < length; i++) {
        byte = fgetc(file);
        if (byte == EOF) {
            fprintf(stderr, "Error: Unexpected end of file while reading a segment.\n");
            return 1;
        }
        Memory[i] = (uint8_t)byte;
    }
    return 0;
}

uint8_t loadFile(char *path, uint8_t *Program, uint8_t *Data) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "Error: Couldn't open file: %s\n", path);
        return 1;
    }
    // Read the first three bytes and check if they're the PRG header.
    if (readHeader(file, "PRG") == UINT32_MAX) {
        fclose(file);
        return 1;
    }
    // Now we need to get the length of the Program Section.
    uint32_t length = readLength(file);
    if (length == UINT32_MAX) {
        fclose(file);
        return 1;
    }
    // Now we load the Program Segment.
    if (loadSegment(file, Program, (uint16_t)length)) {
        fclose(file);
        return 1;
    }
    // Okay, Program is loaded, now do the same thing but for Data.
    // Check the header.
    if (readHeader(file, "DAT") == UINT32_MAX) {
        return 1;
    }
    // Get the legnth of the Data Section.
    length = readLength(file);
    if (length == UINT32_MAX){
        fclose(file);
        return 1;
    }
    // Now load the Data Section.
    if (loadSegment(file, Data, (uint16_t)length)) {
        fclose(file);
        return 1;
    }
    fclose(file);
    return 0;
}
