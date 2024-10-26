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

int debug = 0;

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
    strncpy(token, currentElement->token, sizeof(token)-1); //copying over one less than the total size of the buffer ensures we wind up with a null terminated string.
    toUppercase(token);
    if (getOpcode(token) != 0xFE) {
        // It's a valid instruction, save its value and set its type.
        currentElement->type = INSTRUCTION;
        currentElement->byteValue = getOpcode(token);
        currentElement->byteLength = 1;
        if (debug) printf("Token: %s is an instruction.\n", currentElement->token);
        return 1;
    }
    return 0;
}

int checkIfLiteralValue(intermediateElement *currentElement) {
    char token[32];
    strncpy(token, currentElement->token, sizeof(token)-1);
    if (token[0] == '0') {
        // It's a literal value. Check if it's hex or dec.
        if(token[1] == 'x') {
            // It's a hex literal. Set its value and type.
            currentElement->type = VALUE;
            currentElement->byteLength = 1;
            memmove(token, token + 2, strlen(token)); // Shift the string over to get rid of the 0x.
            currentElement->byteValue = (uint8_t)strtol(token, NULL, 16);
            if (debug) printf("Token: %s is a hexadecimal literal. \n", currentElement->token);
        } else if (token[1] == 'd') {
            // It's a decimal literal. Set its value and type.
            currentElement->type = VALUE;
            currentElement->byteLength = 1;
            memmove(token, token + 2, strlen(token)); // Shift the string over to get rid of the 0d.
            currentElement->byteValue = (uint8_t)strtol(token, NULL, 10);
            if (debug) printf("Token: %s is a decimal literal. \n", currentElement->token);
        }
        return 1;
    }
    return 0;
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
            if (i < sizeof(buffer) - 1) {
                buffer[i++] = c;
            } else {
                fprintf(stderr, "Error: String literal too long.\n");
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
        if (i < sizeof(buffer) - 1) {
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
