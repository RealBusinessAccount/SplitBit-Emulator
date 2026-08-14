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
    int lineNumber = 1; // Line numbers start at 1.
    // Open the file.
    FILE *file = fopen(fileName, "r");
    if (!file) {
        fprintf(stderr, RED "Error: Couldn't open file \"%s\"\n" RESET, fileName);
        exit(1);
    }
    // Read off tokens.
    while (readToken(&(*intermediateArray)[*intermediateIndex], file, &lineNumber)) {
        if (*intermediateIndex >= *arraySize - 1) {
            *arraySize *= 2;  // Double the size of the array
            *intermediateArray = realloc(*intermediateArray, *arraySize * sizeof(intermediateElement));
            if (!intermediateArray) {
                fprintf(stderr, RED "Error: Memory reallocation failed.\n" RESET);
                exit(1);
            }
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
                    readToken(&(*intermediateArray)[*intermediateIndex], file, &lineNumber);
                    char *requested = (*intermediateArray)[*intermediateIndex].token;
                    char *resolved = resolveInclude(fileName, requested);
                    if (!resolved) {
                        reportMissingInclude(fileName, requested, lineNumber);
                        exit(1);
                    }
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
            }
        // Next, check to see if it's an instruction.
        } else if (checkIfInstruction(&(*intermediateArray)[*intermediateIndex])) {
            // We should check if we're set up to mark this for the Program Segment.
            if (status != PROGRAM) {
                fprintf(stderr, RED "Error: Attempting to assemble outside the Program Segment.\n Did you forget to use the #Program keyword?\n" RESET);
                printf(" File: %s at line %d.\n", fileName, lineNumber);
                exit(1);
            }
        // Next, check if it's a literal value.
        } else if (checkIfLiteralValue(&(*intermediateArray)[*intermediateIndex])) {
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
            }
        }
        (*intermediateArray)[*intermediateIndex].destination = status;
        (*intermediateIndex)++;
    }
    return 0;
}
