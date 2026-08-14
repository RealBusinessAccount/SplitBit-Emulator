// secondPass.c
// Functions for the 'second pass' of the SplitBit Assembler.
// The goal here is to resolve the addresses of labels.
// We'll want to abort if the program comes out to greater than the maximum memory for SplitBit.
// We'll also want to abort if there's a label used with no definition.
// Written by Anachronaut
// 10/25/2024

#include <stdlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <stdint.h>
#include "secondPass.h"
#include "Assm-util.h"
#include "assembly.h"

int debugSecondPass = 0;

Label labelArray[MAX_LABELS];
int labelCount = 0;

void freeLabelList() {
    for (int i = 0; i < labelCount; i++) {
        if (labelArray[i].label) {
            free(labelArray[i].label);
        }
    }
    labelCount = 0;
}

void addLabel(char *labelName, uint16_t address, int type) {
    if (labelCount < MAX_LABELS) {
        // Duplicate labelName and remove the trailing colon, if present
        char *cleanedLabel = strdup(labelName);
        int len = strlen(cleanedLabel);
        if (cleanedLabel[len - 1] == ':') {
            cleanedLabel[len - 1] = '\0';  // Remove the colon
        }

        labelArray[labelCount].label = cleanedLabel;
        labelArray[labelCount].address = address;
        labelArray[labelCount].type = type;
        if (debugSecondPass) printf("Added label %s with address %04X\n", labelName, labelArray[labelCount].address);
        labelCount++;
    } else {
        fprintf(stderr, "Error: Too many labels defined.\n");
        exit(1);
    }
}

void populateLabelTable(intermediateElement *intermediateArray, int arraySize) {
    int programCount = 0;
    int dataCount = 0;
    // Loop through the array, if there's a label definition, add it to the label list.
    for (int i = 0; i < arraySize ; i++) {
        if (intermediateArray[i].type == LABEL_DEFINITION) {
            if (intermediateArray[i].destination == PROGRAM) {
                addLabel(intermediateArray[i].token, (uint16_t)programCount, PROGRAM);
            } else {
                addLabel(intermediateArray[i].token, (uint16_t)dataCount, DATA);
            }
        }
        if (intermediateArray[i].destination == PROGRAM) {
            programCount += intermediateArray[i].byteLength;
        } else if (intermediateArray[i].destination == DATA) {
            dataCount += intermediateArray[i].byteLength;
        }
        if (debugSecondPass) printf("Token: %s with byte length %d to destination %d of type %d\n", intermediateArray[i].token ,intermediateArray[i].byteLength, intermediateArray[i].destination, intermediateArray[i].type);

    }
        if (programCount > 0xFFFF ) {
            fprintf(stderr, RED "Error: Program is too long to fit in Program Memory.\n" RESET);
            exit(1);
        }
        if (dataCount > 0xFFFF ) {
            fprintf(stderr, RED "Error: Data is too long to fit in Data Memory.\n" RESET);
            exit(1);
        }
}

int findLabelAddress(const char *labelName) {
    for (int i = 0; i < labelCount; i++) {
        if (strcmp(labelArray[i].label, labelName) == 0) {
            return labelArray[i].address;
        }
    }
    return -1;  // Label not found
}

void fillInLabelAddresses(intermediateElement *intermediateArray, int arraySize) {
    for (int i = 0; i < arraySize; i++) {
        if (intermediateArray[i].type == LABEL) {
            // Look up the label in the label table
            int address = findLabelAddress(intermediateArray[i].token);
            if (address == -1) {
                fprintf(stderr, RED "Error: Undefined label \"%s\".\n" RESET, intermediateArray[i].token);
                printf("File: %s at line %d.\n", intermediateArray[i].fileName, intermediateArray[i].lineNumber);
                exit(1);
            }
            // Assign the found address to the element
            intermediateArray[i].address = address;
        }
    }
}

// Reports the type of the token following index i, or UNKNOWN if there isn't one.
// The operand checks go through this so that an instruction sitting at the very end of
// a program is reported as a missing operand instead of reading off the end of the array.
static int nextTokenType(intermediateElement *intermediateArray, int arraySize, int i) {
    if (i + 1 >= arraySize) {
        return UNKNOWN;
    }
    return intermediateArray[i + 1].type;
}

// Every instruction that reads operand bytes out of Program Memory needs those bytes to
// actually be there. If they aren't, the following instruction gets eaten as an operand
// and everything after it shifts, so these all have to be hard errors.
static void checkOperands(intermediateElement *intermediateArray, int arraySize, int i) {
    uint8_t opcode = intermediateArray[i].byteValue;
    int nextType = nextTokenType(intermediateArray, arraySize, i);
    const char *problem = NULL;

    if (((opcode & 0xF0) == 0x10) && (opcode != 0x1F)) {
        // Branches and CALL take a two byte address, which only a label can supply.
        if (nextType != LABEL) problem = "Branch without label.";
    } else if ((opcode & 0xF0) == 0xD0 || (opcode & 0xF0) == 0xE0) {
        // The instruction is either an input or output and must be followed by a value.
        if (nextType != VALUE) problem = "I/O without destination port.";
    } else if (opcode == 0x26 || opcode == 0x27) {
        // INIA and INIB must be followed by the literal value to load.
        if (nextType != VALUE) problem = "Immediate load without a value to load.";
    } else if (opcode == 0x48 || opcode == 0x49) {
        // DPUP and DPDN must be followed by the literal offset to apply.
        if (nextType != VALUE) problem = "Data Pointer offset without an offset value.";
    } else if (opcode == 0x47) {
        // SETD takes a two byte address, as either a label or a pair of literal bytes.
        if (nextType == VALUE) {
            if (nextTokenType(intermediateArray, arraySize, i + 1) != VALUE) {
                problem = "SETD given one literal byte, but an address is two bytes.";
            }
        } else if (nextType != LABEL) {
            problem = "SETD without an address.";
        }
    }

    if (problem) {
        fprintf(stderr, RED "Error: %s\n" RESET, problem);
        printf("File: %s at line %d.\n", intermediateArray[i].fileName, intermediateArray[i].lineNumber);
        printf("Token: %s\n", intermediateArray[i].token);
        exit(1);
    }
}

void populateOutputBuffers(intermediateElement *intermediateArray, int arraySize, uint8_t *Program, int *programCount, uint8_t *Data, int *dataCount) {
    for (int i = 0; i < arraySize; i++) {
        if (intermediateArray[i].destination == PROGRAM) {
            switch (intermediateArray[i].type) {
                case INSTRUCTION:
                    // Add instruction byte to Program buffer.
                    Program[(*programCount)++] = intermediateArray[i].byteValue;
                    // Instructions that work through a Data Pointer carry a selector
                    // byte naming which one, whether or not the programmer wrote it.
                    for (int d = 0; d < dataPointerOperands(intermediateArray[i].byteValue); d++) {
                        Program[(*programCount)++] = intermediateArray[i].dataPointer[d];
                    }
                    // Make sure any operand bytes this instruction expects are present.
                    checkOperands(intermediateArray, arraySize, i);
                break;
                case VALUE:
                    // Add literal value to Program buffer.
                    Program[(*programCount)++] = intermediateArray[i].byteValue;
                break;
                case LABEL:
                    // Split 16-bit label address into high and low bytes.
                    Program[(*programCount)++] = (intermediateArray[i].address >> 8) & 0xFF;  // High byte
                    Program[(*programCount)++] = intermediateArray[i].address & 0xFF;         // Low byte
                break;
            }
        } else if (intermediateArray[i].destination == DATA) {
            switch (intermediateArray[i].type) {
                case VALUE:
                    // Add literal value to Data buffer.
                    Data[(*dataCount)++] = intermediateArray[i].byteValue;
                break;
                case STRING:
                    // Copy string literal to Data buffer, including null terminator.
                    for (int j = 0; intermediateArray[i].token[j] != '\0'; j++) {
                        Data[(*dataCount)++] = intermediateArray[i].token[j];
                    }
                    Data[(*dataCount)++] = '\0';  // Add null terminator to Data buffer
                break;
                case LABEL:
                    // A label named in the Data Segment puts its address there, which is
                    // how a program lays down a table of addresses for LDD to walk.
                    // Two bytes, most significant first, the same order addresses are
                    // stored in everywhere else.
                    Data[(*dataCount)++] = (intermediateArray[i].address >> 8) & 0xFF;  // High byte
                    Data[(*dataCount)++] = intermediateArray[i].address & 0xFF;         // Low byte
                break;
            }
        }
    }
}

void writeOutputFile(const char *outputFileName, uint8_t *Program, int programCount, uint8_t *Data, int dataCount) {
    FILE *outputFile = fopen(outputFileName, "wb");
    if (!outputFile) {
        fprintf(stderr, RED "Error: Could not open file \"%s\" for writing.\n" RESET, outputFileName);
        exit(1);
    }

    // Write the file header: the magic, the format version, and the features this
    // binary needs from the machine. An emulator that cannot provide one of those
    // features refuses the file rather than running it and going quietly wrong.
    fwrite(SPLITBIT_MAGIC, sizeof(char), SPLITBIT_MAGIC_LENGTH, outputFile);
    fputc(SPLITBIT_FORMAT_VERSION, outputFile);
    uint32_t required = SPLITBIT_FEATURES_REQUIRED;
    for (int i = SPLITBIT_FLAGS_LENGTH - 1; i >= 0; i--) {
        fputc((required >> (i * 8)) & 0xFF, outputFile);  // Most significant byte first.
    }

    // Write the "PRG" header for the program segment
    fwrite("PRG", sizeof(char), SEGMENT_MARKER_LENGTH, outputFile);

    // Write the program segment length as a 2-byte value (big-endian)
    uint16_t programSize = programCount;
    fputc((programSize >> 8) & 0xFF, outputFile);  // High byte
    fputc(programSize & 0xFF, outputFile);         // Low byte

    // Write the Program buffer to the file
    if (fwrite(Program, sizeof(uint8_t), programCount, outputFile) != programCount) {
        fprintf(stderr, RED "Error: Failed to write Program data to file \"%s\".\n" RESET, outputFileName);
        fclose(outputFile);
        exit(1);
    }

    // Write the "DAT" header for the data segment
    fwrite("DAT", sizeof(char), SEGMENT_MARKER_LENGTH, outputFile);

    // Write the data segment length as a 2-byte value (big-endian)
    uint16_t dataSize = dataCount;
    fputc((dataSize >> 8) & 0xFF, outputFile);  // High byte
    fputc(dataSize & 0xFF, outputFile);         // Low byte

    // Write the Data buffer to the file
    if (fwrite(Data, sizeof(uint8_t), dataCount, outputFile) != dataCount) {
        fprintf(stderr, RED "Error: Failed to write Data data to file \"%s\".\n" RESET, outputFileName);
        fclose(outputFile);
        exit(1);
    }

    fclose(outputFile);
    printf("Successfully wrote SplitBit binary to \"%s\".\n", outputFileName);
    printf(GREEN "  Program Segment size: %d bytes.\n  Data Segment size: %d bytes.\n    Total size: %d bytes.\n" RESET, programCount, dataCount, (programCount + dataCount + SPLITBIT_HEADER_BYTES));
}
