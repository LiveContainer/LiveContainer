#import "utils.h"
#include <mach/mach.h>

void __assert_rtn(const char* func, const char* file, int line, const char* failedexpr) {
    [NSException raise:NSInternalInconsistencyException format:@"Assertion failed: (%s), file %s, line %d.\n", failedexpr, file, line];
    abort(); // silent compiler warning
}

bool LCAddressRangeIsReadable(const void *address, size_t length) {
    if(!address || length == 0) {
        return false;
    }

    uintptr_t start = (uintptr_t)address;
    if(start < 0x4000 || length > UINTPTR_MAX - start) {
        return false;
    }

    uintptr_t end = start + length;
    uintptr_t cursor = start;
    while(cursor < end) {
        vm_address_t region = (vm_address_t)cursor;
        vm_size_t regionLength = 0;
        struct vm_region_submap_short_info_64 info;
        mach_msg_type_number_t infoCount = VM_REGION_SUBMAP_SHORT_INFO_COUNT_64;
        natural_t depth = 0;
        kern_return_t kr = vm_region_recurse_64(mach_task_self(), &region, &regionLength, &depth, (vm_region_recurse_info_t)&info, &infoCount);
        if(kr != KERN_SUCCESS || !(info.protection & VM_PROT_READ)) {
            return false;
        }

        uintptr_t regionStart = (uintptr_t)region;
        if(cursor < regionStart || regionLength > UINTPTR_MAX - regionStart) {
            return false;
        }

        uintptr_t regionEnd = regionStart + (uintptr_t)regionLength;
        if(regionEnd <= cursor) {
            return false;
        }

        cursor = regionEnd < end ? regionEnd : end;
    }

    return true;
}

bool LCReadPointer(const void *address, void **value) {
    if(!value || !LCAddressRangeIsReadable(address, sizeof(void *))) {
        return false;
    }

    *value = *(void * const *)address;
    return true;
}

uint64_t aarch64_get_tbnz_jump_address(uint32_t instruction, uint64_t pc) {
    // Check that this is a tbnz instruction
    if ((instruction & 0xFF000000) != 0x37000000) {
        return 0;
    }

    uint32_t imm = ((instruction >> 5) & 0xFFFF) * 4;
    return imm + pc;
}

// https://github.com/pinauten/PatchfinderUtils/blob/master/Sources/CFastFind/CFastFind.c
//
//  CFastFind.c
//  CFastFind
//
//  Created by Linus Henze on 2021-10-16.
//  Copyright © 2021 Linus Henze. All rights reserved.
//

/**
 * Emulate an adrp instruction at the given pc value
 * Returns adrp destination
 */
uint64_t aarch64_emulate_adrp(uint32_t instruction, uint64_t pc) {
    // Check that this is an adrp instruction
    if ((instruction & 0x9F000000) != 0x90000000) {
        return 0;
    }
    
    // Calculate imm from hi and lo
    int32_t imm_hi_lo = (instruction & 0xFFFFE0) >> 3;
    imm_hi_lo |= (instruction & 0x60000000) >> 29;
    if (instruction & 0x800000) {
        // Sign extend
        imm_hi_lo |= 0xFFE00000;
    }
    
    // Build real imm
    int64_t imm = ((int64_t) imm_hi_lo << 12);
    
    // Emulate
    return (pc & ~(0xFFFULL)) + imm;
}

bool aarch64_emulate_add_imm(uint32_t instruction, uint32_t *dst, uint32_t *src, uint32_t *imm) {
    // Check that this is an add instruction with immediate
    if ((instruction & 0xFF000000) != 0x91000000) {
        return 0;
    }
    
    int32_t imm12 = (instruction & 0x3FFC00) >> 10;
    
    uint8_t shift = (instruction & 0xC00000) >> 22;
    switch (shift) {
        case 0:
            *imm = imm12;
            break;
            
        case 1:
            *imm = imm12 << 12;
            break;
            
        default:
            return false;
    }
    
    *dst = instruction & 0x1F;
    *src = (instruction >> 5) & 0x1F;
    
    return true;
}

/**
 * Emulate an adrp and add instruction at the given pc value
 * Returns destination
 */

uint64_t aarch64_emulate_adrp_add(uint32_t instruction, uint32_t addInstruction, uint64_t pc) {
    uint64_t adrp_target = aarch64_emulate_adrp(instruction, pc);
    if (!adrp_target) {
        return 0;
    }
    
    uint32_t addDst;
    uint32_t addSrc;
    uint32_t addImm;
    if (!aarch64_emulate_add_imm(addInstruction, &addDst, &addSrc, &addImm)) {
        return 0;
    }
    
    if ((instruction & 0x1F) != addSrc) {
        return 0;
    }
    
    // Emulate
    return adrp_target + (uint64_t) addImm;
}

/**
 * Emulate an adrp and ldr instruction at the given pc value
 * Returns destination
 */

uint64_t aarch64_emulate_adrp_ldr(uint32_t instruction, uint32_t ldrInstruction, uint64_t pc) {
    uint64_t adrp_target = aarch64_emulate_adrp(instruction, pc);
    if (!adrp_target) {
        return 0;
    }
    
    if ((instruction & 0x1F) != ((ldrInstruction >> 5) & 0x1F)) {
        return 0;
    }
    
    if ((ldrInstruction & 0xFFC00000) != 0xF9400000) {
        return 0;
    }
    
    uint32_t imm12 = ((ldrInstruction >> 10) & 0xFFF) << 3;
    
    // Emulate
    return adrp_target + (uint64_t) imm12;
}


@implementation NSDictionary(lc)

- (BOOL)writeBinToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    NSError* err = 0;
    NSData* plistData = [NSPropertyListSerialization dataWithPropertyList:self format:NSPropertyListBinaryFormat_v1_0 options:0 error:&err];
    if(!err && plistData) {
        return [plistData writeToFile:path atomically:YES];
    } else {
        return NO;
    }
}

@end

