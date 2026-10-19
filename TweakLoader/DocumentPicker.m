@import UniformTypeIdentifiers;
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "../LiveContainer/utils.h"
#import "../LiveContainer/FoundationPrivate.h"

BOOL fixFilePicker;
static BOOL openFilesInPlace;
__attribute__((constructor))
static void NSFMGuestHooksInit() {
    if(!NSUserDefaults.lcGuestAppId) return;
    openFilesInPlace = [NSUserDefaults.guestAppInfo[@"openFilesInPlace"] boolValue];
    fixFilePicker = [NSUserDefaults.guestAppInfo[@"doSymlinkInbox"] boolValue] && !openFilesInPlace;
    
    swizzle(UIDocumentPickerViewController.class, @selector(initForOpeningContentTypes:asCopy:), @selector(hook_initForOpeningContentTypes:asCopy:));
    swizzle(UIDocumentPickerViewController.class, @selector(initWithDocumentTypes:inMode:), @selector(hook_initWithDocumentTypes:inMode:));
    swizzle(UIDocumentBrowserViewController.class, @selector(initForOpeningContentTypes:), @selector(hook_initForOpeningContentTypes));
    swizzleClassMethod(UTType.class, @selector(typeWithIdentifier:), @selector(hook_typeWithIdentifier:));
    if (fixFilePicker) {
        swizzle(NSURL.class, @selector(startAccessingSecurityScopedResource), @selector(hook_startAccessingSecurityScopedResource));
        swizzle(UIDocumentPickerViewController.class, @selector(setAllowsMultipleSelection:), @selector(hook_setAllowsMultipleSelection:));
    }
    if (openFilesInPlace || [NSUserDefaults.guestAppInfo[@"fixFilePickerNew"] boolValue] || NSUserDefaults.isSideStore) {
        swizzle(DOCConfiguration.class, @selector(setHostIdentifier:), @selector(hook_setHostIdentifier:));
    }

}

@implementation UIDocumentPickerViewController(LiveContainerHook)

- (instancetype)hook_initForOpeningContentTypes:(NSArray<UTType *> *)contentTypes asCopy:(BOOL)asCopy {
    if (openFilesInPlace) {
        return [self hook_initForOpeningContentTypes:contentTypes asCopy:asCopy];
    }
    
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

- (instancetype)hook_initWithDocumentTypes:(NSArray<UTType *> *)contentTypes inMode:(NSUInteger)mode {
    if (openFilesInPlace) { return [self hook_initWithDocumentTypes:contentTypes inMode:mode]; }
    return [self initForOpeningContentTypes:contentTypes asCopy:(mode == 1 ? NO : YES)];
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
    if (openFilesInPlace) { return [self hook_initForOpeningContentTypes:contentTypes]; }
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
        NSString *entStr = [(__bridge NSString *)value copy];
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
    } else {
        [self hook_setHostIdentifier:ignored];
    }
}

@end
