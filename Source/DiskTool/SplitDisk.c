// SplitDisk.c
// Makes and edits SplitBit disk images from the host.
//
// Until SplitBit can write its own filesystem there has to be some way to get a program
// onto a disk, and this is it. It is not a shortcut around the machine: it speaks exactly
// the format SplitBit will speak, so an image this makes is one the machine can read and
// an image the machine writes is one this can read back.
//
// Written by Anachronaut

#include "sbfs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Numbers on a SplitBit disk are most significant byte first, the same as everywhere
// else on the machine.
static uint16_t readWord(const uint8_t *at) {
    return (uint16_t)((at[0] << 8) | at[1]);
}

static void writeWord(uint8_t *at, uint16_t value) {
    at[0] = (uint8_t)(value >> 8);
    at[1] = (uint8_t)(value & 0xFF);
}

static FILE *openImage(const char *path, const char *mode) {
    FILE *image = fopen(path, mode);
    if (image == NULL) {
        fprintf(stderr, "Error: Couldn't open the disk image \"%s\".\n", path);
    }
    return image;
}

static int readBlock(FILE *image, uint16_t block, uint8_t *into) {
    if (fseek(image, (long)block * SBFS_BLOCK_BYTES, SEEK_SET) != 0
        || fread(into, 1, SBFS_BLOCK_BYTES, image) != SBFS_BLOCK_BYTES) {
        fprintf(stderr, "Error: Couldn't read block %u.\n", block);
        return 1;
    }
    return 0;
}

static int writeBlock(FILE *image, uint16_t block, const uint8_t *from) {
    if (fseek(image, (long)block * SBFS_BLOCK_BYTES, SEEK_SET) != 0
        || fwrite(from, 1, SBFS_BLOCK_BYTES, image) != SBFS_BLOCK_BYTES) {
        fprintf(stderr, "Error: Couldn't write block %u.\n", block);
        return 1;
    }
    return 0;
}

typedef struct {
    uint16_t diskBlocks;
    uint16_t directoryStart;
    uint16_t directoryBlocks;
    uint16_t freeBlocks;
} Superblock;

// Reads block 0 and checks it really is one of ours. Without the magic a blank image and
// a formatted one with no files would be the same thing.
static int readSuperblock(FILE *image, Superblock *super) {
    uint8_t block[SBFS_BLOCK_BYTES];
    if (readBlock(image, 0, block)) {
        return 1;
    }
    if (memcmp(block, SBFS_MAGIC, SBFS_MAGIC_BYTES) != 0) {
        fprintf(stderr, "Error: That is not a SplitBit disk. Format it first.\n");
        return 1;
    }
    if (block[SBFS_SUPER_VERSION] != SBFS_VERSION) {
        fprintf(stderr, "Error: That disk is version %u, and this understands version %u.\n",
                block[SBFS_SUPER_VERSION], SBFS_VERSION);
        return 1;
    }
    super->diskBlocks = readWord(block + SBFS_SUPER_DISK);
    super->directoryStart = readWord(block + SBFS_SUPER_DIRSTART);
    super->directoryBlocks = readWord(block + SBFS_SUPER_DIRBLOCKS);
    super->freeBlocks = readWord(block + SBFS_SUPER_FREE);
    return 0;
}

static int writeSuperblock(FILE *image, const Superblock *super) {
    uint8_t block[SBFS_BLOCK_BYTES];
    memset(block, 0, sizeof(block));
    memcpy(block, SBFS_MAGIC, SBFS_MAGIC_BYTES);
    block[SBFS_SUPER_VERSION] = SBFS_VERSION;
    writeWord(block + SBFS_SUPER_DISK, super->diskBlocks);
    writeWord(block + SBFS_SUPER_DIRSTART, super->directoryStart);
    writeWord(block + SBFS_SUPER_DIRBLOCKS, super->directoryBlocks);
    writeWord(block + SBFS_SUPER_FREE, super->freeBlocks);
    return writeBlock(image, 0, block);
}

// The whole directory, held in memory while a command works on it. It is small enough
// that reading it once and writing it back once is simpler than picking at blocks, and it
// is what the machine will do too once it has the Data Memory to spare.
typedef struct {
    uint8_t *bytes;
    int entries;
} Directory;

static int readDirectory(FILE *image, const Superblock *super, Directory *directory) {
    directory->entries = super->directoryBlocks * SBFS_ENTRIES_PER_BLOCK;
    directory->bytes = malloc((size_t)super->directoryBlocks * SBFS_BLOCK_BYTES);
    if (directory->bytes == NULL) {
        fprintf(stderr, "Error: Out of memory reading the directory.\n");
        return 1;
    }
    for (uint16_t i = 0; i < super->directoryBlocks; i++) {
        if (readBlock(image, (uint16_t)(super->directoryStart + i),
                      directory->bytes + (size_t)i * SBFS_BLOCK_BYTES)) {
            free(directory->bytes);
            directory->bytes = NULL;
            return 1;
        }
    }
    return 0;
}

static int writeDirectory(FILE *image, const Superblock *super, const Directory *directory) {
    for (uint16_t i = 0; i < super->directoryBlocks; i++) {
        if (writeBlock(image, (uint16_t)(super->directoryStart + i),
                       directory->bytes + (size_t)i * SBFS_BLOCK_BYTES)) {
            return 1;
        }
    }
    return 0;
}

static uint8_t *entryAt(const Directory *directory, int index) {
    return directory->bytes + (size_t)index * SBFS_ENTRY_BYTES;
}

static int entryInUse(const uint8_t *entry) {
    return (entry[SBFS_ENTRY_FLAGS] & SBFS_FLAG_IN_USE) != 0;
}

static uint32_t entrySize(const uint8_t *entry) {
    return (uint32_t)readWord(entry + SBFS_ENTRY_BLOCKS) * SBFS_BLOCK_BYTES
         + entry[SBFS_ENTRY_TAIL];
}

static uint16_t entryBlocksUsed(const uint8_t *entry) {
    return (uint16_t)SBFS_BLOCKS_USED(readWord(entry + SBFS_ENTRY_BLOCKS),
                                      entry[SBFS_ENTRY_TAIL]);
}

// Names are compared as written, the way labels are, and are padded rather than
// terminated, so a name that fills the field has no terminator to find.
static void entryName(const uint8_t *entry, char *into) {
    memcpy(into, entry + SBFS_ENTRY_NAME, SBFS_NAME_BYTES);
    into[SBFS_NAME_BYTES] = '\0';
}

static int findByName(const Directory *directory, const char *name) {
    char held[SBFS_NAME_BYTES + 1];
    for (int i = 0; i < directory->entries; i++) {
        const uint8_t *entry = entryAt(directory, i);
        if (!entryInUse(entry)) {
            continue;
        }
        entryName(entry, held);
        if (strcmp(held, name) == 0) {
            return i;
        }
    }
    return -1;
}

// Where the first free run of the wanted length begins, or -1 if there is not one.
//
// There is no allocation bitmap, and that is the design rather than an omission: with
// files laid down contiguously, every block is either inside some entry's range or it is
// not, so the directory already is the allocation map. A bitmap would be a second copy of
// a fact that is already written down, and a second copy is a thing that can disagree.
static long findFreeRun(const Directory *directory, const Superblock *super, uint16_t wanted) {
    if (wanted == 0) {
        // An empty file occupies nothing, so it has no start to speak of. Block 0 is the
        // superblock and can never hold file data, which makes it the honest way to say
        // "nowhere" without inventing a place that belongs to somebody else.
        (void)directory;
        return 0;
    }
    uint32_t firstData = (uint32_t)super->directoryStart + super->directoryBlocks;
    for (uint32_t candidate = firstData; candidate + wanted <= super->diskBlocks; candidate++) {
        uint32_t clash = 0;
        for (int i = 0; i < directory->entries && !clash; i++) {
            const uint8_t *entry = entryAt(directory, i);
            if (!entryInUse(entry)) {
                continue;
            }
            uint32_t start = readWord(entry + SBFS_ENTRY_START);
            uint32_t used = entryBlocksUsed(entry);
            if (used == 0) {
                continue;
            }
            if (candidate < start + used && start < candidate + wanted) {
                // Overlaps this file, so start looking again past the end of it.
                clash = start + used;
            }
        }
        if (clash) {
            candidate = clash - 1; // The loop's increment takes it to clash.
            continue;
        }
        return (long)candidate;
    }
    return -1;
}

static uint16_t countFree(const Directory *directory, const Superblock *super) {
    uint32_t used = 0;
    for (int i = 0; i < directory->entries; i++) {
        const uint8_t *entry = entryAt(directory, i);
        if (entryInUse(entry)) {
            used += entryBlocksUsed(entry);
        }
    }
    // Block 0 and everything up to the end of the directory is not available.
    uint32_t overhead = (uint32_t)super->directoryStart + super->directoryBlocks;
    return (uint16_t)(super->diskBlocks - overhead - used);
}

// ---- Commands ----

static int commandFormat(const char *path, uint16_t blocks, uint16_t directoryBlocks) {
    if (blocks <= 1u + directoryBlocks) {
        fprintf(stderr, "Error: A disk of %u blocks has no room for a superblock and a"
                        " directory of %u.\n", blocks, directoryBlocks);
        return 1;
    }
    // Quietly, because a disk that is not there yet is the ordinary case for format and
    // not something to complain about on the way past.
    FILE *image = fopen(path, "r+b");
    if (image == NULL) {
        image = openImage(path, "w+b");
        if (image == NULL) {
            return 1;
        }
    }
    uint8_t empty[SBFS_BLOCK_BYTES];
    memset(empty, 0, sizeof(empty));
    for (uint16_t i = 0; i < blocks; i++) {
        if (writeBlock(image, i, empty)) {
            fclose(image);
            return 1;
        }
    }
    Superblock super;
    super.diskBlocks = blocks;
    super.directoryStart = SBFS_FIRST_DIRECTORY_BLOCK;
    super.directoryBlocks = directoryBlocks;
    super.freeBlocks = (uint16_t)(blocks - 1 - directoryBlocks);
    if (writeSuperblock(image, &super)) {
        fclose(image);
        return 1;
    }
    fclose(image);
    printf("Formatted %s: %u blocks, %u of directory, %u free.\n",
           path, blocks, directoryBlocks, super.freeBlocks);
    return 0;
}

static int commandList(const char *path) {
    FILE *image = openImage(path, "rb");
    if (image == NULL) {
        return 1;
    }
    Superblock super;
    Directory directory;
    if (readSuperblock(image, &super) || readDirectory(image, &super, &directory)) {
        fclose(image);
        return 1;
    }
    printf("%s: %u blocks, %u of directory, %u entries.\n",
           path, super.diskBlocks, super.directoryBlocks, directory.entries);
    printf("%-22s %8s %7s %7s\n", "NAME", "BYTES", "START", "BLOCKS");
    char name[SBFS_NAME_BYTES + 1];
    int shown = 0;
    for (int i = 0; i < directory.entries; i++) {
        const uint8_t *entry = entryAt(&directory, i);
        if (!entryInUse(entry)) {
            continue;
        }
        entryName(entry, name);
        printf("%-22s %8u %7u %7u\n", name, entrySize(entry),
               readWord(entry + SBFS_ENTRY_START), entryBlocksUsed(entry));
        shown++;
    }
    // The count in the superblock is a cache, so say what the directory actually adds up
    // to as well. If the two ever disagree, the directory is the one to believe.
    uint16_t counted = countFree(&directory, &super);
    printf("%d file%s, %u blocks free", shown, shown == 1 ? "" : "s", counted);
    if (counted != super.freeBlocks) {
        printf(" (the superblock says %u, which is stale)", super.freeBlocks);
    }
    printf(".\n");
    free(directory.bytes);
    fclose(image);
    return 0;
}

static int commandPut(const char *path, const char *hostFile, const char *asName) {
    FILE *source = fopen(hostFile, "rb");
    if (source == NULL) {
        fprintf(stderr, "Error: Couldn't open \"%s\".\n", hostFile);
        return 1;
    }
    fseek(source, 0, SEEK_END);
    long size = ftell(source);
    rewind(source);
    if (size < 0) {
        fprintf(stderr, "Error: Couldn't measure \"%s\".\n", hostFile);
        fclose(source);
        return 1;
    }

    if (strlen(asName) > SBFS_NAME_BYTES) {
        fprintf(stderr, "Error: \"%s\" is %zu characters, and a name may be %d.\n"
                        " Give a shorter one as the last argument.\n",
                asName, strlen(asName), SBFS_NAME_BYTES);
        fclose(source);
        return 1;
    }

    FILE *image = openImage(path, "r+b");
    if (image == NULL) {
        fclose(source);
        return 1;
    }
    Superblock super;
    Directory directory;
    if (readSuperblock(image, &super) || readDirectory(image, &super, &directory)) {
        fclose(source);
        fclose(image);
        return 1;
    }
    if (findByName(&directory, asName) >= 0) {
        fprintf(stderr, "Error: \"%s\" is already on the disk. Delete it first.\n", asName);
        goto failed;
    }
    int slot = -1;
    for (int i = 0; i < directory.entries && slot < 0; i++) {
        if (!entryInUse(entryAt(&directory, i))) {
            slot = i;
        }
    }
    if (slot < 0) {
        fprintf(stderr, "Error: The directory is full: %d entries, all taken.\n", directory.entries);
        goto failed;
    }

    uint16_t whole = (uint16_t)SBFS_WHOLE_BLOCKS(size);
    uint8_t tail = (uint8_t)SBFS_TAIL_BYTES(size);
    uint16_t needed = (uint16_t)SBFS_BLOCKS_USED(whole, tail);
    long start = findFreeRun(&directory, &super, needed);
    if (start < 0) {
        fprintf(stderr, "Error: No run of %u free blocks. There may be room on the disk"
                        " without there being room in one piece.\n", needed);
        goto failed;
    }

    uint8_t block[SBFS_BLOCK_BYTES];
    for (uint16_t i = 0; i < needed; i++) {
        memset(block, 0, sizeof(block));
        size_t got = fread(block, 1, SBFS_BLOCK_BYTES, source);
        if (got == 0 && i < needed) {
            fprintf(stderr, "Error: \"%s\" ended sooner than its size said.\n", hostFile);
            goto failed;
        }
        if (writeBlock(image, (uint16_t)(start + i), block)) {
            goto failed;
        }
    }

    uint8_t *entry = entryAt(&directory, slot);
    memset(entry, 0, SBFS_ENTRY_BYTES);
    entry[SBFS_ENTRY_FLAGS] = SBFS_FLAG_IN_USE;
    writeWord(entry + SBFS_ENTRY_START, (uint16_t)start);
    writeWord(entry + SBFS_ENTRY_BLOCKS, whole);
    entry[SBFS_ENTRY_TAIL] = tail;
    memcpy(entry + SBFS_ENTRY_NAME, asName, strlen(asName));

    super.freeBlocks = countFree(&directory, &super);
    if (writeDirectory(image, &super, &directory) || writeSuperblock(image, &super)) {
        goto failed;
    }
    printf("Put %s on as \"%s\": %ld bytes at block %ld.\n", hostFile, asName, size, start);
    free(directory.bytes);
    fclose(source);
    fclose(image);
    return 0;

failed:
    free(directory.bytes);
    fclose(source);
    fclose(image);
    return 1;
}

static int commandGet(const char *path, const char *name, const char *hostFile) {
    FILE *image = openImage(path, "rb");
    if (image == NULL) {
        return 1;
    }
    Superblock super;
    Directory directory;
    if (readSuperblock(image, &super) || readDirectory(image, &super, &directory)) {
        fclose(image);
        return 1;
    }
    int slot = findByName(&directory, name);
    if (slot < 0) {
        fprintf(stderr, "Error: There is no \"%s\" on that disk.\n", name);
        free(directory.bytes);
        fclose(image);
        return 1;
    }
    const uint8_t *entry = entryAt(&directory, slot);
    uint32_t size = entrySize(entry);
    uint16_t start = readWord(entry + SBFS_ENTRY_START);
    uint16_t used = entryBlocksUsed(entry);

    FILE *out = fopen(hostFile, "wb");
    if (out == NULL) {
        fprintf(stderr, "Error: Couldn't write \"%s\".\n", hostFile);
        free(directory.bytes);
        fclose(image);
        return 1;
    }
    uint8_t block[SBFS_BLOCK_BYTES];
    uint32_t left = size;
    for (uint16_t i = 0; i < used; i++) {
        if (readBlock(image, (uint16_t)(start + i), block)) {
            fclose(out);
            free(directory.bytes);
            fclose(image);
            return 1;
        }
        uint32_t take = (left < SBFS_BLOCK_BYTES) ? left : SBFS_BLOCK_BYTES;
        fwrite(block, 1, take, out);
        left -= take;
    }
    fclose(out);
    printf("Got \"%s\" off as %s: %u bytes.\n", name, hostFile, size);
    free(directory.bytes);
    fclose(image);
    return 0;
}

static int commandDelete(const char *path, const char *name) {
    FILE *image = openImage(path, "r+b");
    if (image == NULL) {
        return 1;
    }
    Superblock super;
    Directory directory;
    if (readSuperblock(image, &super) || readDirectory(image, &super, &directory)) {
        fclose(image);
        return 1;
    }
    int slot = findByName(&directory, name);
    if (slot < 0) {
        fprintf(stderr, "Error: There is no \"%s\" on that disk.\n", name);
        free(directory.bytes);
        fclose(image);
        return 1;
    }
    // A deleted entry and a never used one are the same thing: the in use bit goes down
    // and its blocks are free again. The blocks themselves are left as they were, which
    // is worth knowing if anything is ever meant to be private.
    memset(entryAt(&directory, slot), 0, SBFS_ENTRY_BYTES);
    super.freeBlocks = countFree(&directory, &super);
    int failed = writeDirectory(image, &super, &directory) || writeSuperblock(image, &super);
    if (!failed) {
        printf("Deleted \"%s\". %u blocks free.\n", name, super.freeBlocks);
    }
    free(directory.bytes);
    fclose(image);
    return failed;
}

static void printUsage(const char *program) {
    printf("Usage: %s <command> <image> [arguments]\n", program);
    printf("\n");
    printf("Commands:\n");
    printf("  format <image> [blocks] [dirblocks]  Lay down a fresh filesystem.\n");
    printf("  list   <image>                       Show what is on the disk.\n");
    printf("  put    <image> <file> [name]         Put a host file onto it.\n");
    printf("  get    <image> <name> [file]         Take one off it.\n");
    printf("  delete <image> <name>                Remove one.\n");
    printf("\n");
    printf("Blocks are %d bytes. A name may be %d characters. Without one, put uses the\n",
           SBFS_BLOCK_BYTES, SBFS_NAME_BYTES);
    printf("file's own name, which is often too long, and it will say so.\n");
}

// The part of a path after the last separator, so that put can default to a file's own
// name rather than the whole path it was found at.
static const char *baseName(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

int main(int argc, char *argv[]) {
    if (argc < 2 || strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
        printUsage(argv[0]);
        return argc < 2 ? 1 : 0;
    }
    const char *command = argv[1];
    if (argc < 3) {
        fprintf(stderr, "Error: %s needs a disk image.\n", command);
        return 1;
    }
    const char *path = argv[2];

    if (strcmp(command, "format") == 0) {
        long blocks = (argc > 3) ? strtol(argv[3], NULL, 0) : 512;
        long directoryBlocks = (argc > 4) ? strtol(argv[4], NULL, 0) : SBFS_DEFAULT_DIRECTORY_BLOCKS;
        if (blocks < 2 || blocks > 0xFFFF || directoryBlocks < 1 || directoryBlocks > 0xFFFF) {
            fprintf(stderr, "Error: A disk is between 2 and 65535 blocks, with at least"
                            " one of directory.\n");
            return 1;
        }
        return commandFormat(path, (uint16_t)blocks, (uint16_t)directoryBlocks);
    }
    if (strcmp(command, "list") == 0) {
        return commandList(path);
    }
    if (strcmp(command, "put") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Error: put needs a file to put on.\n");
            return 1;
        }
        return commandPut(path, argv[3], (argc > 4) ? argv[4] : baseName(argv[3]));
    }
    if (strcmp(command, "get") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Error: get needs the name of a file on the disk.\n");
            return 1;
        }
        return commandGet(path, argv[3], (argc > 4) ? argv[4] : argv[3]);
    }
    if (strcmp(command, "delete") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Error: delete needs the name of a file on the disk.\n");
            return 1;
        }
        return commandDelete(path, argv[3]);
    }
    fprintf(stderr, "Error: There is no \"%s\" command.\n", command);
    printUsage(argv[0]);
    return 1;
}
