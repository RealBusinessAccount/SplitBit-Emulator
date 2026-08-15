// boostrap.c
// Boostrapping Functions for the SplitBit CPU Emulator
// Written by Anachronaut
// 10/16/2024

#include "bootstrap.h"
#include "../Assembler/assembly.h" // For the binary format, which both tools share.
#include <stdio.h>
#include <string.h>

// Reads a number of the given width, most significant byte first.
// Returns 1 if the file runs out before the number does.
static uint8_t readNumber(FILE *file, int width, const char *what, uint32_t *result) {
    uint32_t value = 0;
    for (int i = 0; i < width; i++) {
        int byte = fgetc(file);
        if (byte == EOF) {
            fprintf(stderr, "Error: Unexpected end of file while reading %s.\n", what);
            return 1;
        }
        value = (value << 8) | (uint8_t)byte;
    }
    *result = value;
    return 0;
}

// Reads a fixed length marker and checks it against the one expected. The caller's
// buffer must have room for length + 1 characters; it always comes back with a null
// on the end, so it is safe to print in an error message either way.
static uint8_t readMarker(FILE *file, const char *expected, int length, char *found) {
    memset(found, 0, length + 1);
    for (int i = 0; i < length; i++) {
        int byte = fgetc(file);
        if (byte == EOF) {
            return 1;
        }
        found[i] = (char)byte;
    }
    return strncmp(found, expected, length) != 0;
}

// Reads the file header: the magic, the format version, and the features the binary
// says it needs from the machine.
static uint8_t readFileHeader(FILE *file) {
    char magic[SPLITBIT_MAGIC_LENGTH + 1];
    if (readMarker(file, SPLITBIT_MAGIC, SPLITBIT_MAGIC_LENGTH, magic)) {
        fprintf(stderr, "Error: This is not a SplitBit binary.\n");
        if (strncmp(magic, "PRG", 3) == 0) {
            fprintf(stderr, " It looks like a binary from before the format carried a version.\n Reassemble it and try again.\n");
        } else {
            fprintf(stderr, " Expected the file to begin with \"%s\", found \"%s\".\n", SPLITBIT_MAGIC, magic);
        }
        return 1;
    }

    uint32_t version;
    if (readNumber(file, 1, "the format version", &version)) {
        return 1;
    }
    if (version != SPLITBIT_FORMAT_VERSION) {
        fprintf(stderr, "Error: This binary is in format version %u, and this emulator reads version %u.\n", version, SPLITBIT_FORMAT_VERSION);
        return 1;
    }

    uint32_t required;
    if (readNumber(file, SPLITBIT_FLAGS_LENGTH, "the feature flags", &required)) {
        return 1;
    }
    uint32_t missing = required & ~(uint32_t)SPLITBIT_FEATURES_SUPPORTED;
    if (missing) {
        fprintf(stderr, "Error: This binary was built for a machine this emulator cannot provide.\n");
        fprintf(stderr, " It asks for feature bits 0x%08X, which are not implemented here.\n", missing);
        return 1;
    }
    return 0;
}

static uint8_t loadSegment(FILE *file, uint8_t *Memory, uint32_t length) {
    for (uint32_t i = 0; i < length; i++) {
        int byte = fgetc(file);
        if (byte == EOF) {
            fprintf(stderr, "Error: Unexpected end of file while reading a segment.\n");
            return 1;
        }
        Memory[i] = (uint8_t)byte;
    }
    return 0;
}

// Reads one segment: its marker, its length, and then its contents.
static uint8_t readSegment(FILE *file, const char *marker, uint8_t *Memory) {
    char found[SEGMENT_MARKER_LENGTH + 1];
    if (readMarker(file, marker, SEGMENT_MARKER_LENGTH, found)) {
        fprintf(stderr, "Error: Expected a \"%s\" segment here, found \"%s\".\n", marker, found);
        return 1;
    }
    uint32_t length;
    if (readNumber(file, SEGMENT_LENGTH_BYTES, "a segment length", &length)) {
        return 1;
    }
    return loadSegment(file, Memory, length);
}

// Reads the Vector Segment, which is optional and last. A file that simply ends here
// was written before vectors existed, and an empty table is exactly right for it: every
// entry reads as zero, which means no handler, and the boot vector reading zero means
// the program starts at 0x0000 the way it always did.
//
// Each entry says where in Program Memory the vector sits and where its handler is, so
// installing one is a write straight into the vector table.
static uint8_t readVectorSegment(FILE *file, uint8_t *Program) {
    int first = fgetc(file);
    if (first == EOF) {
        return 0;
    }
    ungetc(first, file);

    char found[SEGMENT_MARKER_LENGTH + 1];
    if (readMarker(file, "VEC", SEGMENT_MARKER_LENGTH, found)) {
        fprintf(stderr, "Error: Expected a \"VEC\" segment here, found \"%s\".\n", found);
        return 1;
    }
    uint32_t length;
    if (readNumber(file, SEGMENT_LENGTH_BYTES, "the vector segment length", &length)) {
        return 1;
    }
    if (length % VECTOR_ENTRY_FILE_BYTES != 0) {
        fprintf(stderr, "Error: The vector segment is %u bytes, which is not a whole number of vectors.\n", length);
        return 1;
    }
    for (uint32_t i = 0; i < length / VECTOR_ENTRY_FILE_BYTES; i++) {
        uint32_t slot, handler;
        if (readNumber(file, 2, "a vector address", &slot)
         || readNumber(file, 2, "a handler address", &handler)) {
            return 1;
        }
        if (slot < SOFTWARE_VECTOR_BASE) {
            fprintf(stderr, "Error: This binary puts a vector at 0x%04X, which is below the vector table.\n", slot);
            return 1;
        }
        Program[slot] = (handler >> 8) & 0xFF;
        Program[(uint16_t)(slot + 1)] = handler & 0xFF;
    }
    return 0;
}

uint8_t loadFile(char *path, uint8_t *Program, uint8_t *Data) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "Error: Couldn't open file: %s\n", path);
        return 1;
    }
    // The Program Segment must come first, then the Data Segment. Short circuiting
    // here means there is one exit, and so only one place that has to close the file.
    uint8_t failed = readFileHeader(file)
                  || readSegment(file, "PRG", Program)
                  || readSegment(file, "DAT", Data)
                  || readVectorSegment(file, Program);
    fclose(file);
    return failed;
}
