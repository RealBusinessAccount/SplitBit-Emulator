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
#include "sbex.h"

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

void addLabel(char *labelName, uint16_t address, int type, const char *fileName, int lineNumber) {
    if (labelCount < MAX_LABELS) {
        // Duplicate labelName and remove the trailing colon, if present
        char *cleanedLabel = strdup(labelName);
        int len = strlen(cleanedLabel);
        if (cleanedLabel[len - 1] == ':') {
            cleanedLabel[len - 1] = '\0';  // Remove the colon
        }

        // A name may only be defined once. Without this check a reference quietly
        // resolves to whichever definition came first, so a typo or a name that two
        // libraries both happen to use is very hard to track down.
        for (int i = 0; i < labelCount; i++) {
            if (strcmp(labelArray[i].label, cleanedLabel) == 0) {
                fprintf(stderr, RED "Error: Label \"%s\" is defined more than once.\n" RESET, cleanedLabel);
                printf("File: %s at line %d.\n", fileName, lineNumber);
                free(cleanedLabel);
                exit(1);
            }
        }

        labelArray[labelCount].label = cleanedLabel;
        labelArray[labelCount].address = address;
        labelArray[labelCount].type = type;
        if (debugSecondPass) printf("Added label %s with address %04X\n", labelName, labelArray[labelCount].address);
        labelCount++;
    } else {
        fprintf(stderr, RED "Error: Too many labels. This program and everything it\n"
                            " includes may define %d between them, and \"%s\" is one too many.\n" RESET,
                MAX_LABELS, labelName);
        printf("File: %s at line %d.\n", fileName, lineNumber);
        exit(1);
    }
}

void populateLabelTable(intermediateElement *intermediateArray, int arraySize) {
    // Counting starts at the base, so a label in a program built to live somewhere else
    // already holds the address it will have once it is there. Nothing relocates
    // anything, which is exactly why this has to be right at assembly time.
    int programCount = segmentBase(PROGRAM);
    int dataCount = segmentBase(DATA);
    // Loop through the array, if there's a label definition, add it to the label list.
    for (int i = 0; i < arraySize ; i++) {
        // How many zeroes an #Align comes to depends on where the cursor has reached,
        // so it can only be worked out here, walking the tokens in order. It has to be
        // settled before the running count moves past it, or every label after it lands
        // in the wrong place.
        if (intermediateArray[i].type == ALIGNMENT) {
            int cursor = (intermediateArray[i].destination == PROGRAM) ? programCount : dataCount;
            int alignment = intermediateArray[i].address;
            intermediateArray[i].byteLength = (alignment - (cursor % alignment)) % alignment;
        }
        if (intermediateArray[i].type == LABEL_DEFINITION && intermediateArray[i].destination != VECTORS) {
            if (intermediateArray[i].destination == PROGRAM) {
                addLabel(intermediateArray[i].token, (uint16_t)programCount, PROGRAM,
                         intermediateArray[i].fileName, intermediateArray[i].lineNumber);
            } else {
                addLabel(intermediateArray[i].token, (uint16_t)dataCount, DATA,
                         intermediateArray[i].fileName, intermediateArray[i].lineNumber);
            }
        }
        if (intermediateArray[i].destination == PROGRAM) {
            programCount += intermediateArray[i].byteLength;
        } else if (intermediateArray[i].destination == DATA) {
            dataCount += intermediateArray[i].byteLength;
        }
        if (debugSecondPass) printf("Token: %s with byte length %d to destination %d of type %d\n", intermediateArray[i].token ,intermediateArray[i].byteLength, intermediateArray[i].destination, intermediateArray[i].type);

    }
        if (programCount > PROGRAM_SEGMENT_LIMIT ) {
            fprintf(stderr, RED "Error: Program is too long to fit in Program Memory.\n"
                                " The Program Segment may not run past 0x%04X, where the vector table begins.\n" RESET,
                                PROGRAM_SEGMENT_LIMIT - 1);
            exit(1);
        }
        if (dataCount > 0xFFFF ) {
            fprintf(stderr, RED "Error: Data is too long to fit in Data Memory.\n" RESET);
            exit(1);
        }
}

// ---- The Vector Segment ----

int findLabelAddress(const char *labelName);

VectorEntry vectorArray[MAX_VECTORS];
int vectorArrayCount = 0;

int vectorCount() {
    return vectorArrayCount;
}

void freeVectorList() {
    for (int i = 0; i < vectorArrayCount; i++) {
        if (vectorArray[i].name) {
            free(vectorArray[i].name);
        }
    }
    vectorArrayCount = 0;
}

// The words the Vector Segment understands. These are spelled without regard to case,
// the way mnemonics are, because they are part of the language rather than names the
// programmer chose.
static int sameWord(const char *a, const char *b) {
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) {
            return 0;
        }
        a++;
        b++;
    }
    return *a == *b;
}

// The vectors that already mean something. Everything else a program names is numbered
// for it, starting above the range held back for faults.
static const struct {
    const char *name;
    uint8_t index;
} reservedVectors[] = {
    { "Boot",           VECTOR_BOOT },
    { "SoftReset",      VECTOR_SOFT_RESET },
    { "BadOpcode",      VECTOR_INVALID_OPCODE },
    { "GuardViolation", VECTOR_GUARD_VIOLATION },
    { "BankFault",      VECTOR_BANK_FAULT },
};
static const int reservedVectorCount = (int)(sizeof(reservedVectors) / sizeof(reservedVectors[0]));

static void vectorError(const char *message, intermediateElement *element) {
    fprintf(stderr, RED "Error: %s\n" RESET, message);
    printf("File: %s at line %d.\n", element->fileName, element->lineNumber);
    printf("Token: %s\n", element->token);
    exit(1);
}

// Whether the token at b is written on the same line as the one at a, and so belongs to
// the same entry. A line is what tells a name with a handler apart from a name on its own.
static int sameLine(intermediateElement *intermediateArray, int a, int b) {
    if (a < 0 || b < 0) {
        return 0;
    }
    return intermediateArray[a].lineNumber == intermediateArray[b].lineNumber
        && intermediateArray[a].fileName == intermediateArray[b].fileName;
}

// The next token belonging to the Vector Segment, or -1 if the segment has run out.
static int nextVectorToken(intermediateElement *intermediateArray, int arraySize, int from) {
    for (int i = from; i < arraySize; i++) {
        if (intermediateArray[i].destination == VECTORS && intermediateArray[i].type != KEYWORD) {
            return i;
        }
    }
    return -1;
}

// A declared vector has a name and a number but no handler, so nothing goes into the
// table for it. It exists so that a program can name a service it calls without claiming
// to implement it, which is what lets one file be included by both sides.
// Where a vector of this name already is, or -1. A name can be met twice: once where it
// is declared and once where somebody supplies its handler.
static int findVector(const char *name) {
    for (int i = 0; i < vectorArrayCount; i++) {
        if (vectorArray[i].name && strcmp(vectorArray[i].name, name) == 0) {
            return i;
        }
    }
    return -1;
}

static void addVector(char *name, uint8_t index, uint16_t base, uint16_t handler,
                      int declaredOnly, intermediateElement *element) {
    if (vectorArrayCount >= MAX_VECTORS) {
        vectorError("Too many vectors defined.", element);
    }
    for (int i = 0; i < vectorArrayCount; i++) {
        if (vectorArray[i].index == index && vectorArray[i].base == base
            && !vectorArray[i].declaredOnly && !declaredOnly) {
            fprintf(stderr, RED "Error: That vector already has a handler.\n" RESET);
            printf("File: %s at line %d.\n", element->fileName, element->lineNumber);
            exit(1);
        }
        if (name && vectorArray[i].name && strcmp(vectorArray[i].name, name) == 0) {
            fprintf(stderr, RED "Error: Vector \"%s\" is named more than once.\n" RESET, name);
            printf("File: %s at line %d.\n", element->fileName, element->lineNumber);
            exit(1);
        }
    }
    vectorArray[vectorArrayCount].name = name ? strdup(name) : NULL;
    vectorArray[vectorArrayCount].index = index;
    vectorArray[vectorArrayCount].base = base;
    vectorArray[vectorArrayCount].handler = handler;
    vectorArray[vectorArrayCount].declaredOnly = declaredOnly;
    vectorArrayCount++;
}

// Resolves the handler named by the token at the given index.
static uint16_t resolveHandler(intermediateElement *intermediateArray, int at, const char *what) {
    if (at < 0) {
        fprintf(stderr, RED "Error: %s is not followed by a handler to go to.\n" RESET, what);
        exit(1);
    }
    if (intermediateArray[at].type != LABEL) {
        vectorError("A vector's handler has to be named by a label.", &intermediateArray[at]);
    }
    int address = findLabelAddress(intermediateArray[at].token);
    if (address == -1) {
        vectorError("That handler does not exist.", &intermediateArray[at]);
    }
    return (uint16_t)address;
}

// Is anything already using this software vector number?
static int vectorNumberTaken(uint8_t index) {
    for (int i = 0; i < vectorArrayCount; i++) {
        if (vectorArray[i].base == SOFTWARE_VECTOR_BASE && vectorArray[i].index == index) {
            return 1;
        }
    }
    return 0;
}

void populateVectorTable(intermediateElement *intermediateArray, int arraySize) {
    // Software vectors a program names for itself and does not pin are numbered in the
    // order they are written, from the automatic range. A programmer never types one of
    // these, so there is no way to land on a reserved vector or on somebody else's
    // agreed number by accident.
    int nextFreeVector = VECTOR_FIRST_AUTO;

    int i = nextVectorToken(intermediateArray, arraySize, 0);
    while (i >= 0) {
        char *token = intermediateArray[i].token;

        if (sameWord(token, "Device")) {
            // A device is named by the port it is plugged into, because that is what
            // decides which vector it arrives through. There is nothing to allocate.
            int portToken = nextVectorToken(intermediateArray, arraySize, i + 1);
            if (portToken < 0 || intermediateArray[portToken].type != VALUE) {
                vectorError("Device has to say which port, as a number.", &intermediateArray[i]);
            }
            int handlerToken = nextVectorToken(intermediateArray, arraySize, portToken + 1);
            uint16_t handler = resolveHandler(intermediateArray, handlerToken, "Device");
            addVector(NULL, intermediateArray[portToken].byteValue, HARDWARE_VECTOR_BASE,
                      handler, 0, &intermediateArray[i]);
            i = nextVectorToken(intermediateArray, arraySize, handlerToken + 1);
            continue;
        }

        // A number on the same line, between the name and any handler, PINS the vector.
        // Nothing else can appear there: a label may not begin with a digit, so a value in
        // this position is a number and can be nothing else.
        int after = nextVectorToken(intermediateArray, arraySize, i + 1);
        int pinned = -1;
        if (sameLine(intermediateArray, i, after) && intermediateArray[after].type == VALUE) {
            pinned = intermediateArray[after].byteValue;
            after = nextVectorToken(intermediateArray, arraySize, after + 1);
        }
        int handlerToken = after;
        int hasHandler = sameLine(intermediateArray, i, handlerToken);
        int already = findVector(token);

        if (already >= 0) {
            // Met before. A handler now is somebody implementing what was declared
            // earlier, which is how one shared file can serve both sides.
            //
            // A number here has to be the one it was declared with. Saying it again is
            // allowed, because an implementer repeating what it is implementing is
            // harmless; saying a different one means the two sides disagree about which
            // vector this is, which is the whole thing pinning exists to prevent.
            if (pinned >= 0 && pinned != vectorArray[already].index) {
                vectorError("That vector was already given a different number.",
                            &intermediateArray[i]);
            }
            if (!hasHandler) {
                vectorError("That vector is declared more than once.", &intermediateArray[i]);
            }
            if (!vectorArray[already].declaredOnly) {
                vectorError("That vector already has a handler.", &intermediateArray[i]);
            }
            vectorArray[already].handler = resolveHandler(intermediateArray, handlerToken, token);
            vectorArray[already].declaredOnly = 0;
            i = nextVectorToken(intermediateArray, arraySize, handlerToken + 1);
            continue;
        }

        uint8_t index;
        int reserved = 0;
        for (int r = 0; r < reservedVectorCount; r++) {
            if (sameWord(token, reservedVectors[r].name)) {
                index = reservedVectors[r].index;
                reserved = 1;
                break;
            }
        }
        if (reserved && pinned >= 0) {
            // Boot, SoftReset and BadOpcode are where the machine looks, not where a
            // program says to look, so their numbers are not anybody's to choose.
            vectorError("That vector's number is fixed by the machine and cannot be given.",
                        &intermediateArray[i]);
        }
        if (!reserved && pinned >= 0) {
            if (pinned < VECTOR_FIRST_PINNED || pinned >= VECTOR_FIRST_AUTO) {
                fprintf(stderr, RED "Error: %d is not a vector number that can be given.\n"
                                    " Numbers below %d belong to the machine, and %d and up are\n"
                                    " handed out by the assembler. A vector two programs have to\n"
                                    " agree about takes one from %d to %d.\n" RESET,
                        pinned, VECTOR_FIRST_PINNED, VECTOR_FIRST_AUTO,
                        VECTOR_FIRST_PINNED, VECTOR_FIRST_AUTO - 1);
                printf("File: %s at line %d.\n",
                       intermediateArray[i].fileName, intermediateArray[i].lineNumber);
                exit(1);
            }
            if (vectorNumberTaken((uint8_t)pinned)) {
                vectorError("Another vector already has that number.", &intermediateArray[i]);
            }
            index = (uint8_t)pinned;
        } else if (!reserved) {
            if (nextFreeVector > 255) {
                vectorError("There are no software vectors left to give this one.", &intermediateArray[i]);
            }
            index = (uint8_t)nextFreeVector;
            nextFreeVector++;
        }

        if (!hasHandler) {
            // Nothing follows it on the line, so this says what the vector is called and
            // what number it has, and leaves implementing it to somebody else.
            addVector(token, index, SOFTWARE_VECTOR_BASE, 0, 1, &intermediateArray[i]);
            i = handlerToken;
            continue;
        }
        uint16_t handler = resolveHandler(intermediateArray, handlerToken, token);
        addVector(token, index, SOFTWARE_VECTOR_BASE, handler, 0, &intermediateArray[i]);
        i = nextVectorToken(intermediateArray, arraySize, handlerToken + 1);
    }
}

void fillInVectorReferences(intermediateElement *intermediateArray, int arraySize) {
    for (int i = 0; i < arraySize; i++) {
        if (intermediateArray[i].type != VECTOR_REFERENCE) {
            continue;
        }
        int found = 0;
        for (int v = 0; v < vectorArrayCount; v++) {
            if (vectorArray[v].name && strcmp(vectorArray[v].name, intermediateArray[i].token) == 0) {
                if (vectorArray[v].base != SOFTWARE_VECTOR_BASE) {
                    vectorError("SWI can only reach a software vector.", &intermediateArray[i]);
                }
                intermediateArray[i].byteValue = vectorArray[v].index;
                found = 1;
                break;
            }
        }
        if (!found) {
            fprintf(stderr, RED "Error: \"%s\" is not a vector.\n Names used with SWI have to be given a handler in a #Vectors section.\n" RESET,
                    intermediateArray[i].token);
            printf("File: %s at line %d.\n", intermediateArray[i].fileName, intermediateArray[i].lineNumber);
            exit(1);
        }
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
        // The Vector Segment is resolved separately. Most of what it holds is not a
        // label at all: the words that name a vector are the segment's own, and looking
        // them up here would report them as undefined.
        if (intermediateArray[i].destination == VECTORS) {
            continue;
        }
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

    // Listed rather than matched on the high nibble, because not every instruction in
    // the branch block takes an address: RET has none, and BRD gets its destination
    // from a Data Pointer instead of from the program.
    if (opcode == 0x10 || opcode == 0x11 || opcode == 0x12 ||
        opcode == 0x13 || opcode == 0x14 || opcode == 0x17 ||
        opcode == 0x1A || opcode == 0x1B || opcode == 0x1C || opcode == 0x1D) {
        // Branches and CALL take a two byte address, which only a label can supply.
        if (nextType != LABEL) problem = "Branch without label.";
    } else if ((opcode & 0xF0) == 0xD0 || (opcode & 0xF0) == 0xE0) {
        // The instruction is either an input or output and must be followed by a value.
        if (nextType != VALUE) problem = "I/O without destination port.";
    } else if (opcode == 0x18) {
        // SWI names a vector, either by the name it was given in the Vector Segment or,
        // rarely, as a literal number. Without one it swallows whatever follows it and
        // every address after that shifts.
        if (nextType != VECTOR_REFERENCE && nextType != VALUE) problem = "SWI without a vector to go to.";
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
                case VECTOR_REFERENCE:
                    // A vector is a number rather than a place, so this is one byte
                    // where a label would be two.
                    Program[(*programCount)++] = intermediateArray[i].byteValue;
                break;
                case PADDING:
                case ALIGNMENT:
                    for (int z = 0; z < intermediateArray[i].byteLength; z++) {
                        Program[(*programCount)++] = 0x00;
                    }
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
                case PADDING:
                case ALIGNMENT:
                    for (int z = 0; z < intermediateArray[i].byteLength; z++) {
                        Data[(*dataCount)++] = 0x00;
                    }
                break;
            }
        }
    }
}

// A loadable program: sixteen bytes saying where it belongs, then the code and the data.
// The space below each base is not written out, because nothing needs to carry it: the
// header says where the bytes go and the loader puts them there.
static void writeLoadable(const char *outputFileName, uint8_t *Program, int programCount,
                          uint8_t *Data, int dataCount) {
    uint16_t codeBase = segmentBase(PROGRAM);
    uint16_t dataBase = segmentBase(DATA);
    int codeLength = programCount - codeBase;
    int dataLength = dataCount - dataBase;
    if (codeLength < 0) codeLength = 0;
    if (dataLength < 0) dataLength = 0;

    FILE *outputFile = fopen(outputFileName, "wb");
    if (!outputFile) {
        fprintf(stderr, RED "Error: Could not open file \"%s\" for writing.\n" RESET, outputFileName);
        exit(1);
    }
    // Boot says where a program begins, which is what the entry field holds, so in a
    // loadable program that line fills it in. It is NOT installed as vector 0: that entry
    // is where the whole machine starts, and a program being loaded into a running system
    // has no business saying anything about that.
    //
    // Without a Boot line the entry is the first byte of the code, which is where a
    // program begins if it does not say otherwise.
    uint16_t entry = codeBase;
    int installed = 0;
    for (int i = 0; i < vectorArrayCount; i++) {
        if (vectorArray[i].declaredOnly) {
            continue;
        }
        if (vectorArray[i].base == SOFTWARE_VECTOR_BASE
            && vectorArray[i].index == VECTOR_BOOT) {
            entry = vectorArray[i].handler;
            continue;
        }
        installed++;
    }
    if (installed > 255) {
        fprintf(stderr, RED "Error: A loadable program may bring at most 255 vectors.\n" RESET);
        exit(1);
    }

    uint8_t header[SBEX_HEADER_BYTES];
    memset(header, 0, sizeof(header));
    memcpy(header, SBEX_MAGIC, SBEX_MAGIC_BYTES);
    // A program that brings vectors needs something of its loader that a version one
    // loader does not know how to give, so it says so, and an older one refuses it rather
    // than running it without them.
    header[SBEX_VERSION_AT] = installed > 0 ? SBEX_VERSION_VECTORS : SBEX_VERSION;
    header[SBEX_VECTORS_AT] = (uint8_t)installed;
    header[SBEX_CODE_AT] = (uint8_t)(codeBase >> 8);
    header[SBEX_CODE_AT + 1] = (uint8_t)(codeBase & 0xFF);
    header[SBEX_ENTRY_AT] = (uint8_t)(entry >> 8);
    header[SBEX_ENTRY_AT + 1] = (uint8_t)(entry & 0xFF);
    header[SBEX_CODE_LEN_AT] = (uint8_t)(codeLength >> 8);
    header[SBEX_CODE_LEN_AT + 1] = (uint8_t)(codeLength & 0xFF);
    header[SBEX_DATA_AT] = (uint8_t)(dataBase >> 8);
    header[SBEX_DATA_AT + 1] = (uint8_t)(dataBase & 0xFF);
    header[SBEX_DATA_LEN_AT] = (uint8_t)(dataLength >> 8);
    header[SBEX_DATA_LEN_AT + 1] = (uint8_t)(dataLength & 0xFF);
    fwrite(header, 1, sizeof(header), outputFile);
    fwrite(Program + codeBase, 1, (size_t)codeLength, outputFile);
    fwrite(Data + dataBase, 1, (size_t)dataLength, outputFile);

    // The vectors, last, so that everything before them sits where a version one loader
    // already expects to find it.
    for (int i = 0; i < vectorArrayCount; i++) {
        if (vectorArray[i].declaredOnly) {
            continue;
        }
        if (vectorArray[i].base == SOFTWARE_VECTOR_BASE
            && vectorArray[i].index == VECTOR_BOOT) {
            continue;
        }
        uint16_t slot = vectorArray[i].base + (uint16_t)vectorArray[i].index * VECTOR_ENTRY_BYTES;
        fputc((slot >> 8) & 0xFF, outputFile);
        fputc(slot & 0xFF, outputFile);
        fputc((vectorArray[i].handler >> 8) & 0xFF, outputFile);
        fputc(vectorArray[i].handler & 0xFF, outputFile);
    }
    fclose(outputFile);
    printf("Successfully wrote SplitBit loadable program to \"%s\".\n", outputFileName);
    printf(GREEN "  Code: %d bytes at 0x%04X.\n  Data: %d bytes at 0x%04X.\n" RESET,
           codeLength, codeBase, dataLength, dataBase);
    if (entry != codeBase) {
        printf(GREEN "  Starts at 0x%04X.\n" RESET, entry);
    }
    if (installed > 0) {
        printf(GREEN "  Vectors: %d. Version 2, so a loader that cannot install them will say so.\n" RESET,
               installed);
    }
    printf(GREEN "    Total size: %d bytes.\n" RESET,
           SBEX_HEADER_BYTES + codeLength + dataLength + installed * SBEX_VECTOR_ENTRY_BYTES);
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
    if (fwrite(Program, sizeof(uint8_t), programCount, outputFile) != (size_t)programCount) {
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
    if (fwrite(Data, sizeof(uint8_t), dataCount, outputFile) != (size_t)dataCount) {
        fprintf(stderr, RED "Error: Failed to write Data data to file \"%s\".\n" RESET, outputFileName);
        fclose(outputFile);
        exit(1);
    }

    // A program with a base is one meant to be loaded, so it is written out with its
    // addresses in front of it and nothing below them. A boot image carries the padding
    // because the machine loads it at zero; a loadable one would only be carrying space
    // it does not use.
    if (programIsLoadable()) {
        fclose(outputFile);
        writeLoadable(outputFileName, Program, programCount, Data, dataCount);
        return;
    }

    // The Vector Segment, only if the program named any. Leaving it out entirely is
    // what lets a binary written before vectors existed still load: the reader treats
    // the end of the file as an empty table rather than a missing one.
    int installed = 0;
    for (int i = 0; i < vectorArrayCount; i++) {
        if (!vectorArray[i].declaredOnly) {
            installed++;
        }
    }
    int vectorBytes = 0;
    if (installed > 0) {
        fwrite("VEC", sizeof(char), SEGMENT_MARKER_LENGTH, outputFile);
        vectorBytes = installed * VECTOR_ENTRY_FILE_BYTES;
        fputc((vectorBytes >> 8) & 0xFF, outputFile);
        fputc(vectorBytes & 0xFF, outputFile);
        for (int i = 0; i < vectorArrayCount; i++) {
            if (vectorArray[i].declaredOnly) {
                continue;
            }
            uint16_t slot = vectorArray[i].base + (uint16_t)vectorArray[i].index * VECTOR_ENTRY_BYTES;
            fputc((slot >> 8) & 0xFF, outputFile);
            fputc(slot & 0xFF, outputFile);
            fputc((vectorArray[i].handler >> 8) & 0xFF, outputFile);
            fputc(vectorArray[i].handler & 0xFF, outputFile);
        }
    }

    fclose(outputFile);
    printf("Successfully wrote SplitBit binary to \"%s\".\n", outputFileName);
    printf(GREEN "  Program Segment size: %d bytes.\n  Data Segment size: %d bytes.\n" RESET, programCount, dataCount);
    if (installed > 0) {
        printf(GREEN "  Vectors: %d.\n" RESET, installed);
    }
    printf(GREEN "    Total size: %d bytes.\n" RESET,
           (programCount + dataCount + SPLITBIT_HEADER_BYTES
            + (installed > 0 ? SEGMENT_MARKER_LENGTH + SEGMENT_LENGTH_BYTES + vectorBytes : 0)));
}
