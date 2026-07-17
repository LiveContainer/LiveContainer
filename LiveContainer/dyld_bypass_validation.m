// Based on: https://blog.xpnsec.com/restoring-dyld-memory-loading
// https://github.com/xpn/DyldDeNeuralyzer/blob/main/DyldDeNeuralyzer/DyldPatch/dyldpatch.m

#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach/mach.h>
#include <sys/syscall.h>

#include "dyld_bypass_validation.h"
#include "litehook.h"
#include "utils.h"

static int (*orig_fcntl)(int fildes, int cmd, void *param) = 0;

// Originated from _kernelrpc_mach_vm_protect_trap
ASM(
.global _builtin_vm_protect \n
_builtin_vm_protect:     \n
    mov x16, #-0xe       \n
    svc #0x80            \n
    ret
);

static bool redirectFunction(char *name, void *patchAddr, void *target) {
    kern_return_t kr = litehook_hook_function(patchAddr, target);
    if (kr == KERN_SUCCESS) {
        NSLog(@"[DyldLVBypass] hook %s succeed!", name);
    } else {
        NSLog(@"[DyldLVBypass] hook %s failed: %d", name, kr);
    }
    return kr == KERN_SUCCESS;
}

static bool hasProtection(vm_address_t regionAddress, vm_prot_t requiredProtection) {
    vm_size_t regionSize = 0;
    natural_t depth = 0;
    vm_region_submap_short_info_data_64_t regionInfo;
    mach_msg_type_number_t infoCount = VM_REGION_SUBMAP_SHORT_INFO_COUNT_64;
    kern_return_t kr = vm_region_recurse_64(mach_task_self(), &regionAddress, &regionSize,
                                            &depth, (vm_region_recurse_info_t)&regionInfo,
                                            &infoCount);
    if (kr != KERN_SUCCESS || regionSize == 0 ||
        (regionInfo.protection & requiredProtection) != requiredProtection ||
        (regionInfo.max_protection & requiredProtection) != requiredProtection) {
        return false;
    }
    return true;
}

static void* hooked_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset) {
    void *map = __mmap(addr, len, prot, flags, fd, offset);
    if (fd && (prot & PROT_EXEC) && (map == MAP_FAILED || !hasProtection((vm_address_t)map, PROT_EXEC))) {
        map = __mmap(addr, len, PROT_READ | PROT_WRITE, flags | MAP_PRIVATE | MAP_ANON, 0, 0);
        void *memoryLoadedFile = __mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, offset);
        memcpy(map, memoryLoadedFile, len);
        munmap(memoryLoadedFile, len);
        mprotect(map, len, prot);
        assert(hasProtection((vm_address_t)map, PROT_EXEC));
    }
    return map;
}

static int hooked___fcntl(int fildes, int cmd, void *param) {
    if (cmd == F_ADDFILESIGS_RETURN) {
#if !(TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR)
        // attempt to attach code signature on iOS only as the binaries may have been signed
        // on macOS, attaching on unsigned binaries without CS_DEBUGGED will crash
        orig_fcntl(fildes, cmd, param);
#endif
        fsignatures_t *fsig = (fsignatures_t*)param;
        // called to check that cert covers file.. so we'll make it cover everything ;)
        fsig->fs_file_start = 0xFFFFFFFF;
        return 0;
    }

    // Signature sanity check by dyld
    else if (cmd == F_CHECK_LV) {
        //orig_fcntl(fildes, cmd, param);
        // Just say everything is fine
        return 0;
    }
    
    // If for another command or file, we pass through
    return orig_fcntl(fildes, cmd, param);
}

char *searchDyldFunction(char *base, char *signature, int length) {
    char *patchAddr = NULL;
    for(int i=0; i < 0x80000; i+=4) {
        if (base[i] == signature[0] && memcmp(base+i, signature, length) == 0) {
            patchAddr = base + i;
            break;
        }
    }
    return patchAddr;
}

void init_bypassDyldLibValidation(void) {
    static BOOL bypassed;
    if (bypassed) return;
    bypassed = YES;

    NSLog(@"[DyldLVBypass] init");
    
    // Modifying exec page during execution may cause SIGBUS, so ignore it now
    // Only comment this out if only one thread (main) is running
    //signal(SIGBUS, SIG_IGN);
    
    orig_fcntl = __fcntl;
    //redirectFunction("mmap", mmap, hooked_mmap);
    //redirectFunction("fcntl", fcntl, hooked_fcntl);

    searchDyldFunctions();

    assert(orig_dyld_mmap);
    assert(orig_dyld_fcntl);

    redirectFunction("dyld_fcntl", orig_dyld_fcntl, hooked___fcntl);
    redirectFunction("dyld_mmap", orig_dyld_mmap, hooked_mmap);
}

void searchDyldFunctions(void) {
    if(orig_dyld_fcntl && orig_dyld_mmap) return;
    
    // TODO: cache offset and litehook_find_dsc_symbol
    char *dyldBase = (char *)_alt_dyld_get_all_image_infos()->dyldImageLoadAddress;
    orig_dyld_fcntl = (void *)searchDyldFunction(dyldBase, fcntlSig, sizeof(fcntlSig));
    orig_dyld_mmap = (void *)searchDyldFunction(dyldBase, mmapSig, sizeof(mmapSig));
    
    // dopamine already hooked it, try to find its hook instead
    if(!orig_dyld_fcntl) {
        char* fcntlAddr = 0;
        // search all syscalls and see if the the instruction before it is a branch instruction
        for(int i=0; i < 0x80000; i+=4) {
            if (dyldBase[i] == syscallSig[0] && memcmp(dyldBase+i, syscallSig, 4) == 0) {
                char* syscallAddr = dyldBase + i;
                uint32_t* prev = (uint32_t*)(syscallAddr - 4);
                if(*prev >> 26 == 0x5) {
                    fcntlAddr = (char*)prev;
                    break;
                }
            }
        }
        
        if(fcntlAddr) {
            uint32_t* inst = (uint32_t*)fcntlAddr;
            int32_t offset = ((int32_t)((*inst)<<6))>>4;
            NSLog(@"[DyldLVBypass] Dopamine hook offset = %x", offset);
            orig_fcntl = (void*)((char*)fcntlAddr + offset);
            orig_dyld_fcntl = (void *)fcntlAddr;
        } else {
            NSLog(@"[DyldLVBypass] Dopamine hook not found");
        }
    }
}
