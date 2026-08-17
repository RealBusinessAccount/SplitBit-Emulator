// firstPass.c
// Functions for the 'first pass' of the SplitBit Assembler.
// The first pass' primary goal is to get all the assembly files loaded into the Intermediate Array.
// Because I want included files to load and assemble in-line with the current file, that needs to be handled at this stage.
// Written by Anachronaut
// 10/25/2024

#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <libgen.h>
#include <limits.h>
#include "firstPass.h"
#include "Assm-util.h"
#include "assembly.h"

// Each source file that has gone into this assembly. The path is kept as it was
// written, because that is what reads well in an error message or a dependency
// rule. The canonical form is kept alongside it so that the same file reached by
// two different routes is recognised as one file and included only once.
typedef struct {
    char *path;
    char *canonical;
} SourceFile;

SourceFile includeList[MAX_INCLUDES];
int includeCount = 0;

char *includeDirectories[MAX_INCLUDES];
int includeDirectoryCount = 0;

void freeIncludeList() {
    for (int i = 0; i < includeCount; i++) {
        free(includeList[i].path);
        free(includeList[i].canonical);
    }
    includeCount = 0;
    for (int i = 0; i < includeDirectoryCount; i++) {
        free(includeDirectories[i]);
    }
    includeDirectoryCount = 0;
}

void addIncludeDirectory(const char *directory) {
    if (includeDirectoryCount >= MAX_INCLUDES) {
        fprintf(stderr, RED "Error: Too many include directories.\n" RESET);
        exit(1);
    }
    includeDirectories[includeDirectoryCount] = strdup(directory);
    includeDirectoryCount++;
}

int sourceFileCount() {
    return includeCount;
}

const char *sourceFile(int index) {
    return includeList[index].path;
}

char *recordSourceFile(char *path) {
    // realpath resolves symlinks and things like "..", so that Libraries/print.asm
    // and ../Libraries/print.asm are known to be the same file.
    char *canonical = realpath(path, NULL);
    if (!canonical) {
        canonical = strdup(path);
    }
    for (int i = 0; i < includeCount; i++) {
        if (strcmp(includeList[i].canonical, canonical) == 0) {
            // Already assembled once. Including it again is not an error, it just
            // does nothing, which is what lets two libraries share a dependency.
            free(canonical);
            free(path);
            return NULL;
        }
    }
    if (includeCount >= MAX_INCLUDES) {
        fprintf(stderr, RED "Error: Too many included files.\n" RESET);
        exit(1);
    }
    includeList[includeCount].path = path;
    includeList[includeCount].canonical = canonical;
    includeCount++;
    return path;
}

// Joins a directory and a file name into a newly allocated path.
static char *joinPath(const char *directory, const char *name) {
    if (!directory || directory[0] == '\0' || strcmp(directory, ".") == 0) {
        return strdup(name);
    }
    size_t length = strlen(directory) + 1 + strlen(name) + 1;
    char *joined = malloc(length);
    if (!joined) {
        fprintf(stderr, RED "Error: Memory allocation failed.\n" RESET);
        exit(1);
    }
    snprintf(joined, length, "%s/%s", directory, name);
    return joined;
}

static int fileExists(const char *path) {
    FILE *file = fopen(path, "r");
    if (file) {
        fclose(file);
        return 1;
    }
    return 0;
}

// Works out where an #Include actually points. An absolute path is taken as given.
// Otherwise the file is looked for beside the file that asked for it, so that a
// library including its own siblings needs no help, and then along the include
// directories in the order they were given. Returns NULL if it is nowhere.
static char *resolveInclude(const char *includingFile, const char *requested) {
    if (requested[0] == '/') {
        return fileExists(requested) ? strdup(requested) : NULL;
    }

    char *copy = strdup(includingFile);
    char *candidate = joinPath(dirname(copy), requested);
    free(copy);
    if (fileExists(candidate)) {
        return candidate;
    }
    free(candidate);

    for (int i = 0; i < includeDirectoryCount; i++) {
        candidate = joinPath(includeDirectories[i], requested);
        if (fileExists(candidate)) {
            return candidate;
        }
        free(candidate);
    }
    return NULL;
}

// Says where the assembler looked, so that a missing include is easy to fix.
static void reportMissingInclude(const char *includingFile, const char *requested, int lineNumber) {
    fprintf(stderr, RED "Error: Couldn't find included file \"%s\".\n" RESET, requested);
    printf(" File: %s at line %d.\n", includingFile, lineNumber);
    printf(" Looked for it:\n");
    char *copy = strdup(includingFile);
    printf("   beside %s\n", includingFile);
    free(copy);
    for (int i = 0; i < includeDirectoryCount; i++) {
        printf("   in %s\n", includeDirectories[i]);
    }
    if (includeDirectoryCount == 0) {
        printf("   and nowhere else, because no include directories were given with -I.\n");
    }
}

int loadFile(intermediateElement **intermediateArray, char *fileName, int *intermediateIndex, size_t *arraySize){
    // fileName is a path already resolved and recorded by the caller, and the copy
    // the include list owns, so element fileNames can safely point at it.
    int status = NOWHERE;
    // A base has to come before anything else in its segment, so this remembers whether
    // that segment has had anything put in it yet.
    static int segmentUsed[3] = {0, 0, 0};
    int lineNumber = 1; // Line numbers start at 1.
    // Open the file.
    FILE *file = fopen(fileName, "r");
    if (!file) {
        fprintf(stderr, RED "Error: Couldn't open file \"%s\"\n" RESET, fileName);
        exit(1);
    }
    // Read off tokens.
    while (readToken(&(*intermediateArray)[*intermediateIndex], file, &lineNumber)) {
        if ((size_t)*intermediateIndex >= *arraySize - 1) {
            size_t grownSize = *arraySize * 2;  // Double the size of the array.
            // Into a temporary, so that the old allocation is still ours to free if
            // this fails, rather than being lost the moment realloc returns NULL.
            intermediateElement *grown = realloc(*intermediateArray, grownSize * sizeof(intermediateElement));
            if (!grown) {
                fprintf(stderr, RED "Error: Memory reallocation failed.\n" RESET);
                exit(1);
            }
            // New elements have to start blank. realloc leaves the new space holding
            // whatever the heap had in it before, and an element that never sets its
            // own byteLength, such as a keyword or a label definition, would then add
            // rubbish to the running address and move everything after it.
            memset(grown + *arraySize, 0, (grownSize - *arraySize) * sizeof(intermediateElement));
            *intermediateArray = grown;
            *arraySize = grownSize;
        }
        //printf("Token number %d\n", intermediateIndex);
        // Go ahead and mark what we already know about this token.
        (*intermediateArray)[*intermediateIndex].fileName = fileName;
        (*intermediateArray)[*intermediateIndex].lineNumber = lineNumber;
        // Take a look at it and determine what it is.
        int testValue = checkIfKeyword(&(*intermediateArray)[*intermediateIndex]);
        if(testValue > 0) {
            switch (testValue){
                case KEYWORD_INCLUDE: {
                    // We need to load another file and process it before continuing.
                    status = NOWHERE;
                    // Get the filename and work out where it actually is.
                    (*intermediateIndex)++;
                    if (!readToken(&(*intermediateArray)[*intermediateIndex], file, &lineNumber)) {
                        // The file ended straight after the keyword, so there is no
                        // name to read and nothing sensible to go looking for.
                        fprintf(stderr, RED "Error: #Include without a file name.\n" RESET);
                        printf(" File: %s at line %d.\n", fileName, lineNumber);
                        exit(1);
                    }
                    char *requested = (*intermediateArray)[*intermediateIndex].token;
                    char *resolved = resolveInclude(fileName, requested);
                    if (!resolved) {
                        reportMissingInclude(fileName, requested, lineNumber);
                        exit(1);
                    }
                    // The included file's first token is about to be read into this
                    // same slot, so let the file name go now. Leaving it would strand
                    // the only pointer to it the moment it is overwritten.
                    free((*intermediateArray)[*intermediateIndex].token);
                    (*intermediateArray)[*intermediateIndex].token = NULL;
                    // recordSourceFile takes the path, and hands back NULL if this file
                    // has already been assembled. Including it twice is harmless, which
                    // is what lets two libraries depend on a third.
                    char *owned = recordSourceFile(resolved);
                    if (owned) {
                        loadFile(intermediateArray, owned, intermediateIndex, arraySize);
                    }
                }
                break;
                case KEYWORD_PROGRAM:
                    // Set the state PROGRAM so we mark additional tokens for inclusion into Program Memory.
                    status = PROGRAM;
                break;
                case KEYWORD_DATA:
                    // Set the state to DATA so we mark additional tokens for inclusion into Data Memory.
                    status = DATA;
                break;
                case KEYWORD_BASE: {
                    if (status != PROGRAM && status != DATA) {
                        fprintf(stderr, RED "Error: #Base outside the Program or Data Segment.\n There is no segment for it to be the base of.\n" RESET);
                        printf(" File: %s at line %d.\n", fileName, lineNumber);
                        exit(1);
                    }
                    if (segmentUsed[status]) {
                        fprintf(stderr, RED "Error: #Base after something is already in the segment.\n"
                                            " A base says where the whole segment begins, so it has to come first.\n" RESET);
                        printf(" File: %s at line %d.\n", fileName, lineNumber);
                        exit(1);
                    }
                    (*intermediateIndex)++;
                    if (!readToken(&(*intermediateArray)[*intermediateIndex], file, &lineNumber)) {
                        fprintf(stderr, RED "Error: #Base without an address.\n" RESET);
                        exit(1);
                    }
                    (*intermediateArray)[*intermediateIndex].fileName = fileName;
                    (*intermediateArray)[*intermediateIndex].lineNumber = lineNumber;
                    setSegmentBase(status, readAddress(&(*intermediateArray)[*intermediateIndex], "#Base"));
                    (*intermediateArray)[*intermediateIndex].type = KEYWORD;
                    (*intermediateArray)[*intermediateIndex].byteLength = 0;
                    (*intermediateArray)[*intermediateIndex].destination = NOWHERE;
                    (*intermediateArray)[*intermediateIndex - 1].destination = NOWHERE;
                    (*intermediateArray)[*intermediateIndex - 1].byteLength = 0;
                    (*intermediateIndex)++;
                    continue;
                }
                case KEYWORD_ALIGN:
                case KEYWORD_RESERVE: {
                    // Both take a count, and both only make sense somewhere that has a
                    // cursor to move along.
                    const char *what = (testValue == KEYWORD_ALIGN) ? "#Align" : "#Reserve";
                    if (status != PROGRAM && status != DATA) {
                        fprintf(stderr, RED "Error: %s outside the Program or Data Segment.\n There is nothing there for it to move along.\n" RESET, what);
                        printf(" File: %s at line %d.\n", fileName, lineNumber);
                        exit(1);
                    }
                    // The count is read here rather than being left to the literal check,
                    // because it is an instruction to the assembler and never becomes a
                    // byte, so a byte's range would be the wrong limit for it. A page
                    // alignment needs 256, and a reservation is often far larger.
                    intermediateElement *directive = &(*intermediateArray)[*intermediateIndex];
                    (*intermediateIndex)++;
                    if (!readToken(&(*intermediateArray)[*intermediateIndex], file, &lineNumber)) {
                        fprintf(stderr, RED "Error: %s without a number.\n" RESET, what);
                        printf(" File: %s at line %d.\n", fileName, lineNumber);
                        exit(1);
                    }
                    (*intermediateArray)[*intermediateIndex].fileName = fileName;
                    (*intermediateArray)[*intermediateIndex].lineNumber = lineNumber;
                    uint16_t count = readCount(&(*intermediateArray)[*intermediateIndex], what);

                    // The count token itself contributes nothing; the directive carries
                    // everything, so that one element stands for one run of zeroes.
                    (*intermediateArray)[*intermediateIndex].type = KEYWORD;
                    (*intermediateArray)[*intermediateIndex].byteLength = 0;
                    (*intermediateArray)[*intermediateIndex].destination = NOWHERE;

                    directive->destination = status;
                    if (testValue == KEYWORD_ALIGN) {
                        // How many zeroes this comes to depends on where the cursor has
                        // reached, which is not known until the second pass walks it.
                        directive->type = ALIGNMENT;
                        directive->address = count;
                        directive->byteLength = 0;
                    } else {
                        directive->type = PADDING;
                        directive->byteLength = count;
                    }
                    (*intermediateIndex)++;
                    continue;
                }
                case KEYWORD_VECTORS:
                    // Set the state to VECTORS. Tokens from here on name handlers rather
                    // than becoming bytes, and the second pass reads them.
                    status = VECTORS;
                break;
            }
        // Next, check to see if it's an instruction.
        } else if (checkIfInstruction(&(*intermediateArray)[*intermediateIndex])) {
            // We should check if we're set up to mark this for the Program Segment.
            if (status != PROGRAM) {
                fprintf(stderr, RED "Error: Attempting to assemble outside the Program Segment.\n Did you forget to use the #Program keyword?\n" RESET);
                printf(" File: %s at line %d.\n", fileName, lineNumber);
                exit(1);
            }
        // Next, check if it's a literal value. A string is never one, however it begins:
        // the quotes are gone by now, so a string starting with a zero looks exactly like
        // a malformed literal and used to be rejected as one.
        } else if ((*intermediateArray)[*intermediateIndex].type != STRING
                   && checkIfLiteralValue(&(*intermediateArray)[*intermediateIndex])) {
            // We should check to make sure we have a destination for it.
            if (status == NOWHERE) {
                fprintf(stderr, RED "Error: Attempting to write a value to nowhere!\n Did you forget to use the #Program or #Data keyword?\n" RESET);
                printf(" File: %s at line %d.\n", fileName, lineNumber);
                exit(1);
            }
        // Finally, check if it's a label or label definition.
        // First, make sure it hasn't already been marked as a string literal.
        } else if ((*intermediateArray)[*intermediateIndex].type != STRING) {
            if (checkIfLabel(&(*intermediateArray)[*intermediateIndex])) {
                if (status == NOWHERE) {
                    fprintf(stderr, RED "Error: Attempting to create or use a label nowhere!\n Did you forget to use the #Program or #Data keyword?\n" RESET);
                    printf(" File: %s at line %d.\n", fileName, lineNumber);
                    exit(1);
                }
                // A name written after SWI is a vector rather than an address, so it
                // stands for one byte instead of two. This is settled by what the name
                // follows, so that it does not depend on the Vector Segment having been
                // read first, which it may not have been: it can live in another file.
                if (status == PROGRAM
                    && (*intermediateArray)[*intermediateIndex].type == LABEL
                    && *intermediateIndex > 0
                    && (*intermediateArray)[*intermediateIndex - 1].type == INSTRUCTION
                    && (*intermediateArray)[*intermediateIndex - 1].byteValue == 0x18) {
                    (*intermediateArray)[*intermediateIndex].type = VECTOR_REFERENCE;
                    (*intermediateArray)[*intermediateIndex].byteLength = 1;
                }
            }
        }
        (*intermediateArray)[*intermediateIndex].destination = status;
        if ((status == PROGRAM || status == DATA)
            && (*intermediateArray)[*intermediateIndex].type != KEYWORD) {
            segmentUsed[status] = 1;
        }
        (*intermediateIndex)++;
    }
    return 0;
}
