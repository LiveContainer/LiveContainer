@import UniformTypeIdentifiers;
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "utils.h"
#import "../LiveContainer/FoundationPrivate.h"

BOOL fixFilePicker;
__attribute__((constructor))
static void NSFMGuestHooksInit() {
    if(!NSUserDefaults.lcGuestAppId) return;
    fixFilePicker = [NSUserDefaults.guestAppInfo[@"doSymlinkInbox"] boolValue];
    
    swizzle(UIDocumentPickerViewController.class, @selector(initForOpeningContentTypes:asCopy:), @selector(hook_initForOpeningContentTypes:asCopy:));
    SEL legacyInitSelector = NSSelectorFromString(@"initWithDocumentTypes:inMode:");
    if ([UIDocumentPickerViewController instancesRespondToSelector:legacyInitSelector]) {
        swizzle(UIDocumentPickerViewController.class, legacyInitSelector, @selector(hook_initWithDocumentTypes:inMode:));
    }
    swizzle(UIDocumentBrowserViewController.class, @selector(initForOpeningContentTypes:), @selector(hook_initForOpeningContentTypes));
    swizzleClassMethod(UTType.class, @selector(typeWithIdentifier:), @selector(hook_typeWithIdentifier:));
    if (fixFilePicker) {
        swizzle(NSURL.class, @selector(startAccessingSecurityScopedResource), @selector(hook_startAccessingSecurityScopedResource));
        swizzle(UIDocumentPickerViewController.class, @selector(setAllowsMultipleSelection:), @selector(hook_setAllowsMultipleSelection:));
    }
    if ([NSUserDefaults.guestAppInfo[@"fixFilePickerNew"] boolValue] || NSUserDefaults.isSideStore) {
        swizzle(DOCConfiguration.class, @selector(setHostIdentifier:), @selector(hook_setHostIdentifier:));
    }

}

@implementation UIDocumentPickerViewController(LiveContainerHook)

- (instancetype)hook_initForOpeningContentTypes:(NSArray<UTType *> *)contentTypes asCopy:(BOOL)asCopy {
    
    // prevent crash when selecting only folder
    BOOL shouldMultiselect = NO;
    if (fixFilePicker && [contentTypes count] == 1 && contentTypes[0] == UTTypeFolder) {
        shouldMultiselect = YES;
    }
    
    // if app is going to choose any unrecognized file type, then we replace it with @[UTTypeItem, UTTypeFolder];
    NSArray<UTType *> * contentTypesNew = @[UTTypeItem, UTTypeFolder];
    

    
    if(fixFilePicker) {
        UIDocumentPickerViewController* ans = [self hook_initForOpeningContentTypes:contentTypesNew asCopy:YES];
        if(shouldMultiselect) {
            [ans hook_setAllowsMultipleSelection:YES];
        }
        return ans;
    } else {
        return [self hook_initForOpeningContentTypes:contentTypesNew asCopy:asCopy];
    }
}

- (instancetype)hook_initWithDocumentTypes:(NSArray *)contentTypes inMode:(NSUInteger)mode {
    NSMutableArray<UTType *> *resolvedTypes = [NSMutableArray array];
    for (id item in contentTypes) {
        if ([item isKindOfClass:UTType.class]) {
            [resolvedTypes addObject:(UTType *)item];
            continue;
        }
        if (![item isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *identifier = (NSString *)item;
        UTType *resolved = [UTType typeWithIdentifier:identifier];
        if (!resolved) {
            resolved = [UTType exportedTypeWithIdentifier:identifier];
        }
        if (!resolved) {
            resolved = [UTType importedTypeWithIdentifier:identifier];
        }
        if (resolved) {
            [resolvedTypes addObject:resolved];
        }
    }
    if (resolvedTypes.count == 0) {
        [resolvedTypes addObjectsFromArray:@[UTTypeItem, UTTypeFolder]];
    }
    return [self initForOpeningContentTypes:resolvedTypes asCopy:(mode == 1 ? NO : YES)];
}

- (void)hook_setAllowsMultipleSelection:(BOOL)allowsMultipleSelection {
    if([self allowsMultipleSelection]) {
        return;
    }
    [self hook_setAllowsMultipleSelection:YES];
}

@end


@implementation UIDocumentBrowserViewController(LiveContainerHook)

- (instancetype)hook_initForOpeningContentTypes:(NSArray<UTType *> *)contentTypes {
    NSArray<UTType *> * contentTypesNew = @[UTTypeItem, UTTypeFolder];
    return [self hook_initForOpeningContentTypes:contentTypesNew];
}

@end


@implementation NSURL(LiveContainerHook)

- (BOOL)hook_startAccessingSecurityScopedResource {
    [self hook_startAccessingSecurityScopedResource];
    return YES;
}

@end

@implementation UTType(LiveContainerHook)

+(instancetype)hook_typeWithIdentifier:(NSString*)identifier {
    UTType* ans = [UTType hook_typeWithIdentifier:identifier];
    // imported / exported TypeWithIdentifier calls ___UTGetDeclarationStatusFromInfoPlist which directly creates types without tags from Info.plist
    if(ans) {
        return ans;
    } else if((ans = [UTType exportedTypeWithIdentifier:identifier])) {
        return ans;
    } else {
        return [UTType importedTypeWithIdentifier:identifier];
    }
}

@end


@implementation DOCConfiguration(LiveContainerHook)

- (void)hook_setHostIdentifier:(NSString *)ignored {
    CFErrorRef error = NULL;
    void* taskSelf = SecTaskCreateFromSelf(NULL);
    CFTypeRef value = SecTaskCopyValueForEntitlement(taskSelf, CFSTR("application-identifier"), &error);
    CFRelease(taskSelf);
    if (value) {
        NSString *entStr = (__bridge NSString *)value;
        CFRelease(value);
        NSRange dotRange = [entStr rangeOfString:@"."];
        if (dotRange.location != NSNotFound) {
               NSString *result = [entStr substringFromIndex:dotRange.location + 1];
            [self hook_setHostIdentifier:result];
        } else {
            [self hook_setHostIdentifier:entStr];
        }
    } else if (error) {
        NSLog(@"Error fetching entitlement: %@", error);
        CFRelease(error);
        [self hook_setHostIdentifier:ignored];
    }
}

@end
