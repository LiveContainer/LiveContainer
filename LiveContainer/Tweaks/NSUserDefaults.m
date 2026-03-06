//
//  NSUserDefaults.m
//  LiveContainer
//
//  Created by s s on 2024/11/29.
//

#import "FoundationPrivate.h"
#import "LCMachOUtils.h"
#import "LCSharedUtils.h"
#import "utils.h"
#import "../../litehook/src/litehook.h"
#include "Tweaks.h"
#include <mach-o/dyld.h>
@import ObjectiveC;
@import MachO;

BOOL hook_return_false(void) {
    return NO;
}

// void swizzle(Class class, SEL originalAction, SEL swizzledAction) {
//     method_exchangeImplementations(class_getInstanceMethod(class, originalAction), class_getInstanceMethod(class, swizzledAction));
// }

// void swizzle2(Class class, SEL originalAction, Class class2, SEL swizzledAction) {
//     Method m1 = class_getInstanceMethod(class2, swizzledAction);
//     class_addMethod(class, swizzledAction, method_getImplementation(m1), method_getTypeEncoding(m1));
//     method_exchangeImplementations(class_getInstanceMethod(class, originalAction), class_getInstanceMethod(class, swizzledAction));
// }

NSURL* appContainerURL = 0;
NSString* appContainerPath = 0;
static bool isAppleIdentifier(NSString* identifier);

static id (*orig_CKContainer_setupWithContainerID_options)(id, SEL, id, id) = nil;
static id (*orig_CKContainer_initWithContainerIdentifier)(id, SEL, id) = nil;
static id (*orig_CKEntitlements_initWithEntitlementsDict)(id, SEL, NSDictionary *) = nil;
static id (*orig_NSUserDefaults_initWithSuiteName_container)(id, SEL, NSString *, NSURL *) = nil;

static os_unfair_lock lcRegramCompatHookLock = OS_UNFAIR_LOCK_INIT;
static BOOL lcCKContainerSetupHooked = NO;
static BOOL lcCKContainerInitHooked = NO;
static BOOL lcCKEntitlementsHooked = NO;
static BOOL lcNSDefaultsContainerHooked = NO;

static BOOL LCShouldUseInstagramCloudKitWorkaround(void) {
    static dispatch_once_t onceToken;
    static BOOL shouldUse = NO;
    dispatch_once(&onceToken, ^{
        NSString *guestBundleID = NSUserDefaults.lcGuestAppId.lowercaseString ?: @"";
        NSString *mainBundleID = NSBundle.mainBundle.bundleIdentifier.lowercaseString ?: @"";
        NSString *processName = NSProcessInfo.processInfo.processName.lowercaseString ?: @"";
        shouldUse = [guestBundleID isEqualToString:@"com.burbn.instagram"] ||
                    [guestBundleID containsString:@"instagram"] ||
                    [mainBundleID isEqualToString:@"com.burbn.instagram"] ||
                    [mainBundleID containsString:@"instagram"] ||
                    [processName containsString:@"instagram"];
    });
    return shouldUse;
}

static BOOL LCHookInstanceMethodInHierarchy(Class targetClass, SEL selector, IMP replacement, IMP *originalOut) {
    if (!targetClass || !selector || !replacement) {
        return NO;
    }

    for (Class cursor = targetClass; cursor != nil; cursor = class_getSuperclass(cursor)) {
        unsigned int methodCount = 0;
        Method *methodList = class_copyMethodList(cursor, &methodCount);
        Method matchedMethod = nil;

        for (unsigned int idx = 0; idx < methodCount; idx++) {
            Method candidate = methodList[idx];
            if (method_getName(candidate) == selector) {
                matchedMethod = candidate;
                break;
            }
        }

        if (!matchedMethod) {
            free(methodList);
            continue;
        }

        if (cursor != targetClass) {
            IMP inheritedImplementation = method_getImplementation(matchedMethod);
            const char *typeEncoding = method_getTypeEncoding(matchedMethod);
            BOOL added = class_addMethod(targetClass, selector, replacement, typeEncoding);
            if (!added) {
                Method ownMethod = class_getInstanceMethod(targetClass, selector);
                if (!ownMethod) {
                    free(methodList);
                    return NO;
                }
                inheritedImplementation = method_setImplementation(ownMethod, replacement);
            }
            if (originalOut) {
                *originalOut = inheritedImplementation;
            }
        } else {
            IMP previousImplementation = method_setImplementation(matchedMethod, replacement);
            if (originalOut) {
                *originalOut = previousImplementation;
            }
        }

        free(methodList);
        return YES;
    }

    return NO;
}

static NSDictionary *LCSanitizedCloudKitEntitlements(NSDictionary *entitlements) {
    if (![entitlements isKindOfClass:NSDictionary.class] || entitlements.count == 0) {
        return entitlements;
    }

    NSMutableDictionary *mutable = [entitlements mutableCopy];
    [mutable removeObjectForKey:@"com.apple.developer.icloud-container-environment"];
    [mutable removeObjectForKey:@"com.apple.developer.icloud-services"];
    return [mutable copy];
}

static id hook_CKContainer_setupWithContainerID_options(id self, SEL _cmd, id containerID, id options) {
    if (!LCShouldUseInstagramCloudKitWorkaround() && orig_CKContainer_setupWithContainerID_options) {
        return orig_CKContainer_setupWithContainerID_options(self, _cmd, containerID, options);
    }
    return nil;
}

static id hook_CKContainer_initWithContainerIdentifier(id self, SEL _cmd, id containerIdentifier) {
    if (!LCShouldUseInstagramCloudKitWorkaround() && orig_CKContainer_initWithContainerIdentifier) {
        return orig_CKContainer_initWithContainerIdentifier(self, _cmd, containerIdentifier);
    }
    return nil;
}

static id hook_CKEntitlements_initWithEntitlementsDict(id self, SEL _cmd, NSDictionary *entitlements) {
    if (!orig_CKEntitlements_initWithEntitlementsDict) {
        return nil;
    }
    NSDictionary *sanitized = LCShouldUseInstagramCloudKitWorkaround()
        ? LCSanitizedCloudKitEntitlements(entitlements)
        : entitlements;
    return orig_CKEntitlements_initWithEntitlementsDict(self, _cmd, sanitized);
}

static BOOL LCShouldRemapDefaultsSuiteToGroupContainer(NSString *suiteName) {
    if (![suiteName isKindOfClass:NSString.class] || suiteName.length == 0) {
        return NO;
    }
    if (![suiteName hasPrefix:@"group."]) {
        return NO;
    }
    return !isAppleIdentifier(suiteName);
}

static id hook_NSUserDefaults_initWithSuiteName_container(id self, SEL _cmd, NSString *suiteName, NSURL *container) {
    NSURL *effectiveContainer = container;
    if (LCShouldRemapDefaultsSuiteToGroupContainer(suiteName)) {
        NSURL *groupContainerURL = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:suiteName];
        if ([groupContainerURL isKindOfClass:NSURL.class]) {
            effectiveContainer = groupContainerURL;
        }
    }

    if (!orig_NSUserDefaults_initWithSuiteName_container) {
        return nil;
    }
    return orig_NSUserDefaults_initWithSuiteName_container(self, _cmd, suiteName, effectiveContainer);
}

static void LCInstallRegramCompatHooks(void) {
    os_unfair_lock_lock(&lcRegramCompatHookLock);

    if (!lcCKContainerSetupHooked) {
        Class ckContainerClass = NSClassFromString(@"CKContainer");
        SEL selector = NSSelectorFromString(@"_setupWithContainerID:options:");
        if (ckContainerClass && selector) {
            lcCKContainerSetupHooked = LCHookInstanceMethodInHierarchy(ckContainerClass,
                                                                        selector,
                                                                        (IMP)hook_CKContainer_setupWithContainerID_options,
                                                                        (IMP *)&orig_CKContainer_setupWithContainerID_options);
        }
    }

    if (!lcCKContainerInitHooked) {
        Class ckContainerClass = NSClassFromString(@"CKContainer");
        SEL selector = NSSelectorFromString(@"_initWithContainerIdentifier:");
        if (ckContainerClass && selector) {
            lcCKContainerInitHooked = LCHookInstanceMethodInHierarchy(ckContainerClass,
                                                                       selector,
                                                                       (IMP)hook_CKContainer_initWithContainerIdentifier,
                                                                       (IMP *)&orig_CKContainer_initWithContainerIdentifier);
        }
    }

    if (!lcCKEntitlementsHooked) {
        Class ckEntitlementsClass = NSClassFromString(@"CKEntitlements");
        SEL selector = NSSelectorFromString(@"initWithEntitlementsDict:");
        if (ckEntitlementsClass && selector) {
            lcCKEntitlementsHooked = LCHookInstanceMethodInHierarchy(ckEntitlementsClass,
                                                                      selector,
                                                                      (IMP)hook_CKEntitlements_initWithEntitlementsDict,
                                                                      (IMP *)&orig_CKEntitlements_initWithEntitlementsDict);
        }
    }

    if (!lcNSDefaultsContainerHooked) {
        SEL selector = NSSelectorFromString(@"_initWithSuiteName:container:");
        if (selector) {
            lcNSDefaultsContainerHooked = LCHookInstanceMethodInHierarchy(NSUserDefaults.class,
                                                                           selector,
                                                                           (IMP)hook_NSUserDefaults_initWithSuiteName_container,
                                                                           (IMP *)&orig_NSUserDefaults_initWithSuiteName_container);
        }
    }

    os_unfair_lock_unlock(&lcRegramCompatHookLock);
}

static void LCRegramCompatImageAdded(const struct mach_header *mh, intptr_t vmaddr_slide) {
    (void)mh;
    (void)vmaddr_slide;
    LCInstallRegramCompatHooks();
}

void NUDGuestHooksInit(void) {
    appContainerPath = [NSString stringWithUTF8String:getenv("HOME")];
    appContainerURL = [NSURL URLWithString:appContainerPath];
    LCInstallRegramCompatHooks();
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _dyld_register_func_for_add_image(LCRegramCompatImageAdded);
    });
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    
#if TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR
    // fix for macOS host
    method_setImplementation(class_getInstanceMethod(NSClassFromString(@"CFPrefsPlistSource"), @selector(_isSharedInTheiOSSimulator)), (IMP)hook_return_false);
#endif

    Class CFPrefsPlistSourceClass = NSClassFromString(@"CFPrefsPlistSource");

    swizzle2(CFPrefsPlistSourceClass, @selector(initWithDomain:user:byHost:containerPath:containingPreferences:), CFPrefsPlistSource2.class, @selector(hook_initWithDomain:user:byHost:containerPath:containingPreferences:));
#pragma clang diagnostic pop
    
    Class CFXPreferencesClass = NSClassFromString(@"_CFXPreferences");
    NSMutableDictionary* sources = object_getIvar([CFXPreferencesClass copyDefaultPreferences], class_getInstanceVariable(CFXPreferencesClass, "_sources"));

    [sources removeObjectForKey:@"C/A//B/L"];
    [sources removeObjectForKey:@"C/C//*/L"];
    
    // replace _CFPrefsCurrentAppIdentifierCache so kCFPreferencesCurrentApplication refers to the guest app
    const char* coreFoundationPath = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    mach_header_u* coreFoundationHeader = LCGetLoadedImageHeader(2, coreFoundationPath);
    
#if !TARGET_OS_SIMULATOR
    CFStringRef* _CFPrefsCurrentAppIdentifierCache = getCachedSymbol(@"__CFPrefsCurrentAppIdentifierCache", coreFoundationHeader);
    if(!_CFPrefsCurrentAppIdentifierCache) {
        _CFPrefsCurrentAppIdentifierCache = litehook_find_dsc_symbol(coreFoundationPath, "__CFPrefsCurrentAppIdentifierCache");
        uint64_t offset = (uint64_t)((void*)_CFPrefsCurrentAppIdentifierCache - (void*)coreFoundationHeader);
        saveCachedSymbol(@"__CFPrefsCurrentAppIdentifierCache", coreFoundationHeader, offset);
    }
    [NSUserDefaults.lcUserDefaults _setIdentifier:(__bridge NSString*)CFStringCreateCopy(nil, *_CFPrefsCurrentAppIdentifierCache)];
    *_CFPrefsCurrentAppIdentifierCache = (__bridge CFStringRef)NSUserDefaults.lcGuestAppId;
#else
    // FIXME: for now we skip overwriting _CFPrefsCurrentAppIdentifierCache on simulator, since there is no way to find private symbol
#endif
    
    NSUserDefaults* newStandardUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"whatever"];
    [newStandardUserDefaults _setIdentifier:NSUserDefaults.lcGuestAppId];
    NSUserDefaults.standardUserDefaults = newStandardUserDefaults;

#if !TARGET_OS_SIMULATOR
    NSString* selectedLanguage = NSUserDefaults.guestAppInfo[@"LCSelectedLanguage"];
    if(selectedLanguage) {
        [newStandardUserDefaults setObject:@[selectedLanguage] forKey:@"AppleLanguages"];
        CFMutableArrayRef* _CFBundleUserLanguages = getCachedSymbol(@"__CFBundleUserLanguages", coreFoundationHeader);
        if(!_CFBundleUserLanguages) {
            _CFBundleUserLanguages = litehook_find_dsc_symbol(coreFoundationPath, "__CFBundleUserLanguages");
            uint64_t offset = (uint64_t)((void*)_CFBundleUserLanguages - (void*)coreFoundationHeader);
            saveCachedSymbol(@"__CFBundleUserLanguages", coreFoundationHeader, offset);
        }
        // set _CFBundleUserLanguages to selected languages
        NSMutableArray* newUserLanguages = [NSMutableArray arrayWithObjects:selectedLanguage, nil];
        *_CFBundleUserLanguages = (__bridge CFMutableArrayRef)newUserLanguages;
    } else {
        [newStandardUserDefaults removeObjectForKey:@"AppleLanguages"];
    }
#endif
    
    // Create Library/Preferences folder in app's data folder in case it does not exist
    NSFileManager* fm = NSFileManager.defaultManager;
    NSURL* libraryPath = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL* preferenceFolderPath = [libraryPath URLByAppendingPathComponent:@"Preferences"];
    if(![fm fileExistsAtPath:preferenceFolderPath.path]) {
        NSError* error;
        [fm createDirectoryAtPath:preferenceFolderPath.path withIntermediateDirectories:YES attributes:@{} error:&error];
    }
    
}

NSArray* appleIdentifierPrefixes = @[
    @"com.apple.",
    @"group.com.apple.",
    @"systemgroup.com.apple."
];

static bool isAppleIdentifier(NSString* identifier) {
    for(NSString* cur in appleIdentifierPrefixes) {
        if([identifier hasPrefix:cur]) {
            return true;
        }
    }
    return false;
}


@implementation CFPrefsPlistSource2
-(id)hook_initWithDomain:(CFStringRef)domain user:(CFStringRef)user byHost:(bool)host containerPath:(CFStringRef)containerPath containingPreferences:(id)arg5 {
    if(isAppleIdentifier((__bridge NSString*)domain)) {
        return [self hook_initWithDomain:domain user:user byHost:host containerPath:containerPath containingPreferences:arg5];
    }
    if(user == kCFPreferencesAnyUser) {
        user = kCFPreferencesCurrentUser;
    }
    return [self hook_initWithDomain:domain user:user byHost:host containerPath:(__bridge CFStringRef)appContainerPath containingPreferences:arg5];
}
@end
