 // Assembler.c
// Basic Assembler for programs written for the SplitBit CPU
// Written by Anachronaut
// 10/18/2024

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <libgen.h>
#include <unistd.h>
#include <getopt.h>
#include "Assm-util.h"
#include "firstPass.h"
#include "secondPass.h"

int programLength = 0;
int dataLength = 0;

uint8_t Program[0xFFFF], Data[0xFFFF];


char* createOutputFileName(const char *inputFilePath) {
    // Make a copy of inputFilePath, since basename may modify it
    char *pathCopy = strdup(inputFilePath);
    if (!pathCopy) {
        fprintf(stderr, "Error: Memory allocation failed for path copy.\n");
        exit(1);
    }

    // Get the filename from the path
    char *fileName = basename(pathCopy);

    // Find the length of the filename
    size_t len = strlen(fileName);

    // Check if the filename ends with ".asm"
    char *outputFileName;
    if (len > 4 && strcmp(fileName + len - 4, ".asm") == 0) {
        // Allocate memory for the new file name with ".bin" extension
        outputFileName = malloc(len - 4 + 5);  // Remove ".asm" (4 chars) and add ".bin" (4 chars + null terminator)
        if (!outputFileName) {
            fprintf(stderr, "Error: Memory allocation failed for output file name.\n");
            free(pathCopy);
            exit(1);
        }
        // Copy the filename up to ".asm" and add ".bin"
        strncpy(outputFileName, fileName, len - 4);
        strcpy(outputFileName + len - 4, ".bin");
    } else {
        // If there's no ".asm" extension, add ".bin" to the full filename
        outputFileName = malloc(len + 5);  // Original length + ".bin" + null terminator
        if (!outputFileName) {
            fprintf(stderr, "Error: Memory allocation failed for output file name.\n");
            free(pathCopy);
            exit(1);
        }
        strcpy(outputFileName, fileName);
        strcat(outputFileName, ".bin");
    }

    free(pathCopy);  // Free the temporary path copy
    return outputFileName;
}

// Remember to be a good programmer and free up all the allocated memory.
void assemblerCleanup(intermediateElement *intermediateArray, int arraySize, char *outputFileName) {
    // Free each token in intermediateArray.
    for (int i = 0; i < arraySize; i++) {
        if (intermediateArray[i].token) {
            free(intermediateArray[i].token);
        }
    }
    // Free the intermediateArray itself.
    free(intermediateArray);

    // Free the list of included files.
    freeIncludeList();

    // Free the list of labels.
    freeLabelList();

    // Free the list of vectors.
    freeVectorList();

    // Free the output file name
    free(outputFileName);
}

void printUsage(const char *programName) {
    printf("Usage: %s [OPTIONS] <sourcefile>\n", programName);
    printf("\n");
    printf("Options:\n");
    printf("  -o <file>    Write the output to this path instead of alongside the source.\n");
    printf("  -I <dir>     Look in this directory for included files. May be given more than once.\n");
    printf("  -M <file>    Write the source files this output depends on, as a make rule.\n");
    printf("  -h, --help   Display this help message.\n");
}

// Writes a make rule naming every source file that went into the output, so that a
// build system knows to reassemble when any of them changes. The empty rules after it
// are so that deleting a library does not leave make with a prerequisite it cannot
// build; without them the build stops instead of just reassembling.
void writeDependencyFile(const char *dependencyPath, const char *outputPath) {
    FILE *file = fopen(dependencyPath, "w");
    if (!file) {
        fprintf(stderr, RED "Error: Could not open file \"%s\" for writing.\n" RESET, dependencyPath);
        exit(1);
    }
    fprintf(file, "%s:", outputPath);
    for (int i = 0; i < sourceFileCount(); i++) {
        fprintf(file, " %s", sourceFile(i));
    }
    fprintf(file, "\n\n");
    // The source itself is index 0, and always exists, so it needs no empty rule.
    for (int i = 1; i < sourceFileCount(); i++) {
        fprintf(file, "%s:\n", sourceFile(i));
    }
    fclose(file);
}

// A program that bases one segment and not the other is a mistake the assembler is the
// last place to catch. Nothing relocates, so the unbased half keeps the addresses it was
// given, which are addresses from zero up, and the loader puts it there: on top of
// whatever the system keeps at the bottom of memory. It does not fail at load time and it
// does not fail at the jump. It fails later, somewhere else, as corruption.
//
// Only a segment with something in it can land on anything, so an empty one says nothing.
// A base of zero that was actually asked for is left alone, which is how a program says
// it meant it.
void checkSegmentBases(const char *fileName) {
    if (!programIsLoadable()) {
        return; // A boot image. Both segments begin at zero because that is where they go.
    }

    const char *segmentName[3];
    segmentName[PROGRAM] = "Program";
    segmentName[DATA] = "Data";
    int segmentEnd[3];
    segmentEnd[PROGRAM] = programLength;
    segmentEnd[DATA] = dataLength;

    const int segments[2] = { PROGRAM, DATA };
    for (int i = 0; i < 2; i++) {
        int mine = segments[i], other = segments[1 - i];
        int content = segmentEnd[mine] - segmentBase(mine);
        if (segmentBaseWasGiven(mine) || content <= 0 || !segmentBaseWasGiven(other)) {
            continue;
        }
        fprintf(stderr, RED "Error: The %s Segment is based at 0x%04X, but the %s Segment\n"
                            " has %d byte%s at 0x0000 and was never given a #Base.\n"
                            " Half a program loaded at zero lands on whatever is already there.\n" RESET,
                segmentName[other], segmentBase(other), segmentName[mine],
                content, content == 1 ? "" : "s");
        printf(" File: %s\n", fileName);
        printf(" Say \"#Base 0x0000\" in the %s Segment if that is what you meant.\n", segmentName[mine]);
        exit(1);
    }
}

int main(int argc, char *argv[]) {
    static struct option long_options[] = {
        {"output",  required_argument, 0, 'o'},
        {"include", required_argument, 0, 'I'},
        {"depend",  required_argument, 0, 'M'},
        {"help",    no_argument,       0, 'h'},
        {0,         0,                 0,  0 }
        };
    char *outputFileName = NULL;
    char *dependencyFileName = NULL;
    int option_index = 0;
    int opt;

    while ((opt = getopt_long(argc, argv, "o:I:M:h", long_options, &option_index)) != -1) {
        switch (opt) {
            case 'o':
                outputFileName = strdup(optarg);
            break;
            case 'I':
                addIncludeDirectory(optarg);
            break;
            case 'M':
                dependencyFileName = strdup(optarg);
            break;
            case 'h':
                printUsage(argv[0]);
                return 0;
            default:
                printUsage(argv[0]);
                return 1;
        }
    }

    if (optind >= argc) {
        fprintf(stderr, RED "Error: No source file specified.\n" RESET);
        printUsage(argv[0]);
        return 1;
    }
    char *fileName = argv[optind];
    optind++;
    if (optind < argc) {
        fprintf(stderr, RED "Error: Unexpected argument: %s\n" RESET, argv[optind]);
        return 1;
    }

    // Allocate initial space for the intermediate array. calloc rather than malloc,
    // because not every element sets every one of its own fields, and a stray
    // byteLength would quietly shift every address that follows it.
    size_t arraySize = 1024;
    intermediateElement *intermediateArray = calloc(arraySize, sizeof(intermediateElement));
    if (!intermediateArray) {
        fprintf(stderr, RED "Error: Memory allocation failed.\n" RESET);
        exit(1);
    }

    // The file named on the command line is the first source file, and the include
    // list owns the copy that everything else points at.
    char *source = recordSourceFile(strdup(fileName));
    int index = 0;
    loadFile(&intermediateArray, source, &index, &arraySize);
    populateLabelTable(intermediateArray, index);
    fillInLabelAddresses(intermediateArray, index);
    // Vectors come after the labels, because a handler is named by its label, and before
    // the buffers are filled, because SWI needs the number its vector was given.
    populateVectorTable(intermediateArray, index);
    fillInVectorReferences(intermediateArray, index);
    // The buffers are filled from wherever each segment is based, so that a byte's place
    // in the buffer is the address it will have. For a boot image both bases are zero and
    // this changes nothing.
    programLength = segmentBase(PROGRAM);
    dataLength = segmentBase(DATA);
    populateOutputBuffers(intermediateArray, index, Program, &programLength, Data, &dataLength);
    // After the buffers, because how much a segment actually holds is not known until it
    // has been filled, and an empty segment is not a mistake.
    checkSegmentBases(fileName);
    if (!outputFileName) {
        outputFileName = createOutputFileName(fileName);
    }
    writeOutputFile(outputFileName, Program, programLength, Data, dataLength);
    if (dependencyFileName) {
        writeDependencyFile(dependencyFileName, outputFileName);
        free(dependencyFileName);
    }
    assemblerCleanup(intermediateArray, index, outputFileName);
    return 0;
}

