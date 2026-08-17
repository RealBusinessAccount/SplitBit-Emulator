// Assm-util.c
// Utility and helper functions for the SplitBit Assembler.
// Written by Anachronaut
// 10/25/2024

#include <stdlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include "Assm-util.h"
#include "assembly.h"
#include "../Emulator/cpu.h" // For DATA_POINTERS, so the CPU stays the one source of truth.

int debug = 0;

static uint16_t segmentBases[3];
static int basesGiven = 0;
// Per segment, because a base of zero that was asked for and a base of zero that was
// never mentioned are different things, and only the second one is likely a mistake.
static int baseGiven[3];

void setSegmentBase(int segment, uint16_t base) {
    segmentBases[segment] = base;
    baseGiven[segment] = 1;
    basesGiven = 1;
}

uint16_t segmentBase(int segment) {
    return segmentBases[segment];
}

int segmentBaseWasGiven(int segment) {
    return baseGiven[segment];
}

int programIsLoadable(void) {
    return basesGiven;
}

void toUppercase(char *str) {
    for (int i = 0; str[i]; i++) {
        str[i] = toupper(str[i]);
    }
}

int checkIfKeyword(intermediateElement *currentElement) {
    if (currentElement->token[0] == '#') {
        if (debug) printf("Token: %s is a keyword.\n", currentElement->token);
        currentElement->type = KEYWORD;
        currentElement->destination = NOWHERE;
        if (strcmp(currentElement->token, "#Include") == 0) {
            return KEYWORD_INCLUDE;
        } else if (strcmp(currentElement->token, "#Program") == 0) {
            // We'll want to remember we encountered this and mark all the additional tokens until we hit another keyword for inclusion in the Program Segment.
            return KEYWORD_PROGRAM;
        } else if (strcmp(currentElement->token, "#Data") == 0) {
            // Same as for #Program, but mark for inclusion in the Data Segment.
            return KEYWORD_DATA;
        } else if (strcmp(currentElement->token, "#Align") == 0) {
            // Puts down as many zero bytes as it takes to reach the next multiple of
            // the number that follows. The file that needs the boundary is then the
            // file that asks for it, rather than relying on whatever came before.
            return KEYWORD_ALIGN;
        } else if (strcmp(currentElement->token, "#Base") == 0) {
            // Says where this segment is loaded, which makes the program a loadable one
            // rather than a boot image.
            return KEYWORD_BASE;
        } else if (strcmp(currentElement->token, "#Reserve") == 0) {
            // Puts down the number of zero bytes that follows, so that a label can
            // stand for a region rather than just its first byte.
            return KEYWORD_RESERVE;
        } else if (strcmp(currentElement->token, "#Vectors") == 0) {
            // Names which handler belongs to which vector. Nothing here is assembled
            // into either segment; it is worked out and written into the vector table.
            return KEYWORD_VECTORS;
        } else {
            // It's a malformed keyword.
            fprintf(stderr, RED "Error: Invalid Keyword \"%s\" in file \"%s\" at line number %d.\n" RESET, currentElement->token, currentElement->fileName, currentElement->lineNumber);
            exit(1);
        }
    }
    // It's not a keyword.
    return 0;
}

int checkIfInstruction(intermediateElement *currentElement) {
    char token[32];
    if (strlen(currentElement->token) >= sizeof(token)) {
        // Longer than any mnemonic could be, so it is not one.
        return 0;
    }
    strcpy(token, currentElement->token);
    toUppercase(token);

    // An instruction that works through a Data Pointer names which one by hanging a
    // selector off the mnemonic, as in LDA.2. LDD and STD move a pointer through a
    // pointer, so they take two, as in LDD.1.0. Split those off before looking the
    // mnemonic up.
    char *selector[MAX_DATA_POINTER_OPERANDS] = { NULL };
    int selectorsGiven = 0;
    char *dot = strchr(token, '.');
    while (dot) {
        *dot = '\0';
        dot++;
        if (selectorsGiven < MAX_DATA_POINTER_OPERANDS) {
            selector[selectorsGiven] = dot;
        }
        selectorsGiven++;
        dot = strchr(dot, '.');
    }

    uint8_t opcode = getOpcode(token);
    if (opcode == 0xFE) {
        // It's not an instruction.
        return 0;
    }

    int selectorsWanted = dataPointerOperands(opcode);
    if (selectorsGiven > selectorsWanted) {
        if (selectorsWanted == 0) {
            fprintf(stderr, RED "Error: %s does not work through a Data Pointer, so it cannot take a selector.\n" RESET, token);
        } else {
            fprintf(stderr, RED "Error: %s takes %d Data Pointer selector(s), but \"%s\" gives %d.\n" RESET, token, selectorsWanted, currentElement->token, selectorsGiven);
        }
        printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
        exit(1);
    }

    currentElement->type = INSTRUCTION;
    currentElement->byteValue = opcode;
    // The selectors are emitted whether or not they were written, so the length is
    // fixed by the instruction. Leaving one off is the same as writing 0.
    currentElement->byteLength = 1 + selectorsWanted;

    for (int i = 0; i < selectorsWanted; i++) {
        currentElement->dataPointer[i] = 0;
        if (i < selectorsGiven && selector[i]) {
            char *end;
            long value = strtol(selector[i], &end, 10);
            if (*selector[i] == '\0' || *end != '\0' || value < 0 || value >= DATA_POINTERS) {
                fprintf(stderr, RED "Error: \"%s\" does not name a Data Pointer.\n Selectors run from 0 to %d.\n" RESET, currentElement->token, DATA_POINTERS - 1);
                printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
                exit(1);
            }
            currentElement->dataPointer[i] = (uint8_t)value;
        }
    }

    if (debug) printf("Token: %s is an instruction with %d selector(s).\n", currentElement->token, selectorsWanted);
    return 1;
}

int checkIfLiteralValue(intermediateElement *currentElement) {
    const char *token = currentElement->token;
    if (token[0] != '0') {
        // It's not a literal value.
        return 0;
    }
    // A leading zero means the programmer was trying to write a literal, so anything
    // malformed from here on is an error. Falling through to the label check instead
    // would quietly emit the wrong number of bytes and shift the rest of the program.
    int base;
    const char *baseName;
    if (token[1] == 'x') {
        base = 16;
        baseName = "hexadecimal";
    } else if (token[1] == 'd') {
        base = 10;
        baseName = "decimal";
    } else {
        fprintf(stderr, RED "Error: Malformed literal value \"%s\".\n Literals must be prefaced with 0x for hexadecimal or 0d for decimal.\n" RESET, token);
        printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
        exit(1);
    }
    // Everything after the prefix has to be a digit in that base.
    const char *digits = token + 2;
    if (*digits == '\0') {
        fprintf(stderr, RED "Error: Literal value \"%s\" has no digits after its prefix.\n" RESET, token);
        printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
        exit(1);
    }
    for (const char *c = digits; *c; c++) {
        if (!(base == 16 ? isxdigit((unsigned char)*c) : isdigit((unsigned char)*c))) {
            fprintf(stderr, RED "Error: \"%c\" is not a %s digit, in literal value \"%s\".\n" RESET, *c, baseName, token);
            printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
            exit(1);
        }
    }
    // The digits are all valid, so the only thing left to get wrong is the range.
    long value = strtol(digits, NULL, base);
    if (value > 255) {
        fprintf(stderr, RED "Error: Literal value \"%s\" is too large to fit in one byte.\n Values must be in the range 0x00 to 0xFF, or 0d0 to 0d255.\n" RESET, token);
        printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
        exit(1);
    }
    currentElement->type = VALUE;
    currentElement->byteLength = 1;
    currentElement->byteValue = (uint8_t)value;
    if (debug) printf("Token: %s is a %s literal. \n", token, baseName);
    return 1;
}

// Shared by readCount and readAddress, which differ only in whether zero is an answer.
// A count of nothing is a typo; an address of zero is the bottom of memory.
static uint16_t readNumber(intermediateElement *currentElement, const char *what, long least) {
    const char *token = currentElement->token;
    int base;
    const char *baseName;
    if (token[0] != '0' || (token[1] != 'x' && token[1] != 'd')) {
        fprintf(stderr, RED "Error: %s needs a number, prefaced with 0x or 0d. Found \"%s\".\n" RESET, what, token);
        printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
        exit(1);
    }
    if (token[1] == 'x') {
        base = 16;
        baseName = "hexadecimal";
    } else {
        base = 10;
        baseName = "decimal";
    }
    const char *digits = token + 2;
    if (*digits == '\0') {
        fprintf(stderr, RED "Error: %s was given \"%s\", which has no digits after its prefix.\n" RESET, what, token);
        printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
        exit(1);
    }
    for (const char *c = digits; *c; c++) {
        if (!(base == 16 ? isxdigit((unsigned char)*c) : isdigit((unsigned char)*c))) {
            fprintf(stderr, RED "Error: \"%c\" is not a %s digit, in \"%s\".\n" RESET, *c, baseName, token);
            printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
            exit(1);
        }
    }
    long value = strtol(digits, NULL, base);
    if (value < least || value > 0xFFFF) {
        fprintf(stderr, RED "Error: %s was given \"%s\". It has to be at least %ld and no more than 0xFFFF.\n" RESET, what, token, least);
        printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
        exit(1);
    }
    return (uint16_t)value;
}

uint16_t readCount(intermediateElement *currentElement, const char *what) {
    return readNumber(currentElement, what, 1);
}

uint16_t readAddress(intermediateElement *currentElement, const char *what) {
    return readNumber(currentElement, what, 0);
}

int checkIfLabel(intermediateElement *currentElement) {
    char *token = currentElement->token;
    int length = strlen(token);
    // Check if the last character is a colon.
    if (token[length - 1] == ':') {
        // It is, so this is a label definition.
        currentElement->type = LABEL_DEFINITION;
        currentElement->destination = NOWHERE;
        if (debug) printf("Token: %s is a label definition.\n", token);
        return 1;
    } else {
        // By process of elimination, if whatever this is wasn't picked up by any of the other checks, it's either a label or is invalid.
        currentElement->type = LABEL;
        currentElement->byteLength = 2;
        if (debug) printf("Token: %s is probably a label?\n", token);
        return 1;
    }
    return 0;
}

int readToken(intermediateElement *currentElement, FILE *file, int *lineNumber) {
    int c;
    char buffer[256];  // Buffer to hold the token temporarily.
    int i = 0;

    // Step 1: Skip whitespace and comments.
    while ((c = fgetc(file)) != EOF) {
        if (isspace(c)) {
            if (c == '\n') (*lineNumber)++;  // Increment line count on newlines.
            continue;  // Skip whitespace
        } else if (c == ';') {
            // A comment: ignore characters until the newline.
            while ((c = fgetc(file)) != EOF && c != '\n');
            if (c == '\n') (*lineNumber)++;  // Increment line count after comment line.
            continue;
        } else {
            break;  // Found a non-whitespace, non-comment character
        }
    }

    // Step 2: Handle EOF
    if (c == EOF) {
        return 0;  // Indicate end of file
    }

    // Step 3: Handle string literals
    if (c == '"') {
        while ((c = fgetc(file)) != EOF && c != '"') {
            if (i < (int)(sizeof(buffer) - 1)) {
                buffer[i++] = c;
            } else {
                // Say the limit and where it was met. A string long enough to reach this
                // is usually several lines of help text, and "too long" on its own leaves
                // somebody counting characters to find out by how much.
                fprintf(stderr, RED "Error: String literal longer than %d characters.\n"
                        " Every string carries its own zero byte, so two written in a row"
                        " are two strings\n rather than one long one. Give each its own"
                        " label and print them one after another.\n" RESET,
                        (int)(sizeof(buffer) - 1));
                printf(" File: %s at line %d.\n", currentElement->fileName, *lineNumber);
                exit(1);
            }
        }

        buffer[i] = '\0';  // Null-terminate the string

        // Store in intermediateElement and set type
        currentElement->token = strdup(buffer);
        currentElement->type = STRING;
        currentElement->byteLength = strlen(currentElement->token)+1;
        if (debug) printf("Token: %s is a string literal.\n", currentElement->token);
        return 1;  // Success
    }

    // Step 4: Handle non-string tokens
    ungetc(c, file);  // Put the first character back
    while ((c = fgetc(file)) != EOF && !isspace(c) && c != ';') {
        if (i < (int)(sizeof(buffer) - 1)) {
            buffer[i++] = c;
        } else {
            fprintf(stderr, "Error: Token too long.\n");
            printf(" File: %s at line %d.\n", currentElement->fileName, currentElement->lineNumber);
            exit(1);
        }
    }
    buffer[i] = '\0';  // Null-terminate the token

    // Put back the last character if it's not whitespace or EOF
    if (c != EOF && c != ';') {
        ungetc(c, file);
    } else if (c == ';') {
        // Skip remaining characters on this line if a comment starts
        while ((c = fgetc(file)) != EOF && c != '\n');
    }

    // Store the token in intermediateElement and set a default type
    currentElement->token = strdup(buffer);
    currentElement->type = UNKNOWN;

    return 1;  // Success
}
