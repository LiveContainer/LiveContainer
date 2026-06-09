#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <libgen.h>
#include <unistd.h>
#include <stdbool.h>

static uint32_t rnd32(uint32_t v, uint32_t r) {
    r--;
    return (v + r) & ~r;
}

static void insertDylibCommand(uint32_t cmd, const char *path, struct mach_header_64 *header) {
    const char *name = cmd==LC_ID_DYLIB ? basename((char *)path) : path;
    struct dylib_command *dylib;
    size_t cmdsize = sizeof(struct dylib_command) + rnd32((uint32_t)strlen(name) + 1, 8);
    if (cmd == LC_ID_DYLIB) {
        dylib = (struct dylib_command *)(sizeof(struct mach_header_64) + (uintptr_t)header);
        memmove((void *)((uintptr_t)dylib + cmdsize), (void *)dylib, header->sizeofcmds);
        bzero(dylib, cmdsize);
    } else {
        dylib = (struct dylib_command *)(sizeof(struct mach_header_64) + (void *)header+header->sizeofcmds);
    }
    dylib->cmd = cmd;
    dylib->cmdsize = cmdsize;
    dylib->dylib.name.offset = sizeof(struct dylib_command);
    dylib->dylib.compatibility_version = 0x10000;
    dylib->dylib.current_version = 0x10000;
    dylib->dylib.timestamp = 2;
    strncpy((void *)dylib + dylib->dylib.name.offset, name, strlen(name));
    header->ncmds++;
    header->sizeofcmds += dylib->cmdsize;
}

static void replaceDylinkerWithIDDylibCommand(struct dylinker_command* dylinkerCommand, const char *path) {
    uint32_t size = dylinkerCommand->cmdsize;
    struct dylib_command* newDylibCommand = (struct dylib_command*)dylinkerCommand;
    newDylibCommand->cmd = LC_ID_DYLIB;
    newDylibCommand->dylib.name.offset = sizeof(struct dylib_command);
    newDylibCommand->dylib.compatibility_version = 0x10000;
    newDylibCommand->dylib.current_version = 0x10000;
    newDylibCommand->dylib.timestamp = 2;
    uint32_t nameSize = size - sizeof(struct dylib_command);
    const char* name = basename((char *)path);
    strncpy((void *)newDylibCommand + newDylibCommand->dylib.name.offset, name, nameSize);
    *((char *)newDylibCommand + newDylibCommand->dylib.name.offset + nameSize - 1) = 0;
}

int LCPatchExecSlice(const char *path, struct mach_header_64 *header) {
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    if (header->magic == MH_MAGIC_64) {
        header->filetype = MH_DYLIB;
        header->flags |= MH_NO_REEXPORTED_DYLIBS;
        header->flags &= ~MH_PIE;
    }
    struct segment_command_64 *seg = (struct segment_command_64 *)imageHeaderPtr;
    if (seg->cmd == LC_SEGMENT_64 && seg->vmaddr == 0) {
        seg->vmaddr = 0x100000000 - 0x4000;
        seg->vmsize = 0x4000;
        strncpy(seg->segname, "__PAGEZER0", 16);
    }

    bool hasDylibCommand = false;
    int textSectionOffest = 0;
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    struct dylinker_command* dylinkerCommand = 0;
    bool codeSignatureCommandFound = false;
    for(int i = 0; i < header->ncmds; i++) {
        if(command->cmd == LC_ID_DYLIB) {
            hasDylibCommand = true;
        } else if(command->cmd == LC_SEGMENT_64) {
            struct segment_command_64* seglc = (struct segment_command_64*)command;
            if (strcmp("__TEXT", seglc->segname) == 0) {
                for (uint32_t j = 0; j < seglc->nsects; j++) {
                    struct section_64* sect = (struct section_64*)(((void*)command + sizeof(struct segment_command_64) + sizeof(struct section_64) * j));
                    if (0 == strcmp("__text", sect->sectname)) {
                        textSectionOffest = sect->offset;
                    }
                }
            }
        } else if (command->cmd == LC_CODE_SIGNATURE) {
            codeSignatureCommandFound = true;
        } else if (command->cmd == LC_LOAD_DYLINKER) {
            dylinkerCommand = (struct dylinker_command*)command;
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }
    long freeLoadCommandCountLeft = (void*)header + textSectionOffest - (void*)command;
    if(!codeSignatureCommandFound) freeLoadCommandCountLeft -= 0x10;

    int idDylibCommandSize = sizeof(struct dylib_command) + rnd32((uint32_t)strlen(basename((char*)path)) + 1, 8);
    if(!hasDylibCommand) {
        if (freeLoadCommandCountLeft >= idDylibCommandSize) {
            freeLoadCommandCountLeft -= idDylibCommandSize;
            insertDylibCommand(LC_ID_DYLIB, path, header);
        } else if (dylinkerCommand) {
            replaceDylinkerWithIDDylibCommand(dylinkerCommand, path);
        }
    }
    return 0;
}

int main(int argc, char** argv) {
    if(argc < 2) return 1;
    const char *path = argv[1];
    int fd = open(path, O_RDWR, 0600);
    if(fd < 0) return 1;
    struct stat s;
    fstat(fd, &s);
    void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) return 1;
    uint32_t magic = *(uint32_t *)map;
    if (magic == FAT_CIGAM) {
        struct fat_header *header = (struct fat_header *)map;
        struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
        for (int i = 0; i < OSSwapInt32(header->nfat_arch); i++) {
            if (OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                LCPatchExecSlice(path, (struct mach_header_64 *)(map + OSSwapInt32(arch->offset)));
            }
            arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
        }
    } else if (magic == MH_MAGIC_64) {
        LCPatchExecSlice(path, (struct mach_header_64 *)map);
    }
    msync(map, s.st_size, MS_SYNC);
    munmap(map, s.st_size);
    close(fd);
    printf("Patched %s successfully\n", path);
    return 0;
}
