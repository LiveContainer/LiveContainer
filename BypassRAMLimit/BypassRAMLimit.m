//
//  main.m
//  LiveContainer
//
//  Created by Duy Tran on 3/10/26.
//
@import Foundation;
#import "../LiveContainer/FoundationPrivate.h"
#import "../LiveContainer/UIKitPrivate.h"
#import "../LiveContainer/LCSharedUtils.h"
#import "../LiveContainer/utils.h"

static const vm_size_t kRegionSize = 1ull * 1024 * 1024 * 1024;

@interface LCShmemItem : NSExtensionItem
+ (instancetype)itemWithMemory:(xpc_object_t)mem;
- (xpc_object_t)memory;
@end

@interface LiveProcessHandler : NSObject<NSExtensionRequestHandling>
+ (NSExtensionContext *)extensionContext;
+ (NSDictionary *)retrievedAppInfo;
@end

int main(void) {
    Class LiveProcessHandler = NSClassFromString(@"LiveProcessHandler");
    NSExtensionContext *context = [LiveProcessHandler extensionContext];
    
    NSMutableArray *shmemArray = [NSMutableArray array];
    for (int i = 0; i < NSProcessInfo.processInfo.physicalMemory / kRegionSize; i++) {
        vm_address_t addr;
        kern_return_t kr = vm_allocate(mach_task_self(), &addr, kRegionSize, VM_FLAGS_ANYWHERE);
        if (kr != KERN_SUCCESS) break;
        xpc_object_t mem = xpc_shmem_create((void *)addr, kRegionSize);
        shmemArray[i] = [LCShmemItem itemWithMemory:mem];
    }
    NSLog(@"Sending mem array: %@", shmemArray);
    [context completeRequestReturningItems:shmemArray completionHandler:^(BOOL expired) {
        NSLog(@"Completion handler");
    }];
    
    CFRunLoopRun();
    return 0;
}

@implementation LCShmemItem
+ (BOOL)supportsSecureCoding { return YES; }

+ (instancetype)itemWithMemory:(xpc_object_t)mem {
    LCShmemItem *item = [self new];
    item.userInfo = @{@"shmem": mem};
    return item;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [(NSXPCCoder *)coder encodeXPCObject:self.userInfo[@"shmem"]
                                forKey:@"shmem"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        xpc_object_t mem = [(NSXPCCoder *)coder
            decodeXPCObjectOfType:XPC_TYPE_SHMEM forKey:@"shmem"];
        if (!mem) return nil;
        self.userInfo = @{@"shmem": mem};
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    LCShmemItem *copy = [[[self class] allocWithZone:zone] init];
    copy.userInfo = self.userInfo;
    return copy;
}

- (NSString *)description {
    return [self.memory description];
}

- (xpc_object_t)memory {
    return self.userInfo[@"shmem"];
}
@end

#pragma mark - Code to be called from LiveContainer to spawn this payload
@implementation NSExtension(BypassRAMLimitPayload)
+ (void)spawnBypassRAMLimitPayload {
    __block NSError *error;
    NSExtension *ext = [NSExtension extensionWithIdentifier:[PrivClass(LCSharedUtils) liveProcessBundleIdentifier] error:&error];
    if (!ext) {
        NSLog(@"BypassRAMLimit: LiveProcess not found");
        return;
    }

    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{
        @"customPayloadDylib": @"@rpath/BypassRAMLimit.framework/BypassRAMLimit",
        @"customPayloadEntry": @"main"
    };
    ext.requestCompletionBlock = ^(NSUUID *uuid, NSArray *items) {
        for (LCShmemItem *item in items) {
            NSLog(@"Got mem: %@", item);
            void *map;
            size_t size = xpc_shmem_map(item.memory, &map);
            NSLog(@"Mapped shmem %p size 0x%zx (%@)", map, size, size==kRegionSize ? @"OK":@"Fail?");
//            for(uint64_t i = 0; i < size; i+=PAGE_SIZE) {
//                ((uint8_t*)map)[i] = 0;
//            }
            bzero(map, size);
        }
        NSLog(@"BypassRAMLimit: requestCompletionBlock");
    };
    ext.requestCancellationBlock = ^(NSUUID *uuid, NSError *e) {
        NSLog(@"BypassRAMLimit: requestCancellationBlock: %@", e);
    };
    ext.requestInterruptionBlock = ^(NSUUID *uuid) {
        NSLog(@"BypassRAMLimit: requestInterruptionBlock");
    };
    [ext beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *uuid) {
        CFRunLoopStop(CFRunLoopGetMain());
    }];
    CFRunLoopRun();
}
@end
