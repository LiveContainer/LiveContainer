#include <errno.h>
#include <fcntl.h>
#include <libkern/OSByteOrder.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static uint32_t roundUp32(uint32_t value, uint32_t alignment) {
    alignment--;
    return (value + alignment) & ~alignment;
}

static const char *lastPathComponent(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

static bool rangeFits(size_t offset, size_t length, size_t totalSize) {
    return offset <= totalSize && length <= totalSize - offset;
}

static bool insertDylibCommand(const char *path, struct mach_header_64 *header, size_t sliceSize, size_t textSectionOffset) {
    const char *name = lastPathComponent(path);
    uint32_t nameLength = (uint32_t)strlen(name) + 1;
    uint32_t commandSize = (uint32_t)sizeof(struct dylib_command) + roundUp32(nameLength, 8);
    size_t headerSize = sizeof(struct mach_header_64);

    if(!rangeFits(headerSize, header->sizeofcmds, sliceSize) ||
       !rangeFits(headerSize, (size_t)header->sizeofcmds + commandSize, sliceSize) ||
       headerSize + (size_t)header->sizeofcmds + commandSize > textSectionOffset) {
        return false;
    }

    struct dylib_command *command = (struct dylib_command *)((uint8_t *)header + headerSize);
    memmove((uint8_t *)command + commandSize, command, header->sizeofcmds);
    memset(command, 0, commandSize);

    command->cmd = LC_ID_DYLIB;
    command->cmdsize = commandSize;
    command->dylib.name.offset = sizeof(struct dylib_command);
    command->dylib.compatibility_version = 0x10000;
    command->dylib.current_version = 0x10000;
    command->dylib.timestamp = 2;
    memcpy((uint8_t *)command + command->dylib.name.offset, name, nameLength);

    header->ncmds++;
    header->sizeofcmds += commandSize;
    return true;
}

static bool replaceDylinkerWithIDDylibCommand(struct dylinker_command *dylinkerCommand, const char *path) {
    const char *name = lastPathComponent(path);
    uint32_t commandSize = dylinkerCommand->cmdsize;
    if(commandSize <= sizeof(struct dylib_command)) {
        return false;
    }

    struct dylib_command *command = (struct dylib_command *)dylinkerCommand;
    uint32_t nameSize = commandSize - (uint32_t)sizeof(struct dylib_command);
    command->cmd = LC_ID_DYLIB;
    command->dylib.name.offset = sizeof(struct dylib_command);
    command->dylib.compatibility_version = 0x10000;
    command->dylib.current_version = 0x10000;
    command->dylib.timestamp = 2;
    memset((uint8_t *)command + command->dylib.name.offset, 0, nameSize);
    strlcpy((char *)command + command->dylib.name.offset, name, nameSize);
    return true;
}

static bool patchExecutableSlice(const char *path, struct mach_header_64 *header, size_t sliceSize) {
    if(sliceSize < sizeof(struct mach_header_64) || header->magic != MH_MAGIC_64) {
        return false;
    }
    if(!rangeFits(sizeof(struct mach_header_64), header->sizeofcmds, sliceSize)) {
        return false;
    }

    header->filetype = MH_DYLIB;
    header->flags |= MH_NO_REEXPORTED_DYLIBS;
    header->flags &= ~MH_PIE;

    bool hasDylibCommand = false;
    bool hasCodeSignatureCommand = false;
    size_t textSectionOffset = 0;
    struct dylinker_command *dylinkerCommand = NULL;

    uint8_t *loadCommandPtr = (uint8_t *)header + sizeof(struct mach_header_64);
    uint8_t *loadCommandsEnd = loadCommandPtr + header->sizeofcmds;
    for(uint32_t i = 0; i < header->ncmds; i++) {
        if(loadCommandPtr + sizeof(struct load_command) > loadCommandsEnd) {
            return false;
        }

        struct load_command *command = (struct load_command *)loadCommandPtr;
        if(command->cmdsize < sizeof(struct load_command) || loadCommandPtr + command->cmdsize > loadCommandsEnd) {
            return false;
        }

        if(command->cmd == LC_ID_DYLIB) {
            hasDylibCommand = true;
        } else if(command->cmd == LC_CODE_SIGNATURE) {
            hasCodeSignatureCommand = true;
        } else if(command->cmd == LC_LOAD_DYLINKER) {
            dylinkerCommand = (struct dylinker_command *)command;
        } else if(command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
            struct segment_command_64 *segment = (struct segment_command_64 *)command;
            if(segment->vmaddr == 0 && strncmp(segment->segname, "__PAGEZERO", sizeof(segment->segname)) == 0) {
                // Keep the segment count stable so LC_DYLD_CHAINED_FIXUPS still
                // describes the same segments, but shrink PAGEZERO enough to map.
                segment->vmaddr = 0x100000000 - 0x4000;
                segment->vmsize = 0x4000;
                memset(segment->segname, 0, sizeof(segment->segname));
                strlcpy(segment->segname, "__PAGEZER0", sizeof(segment->segname));
            } else if(strncmp(segment->segname, SEG_TEXT, sizeof(segment->segname)) == 0) {
                uint8_t *sectionPtr = loadCommandPtr + sizeof(struct segment_command_64);
                if(sectionPtr + (size_t)segment->nsects * sizeof(struct section_64) > loadCommandPtr + command->cmdsize) {
                    return false;
                }
                for(uint32_t j = 0; j < segment->nsects; j++) {
                    struct section_64 *section = (struct section_64 *)(sectionPtr + (size_t)j * sizeof(struct section_64));
                    if(strncmp(section->sectname, SECT_TEXT, sizeof(section->sectname)) == 0) {
                        textSectionOffset = section->offset;
                        break;
                    }
                }
            }
        }

        loadCommandPtr += command->cmdsize;
    }

    if(!hasDylibCommand) {
        bool inserted = false;
        if(textSectionOffset > 0 && loadCommandPtr <= (uint8_t *)header + textSectionOffset) {
            size_t freeLoadCommandBytes = (size_t)((uint8_t *)header + textSectionOffset - loadCommandPtr);
            if(!hasCodeSignatureCommand && freeLoadCommandBytes >= 0x10) {
                freeLoadCommandBytes -= 0x10;
            }

            const char *name = lastPathComponent(path);
            uint32_t commandSize = (uint32_t)sizeof(struct dylib_command) + roundUp32((uint32_t)strlen(name) + 1, 8);
            if(freeLoadCommandBytes >= commandSize) {
                inserted = insertDylibCommand(path, header, sliceSize, textSectionOffset);
            }
        }

        if(!inserted && (!dylinkerCommand || !replaceDylinkerWithIDDylibCommand(dylinkerCommand, path))) {
            fprintf(stderr, "Unable to add LC_ID_DYLIB to %s\n", path);
            return false;
        }
    }

    return true;
}

static bool patchFile(const char *path) {
    int fd = open(path, O_RDWR);
    if(fd < 0) {
        perror("open");
        return false;
    }

    struct stat st;
    if(fstat(fd, &st) != 0 || st.st_size <= 0) {
        perror("fstat");
        close(fd);
        return false;
    }

    void *map = mmap(NULL, (size_t)st.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if(map == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return false;
    }

    bool patched = false;
    uint32_t magic = *(uint32_t *)map;
    if(magic == FAT_CIGAM) {
        struct fat_header *fatHeader = (struct fat_header *)map;
        uint32_t archCount = OSSwapInt32(fatHeader->nfat_arch);
        struct fat_arch *arch = (struct fat_arch *)((uint8_t *)map + sizeof(struct fat_header));
        for(uint32_t i = 0; i < archCount; i++, arch++) {
            uint32_t offset = OSSwapInt32(arch->offset);
            uint32_t size = OSSwapInt32(arch->size);
            if(OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64 && rangeFits(offset, size, (size_t)st.st_size)) {
                patched |= patchExecutableSlice(path, (struct mach_header_64 *)((uint8_t *)map + offset), size);
            }
        }
    } else if(magic == MH_MAGIC_64) {
        patched = patchExecutableSlice(path, (struct mach_header_64 *)map, (size_t)st.st_size);
    }

    if(patched && msync(map, (size_t)st.st_size, MS_SYNC) != 0) {
        perror("msync");
        patched = false;
    }

    munmap(map, (size_t)st.st_size);
    close(fd);
    return patched;
}

int main(int argc, char **argv) {
    if(argc != 2) {
        fprintf(stderr, "Usage: %s /path/to/SideStore\n", argv[0]);
        return 1;
    }

    if(!patchFile(argv[1])) {
        fprintf(stderr, "Failed to patch %s\n", argv[1]);
        return 1;
    }

    printf("Patched %s successfully\n", argv[1]);
    return 0;
}
