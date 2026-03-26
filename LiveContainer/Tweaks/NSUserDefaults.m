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
#import "CloudKit/CloudKit.h"
#import "Intents/Intents.h"
#import <UserNotifications/UserNotifications.h>

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

    // 处理iCloud
    swizzleClassMethod(CKContainer.class, @selector(defaultContainer), @selector(hook_defaultContainer));
    swizzleClassMethod(CKContainer.class, @selector(containerWithIdentifier:),@selector(hook_containerWithIdentifier:));
    // 处理Siri
    swizzleClassMethod(INPreferences.class, @selector(requestSiriAuthorization:),@selector(hook_requestSiriAuthorization:));
    swizzleClassMethod(INPreferences.class, @selector(siriAuthorizationStatus),@selector(hook_siriAuthorizationStatus));
    swizzleClassMethod(INVocabulary.class, @selector(sharedVocabulary),@selector(hook_sharedVocabulary));
    swizzleClassMethod(INPlayMediaIntent.class, @selector(initWithMediaItems:mediaItems:mediaContainer:playShuffled:playbackRepeatMode:resumePlayback:playbackQueueLocation:playbackSpeed:mediaSearch:),@selector(hook_initWithMediaItems:mediaItems:mediaContainer:playShuffled:playbackRepeatMode:resumePlayback:playbackQueueLocation:playbackSpeed:mediaSearch:));

    // 处理通知权限
    swizzle(UNNotificationSettings.class, @selector(authorizationStatus), @selector(hook_authorizationStatus));
    swizzle(UNNotificationSettings.class, @selector(soundSetting), @selector(hook_soundSetting));
    swizzle(UNNotificationSettings.class, @selector(badgeSetting), @selector(hook_badgeSetting));
    swizzle(UNNotificationSettings.class, @selector(alertSetting), @selector(hook_alertSetting));
    swizzle(UNNotificationSettings.class, @selector(lockScreenSetting), @selector(hook_lockScreenSetting));
    swizzle(UNNotificationSettings.class, @selector(notificationCenterSetting), @selector(hook_notificationCenterSetting));
    swizzle(UNNotificationSettings.class, @selector(alertStyle), @selector(hook_alertStyle));

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

@implementation INPreferences (hook)
+ (void)hook_requestSiriAuthorization:(void (^)(INSiriAuthorizationStatus))handler {
    NSLog(@"Swizzled requestSiriAuthorization, denying access");
    if (handler) {
        handler(INSiriAuthorizationStatusDenied);
    }
}
+ (INSiriAuthorizationStatus)hook_siriAuthorizationStatus {
    NSLog(@"Swizzled requestSiriAuthorization, denying access");
    return INSiriAuthorizationStatusDenied;
}
@end

@implementation CKContainer (hook)
- (void)hook_accountStatusWithCompletionHandler:(void (^)(CKAccountStatus, NSError *))completionHandler {
    NSLog(@"Swizzled accountStatusWithCompletionHandler, denying iCloud access");
    if (completionHandler) {
        // 返回无账户状态，模拟 iCloud 不可用
        completionHandler(CKAccountStatusNoAccount, [NSError errorWithDomain:@"CloudKit" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"iCloud access denied"}]);
    }
}
+ (CKContainer *)hook_defaultContainer {
    NSLog(@"Swizzled swizzled_defaultContainer, denying iCloud access");
    return nil;
}
+ (CKContainer *)hook_containerWithIdentifier:(NSString *)containerIdentifier {
    NSLog(@"Swizzled swizzled_containerWithIdentifier, denying iCloud access");
    return nil;
}
// 阻止用户获取令牌
- (void)hook_fetchUserRecordIDWithCompletionHandler:(void (^)(CKRecordID *recordID, NSError *error))completionHandler {
    // 返回虚假信息
    if (completionHandler) {
        NSError *error = [NSError errorWithDomain:CKErrorDomain
                                             code:CKErrorNotAuthenticated
                                         userInfo:@{NSLocalizedDescriptionKey: @"User authentication failed"}];
        completionHandler(nil, error);
    }
}
// 阻止权限检查
- (void)hook_requestApplicationPermission:(CKApplicationPermissions)permission completionHandler:(void (^)(CKApplicationPermissionStatus status, NSError *error))completion {
    // 总是返回无权限状态
    if (completion) {
        NSError *error = [NSError errorWithDomain:CKErrorDomain
                                             code:CKErrorPermissionFailure
                                         userInfo:@{NSLocalizedDescriptionKey: @"iCloud access denied"}];
        completion(CKApplicationPermissionStatusDenied, error);
    }
}
@end

@implementation NSFileManager (hook)
// 阻止文件令牌获取访问
- (id)alwaysDenyUbiquityIdentityToken {
    return nil; // 返回nil阻止文件同步
}
@end

@implementation INVocabulary (hook)

+ (instancetype)hook_sharedVocabulary {
    return nil;
}

@end

@implementation INPlayMediaIntent (hook)

- (instancetype)hook_initWithMediaItems:(nullable NSArray<INMediaItem *> *)mediaItems
                    mediaContainer:(nullable INMediaItem *)mediaContainer
                      playShuffled:(nullable NSNumber *)playShuffled
                playbackRepeatMode:(INPlaybackRepeatMode)playbackRepeatMode
                    resumePlayback:(nullable NSNumber *)resumePlayback
             playbackQueueLocation:(INPlaybackQueueLocation)playbackQueueLocation
                     playbackSpeed:(nullable NSNumber *)playbackSpeed
                       mediaSearch:(nullable INMediaSearch *)mediaSearch {
    return nil;
}

@end

@implementation CKDatabase (hook)
- (void)hook_fetchRecordWithID:(CKRecordID *)recordID completionHandler:(void (NS_SWIFT_SENDABLE ^)(CKRecord * _Nullable record, NSError * _Nullable error))completionHandler {
    if (completionHandler) {
        NSError *error = [NSError errorWithDomain:CKErrorDomain
                                             code:CKErrorPermissionFailure
                                         userInfo:@{NSLocalizedDescriptionKey: @"iCloud access denied"}];
        completionHandler(nil, error);
    }
}
- (void)hook_performQuery:(CKQuery *)query inZoneWithID:(nullable CKRecordZoneID *)zoneID completionHandler:(void (NS_SWIFT_SENDABLE ^)(NSArray<CKRecord *> * _Nullable results, NSError * _Nullable error))completionHandler {
    if (completionHandler) {
        NSError *error = [NSError errorWithDomain:CKErrorDomain
                                             code:CKErrorPermissionFailure
                                         userInfo:@{NSLocalizedDescriptionKey: @"iCloud access denied"}];
        completionHandler(nil, error);
    }
}
@end


@implementation UNNotificationSettings (hook)

- (UNAuthorizationStatus)hook_authorizationStatus {
    // 强制返回 Authorized (2)
    return UNAuthorizationStatusAuthorized;
}

// 2. 伪造具体功能的开关状态 (防止应用检查细分权限)
- (UNNotificationSetting)hook_soundSetting {
    return UNNotificationSettingEnabled;
}

- (UNNotificationSetting)hook_badgeSetting {
    return UNNotificationSettingEnabled;
}

- (UNNotificationSetting)hook_alertSetting {
    return UNNotificationSettingEnabled;
}

- (UNNotificationSetting)hook_lockScreenSetting {
    return UNNotificationSettingEnabled;
}

- (UNNotificationSetting)hook_notificationCenterSetting {
    return UNNotificationSettingEnabled;
}

- (UNAlertStyle)hook_alertStyle {
    return UNAlertStyleBanner;
}

@end
