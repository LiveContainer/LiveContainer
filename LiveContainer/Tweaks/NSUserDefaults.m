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
@import ObjectiveC;
@import MachO;
#include <sys/utsname.h>

BOOL hook_return_false(void) {
    return NO;
}

void swizzle2(Class class, SEL originalAction, Class class2, SEL swizzledAction) {
    Method m1 = class_getInstanceMethod(class2, swizzledAction);
    class_addMethod(class, swizzledAction, method_getImplementation(m1), method_getTypeEncoding(m1));
    method_exchangeImplementations(class_getInstanceMethod(class, originalAction), class_getInstanceMethod(class, swizzledAction));
}

NSURL* appContainerURL = 0;
NSString* appContainerPath = 0;

void NUDGuestHooksInit(void) {
#define NUD_LOG(fmt, ...) litehook_diagnostic_log("NUDGuestHooksInit: " fmt, ##__VA_ARGS__)
    struct utsname systemInfo = {0};
    uname(&systemInfo);
    NUD_LOG("BEGIN machine=%s kernel=%s version=%s HOME=%s LC_HOME_PATH=%s", systemInfo.machine, systemInfo.release, systemInfo.version, getenv("HOME") ?: "(null)", getenv("LC_HOME_PATH") ?: "(null)");
    NUD_LOG("before creating app container path/URL");
    appContainerPath = [NSString stringWithUTF8String:getenv("HOME")];
    appContainerURL = [NSURL URLWithString:appContainerPath];
    NUD_LOG("app container path/URL ready; before installing preferences hooks");
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    
#if TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR
    // fix for macOS host
    method_setImplementation(class_getInstanceMethod(NSClassFromString(@"CFPrefsPlistSource"), @selector(_isSharedInTheiOSSimulator)), (IMP)hook_return_false);
#endif

    Class CFPrefsPlistSourceClass = NSClassFromString(@"CFPrefsPlistSource");

    NUD_LOG("before swizzle CFPrefsPlistSource class=%p", CFPrefsPlistSourceClass);
    swizzle2(CFPrefsPlistSourceClass, @selector(initWithDomain:user:byHost:containerPath:containingPreferences:), CFPrefsPlistSource2.class, @selector(hook_initWithDomain:user:byHost:containerPath:containingPreferences:));
#pragma clang diagnostic pop
    
    NUD_LOG("preferences swizzle complete; before resolving _CFXPreferences");
    Class CFXPreferencesClass = NSClassFromString(@"_CFXPreferences");
    NUD_LOG("before copyDefaultPreferences class=%p", CFXPreferencesClass);
    id preferences = [CFXPreferencesClass copyDefaultPreferences];
    Ivar sourcesIvar = class_getInstanceVariable(CFXPreferencesClass, "_sources");
    NUD_LOG("before object_getIvar preferences=%p sourcesIvar=%p", (__bridge void *)preferences, sourcesIvar);
    NSMutableDictionary* sources = object_getIvar(preferences, sourcesIvar);
    NUD_LOG("before removing cached preference sources dictionary=%p", (__bridge void *)sources);

    [sources removeObjectForKey:@"C/A//B/L"];
    [sources removeObjectForKey:@"C/C//*/L"];
    
    // replace _CFPrefsCurrentAppIdentifierCache so kCFPreferencesCurrentApplication refers to the guest app
    const char* coreFoundationPath = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    NUD_LOG("sources removed; before LCGetLoadedImageHeader CoreFoundation");
    mach_header_u* coreFoundationHeader = LCGetLoadedImageHeader(2, coreFoundationPath);
    NUD_LOG("CoreFoundation header=%p; before getCachedSymbol __CFPrefsCurrentAppIdentifierCache", coreFoundationHeader);
    
#if !TARGET_OS_SIMULATOR
    CFStringRef* _CFPrefsCurrentAppIdentifierCache = getCachedSymbol(@"__CFPrefsCurrentAppIdentifierCache", coreFoundationHeader);
    NUD_LOG("getCachedSymbol __CFPrefsCurrentAppIdentifierCache returned %p", _CFPrefsCurrentAppIdentifierCache);
    if(!_CFPrefsCurrentAppIdentifierCache) {
        NUD_LOG("before litehook_find_dsc_symbol __CFPrefsCurrentAppIdentifierCache");
        _CFPrefsCurrentAppIdentifierCache = litehook_find_dsc_symbol(coreFoundationPath, "__CFPrefsCurrentAppIdentifierCache");
        NUD_LOG("litehook_find_dsc_symbol __CFPrefsCurrentAppIdentifierCache returned %p", _CFPrefsCurrentAppIdentifierCache);
        uint64_t offset = (uint64_t)((void*)_CFPrefsCurrentAppIdentifierCache - (void*)coreFoundationHeader);
        NUD_LOG("before saveCachedSymbol __CFPrefsCurrentAppIdentifierCache offset=0x%llx header=%p%s", (unsigned long long)offset, coreFoundationHeader, _CFPrefsCurrentAppIdentifierCache ? "" : " WARNING: NULL lookup result");
        saveCachedSymbol(@"__CFPrefsCurrentAppIdentifierCache", coreFoundationHeader, offset);
        NUD_LOG("saveCachedSymbol __CFPrefsCurrentAppIdentifierCache complete");
    }
    NUD_LOG("before dereference __CFPrefsCurrentAppIdentifierCache address=%p", _CFPrefsCurrentAppIdentifierCache);
    CFStringRef originalIdentifier = *_CFPrefsCurrentAppIdentifierCache;
    NUD_LOG("dereference complete value=%p; before CFStringCreateCopy", originalIdentifier);
    CFStringRef copiedIdentifier = CFStringCreateCopy(nil, originalIdentifier);
    NUD_LOG("CFStringCreateCopy returned %p; before lcUserDefaults _setIdentifier", copiedIdentifier);
    [NSUserDefaults.lcUserDefaults _setIdentifier:(__bridge NSString*)copiedIdentifier];
    NUD_LOG("_setIdentifier complete; before obtaining guest identifier");
    CFStringRef guestIdentifier = (__bridge CFStringRef)NSUserDefaults.lcGuestAppId;
    NUD_LOG("before writing __CFPrefsCurrentAppIdentifierCache address=%p value=%p", _CFPrefsCurrentAppIdentifierCache, guestIdentifier);
    *_CFPrefsCurrentAppIdentifierCache = guestIdentifier;
    NUD_LOG("__CFPrefsCurrentAppIdentifierCache write complete");
#else
    // FIXME: for now we skip overwriting _CFPrefsCurrentAppIdentifierCache on simulator, since there is no way to find private symbol
#endif
    
    NUD_LOG("before creating replacement standardUserDefaults");
    NSUserDefaults* newStandardUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"whatever"];
    NUD_LOG("replacement created=%p; before _setIdentifier", (__bridge void *)newStandardUserDefaults);
    [newStandardUserDefaults _setIdentifier:NSUserDefaults.lcGuestAppId];
    NUD_LOG("before replacing standardUserDefaults");
    NSUserDefaults.standardUserDefaults = newStandardUserDefaults;

#if !TARGET_OS_SIMULATOR
    NUD_LOG("standardUserDefaults replaced; before reading selected language");
    NSString* selectedLanguage = NSUserDefaults.guestAppInfo[@"LCSelectedLanguage"];
    if(selectedLanguage) {
        NUD_LOG("selected language present; before setting AppleLanguages");
        [newStandardUserDefaults setObject:@[selectedLanguage] forKey:@"AppleLanguages"];
        NUD_LOG("before getCachedSymbol __CFBundleUserLanguages");
        CFMutableArrayRef* _CFBundleUserLanguages = getCachedSymbol(@"__CFBundleUserLanguages", coreFoundationHeader);
        NUD_LOG("getCachedSymbol __CFBundleUserLanguages returned %p", _CFBundleUserLanguages);
        if(!_CFBundleUserLanguages) {
            NUD_LOG("before litehook_find_dsc_symbol __CFBundleUserLanguages");
            _CFBundleUserLanguages = litehook_find_dsc_symbol(coreFoundationPath, "__CFBundleUserLanguages");
            NUD_LOG("litehook_find_dsc_symbol __CFBundleUserLanguages returned %p", _CFBundleUserLanguages);
            uint64_t offset = (uint64_t)((void*)_CFBundleUserLanguages - (void*)coreFoundationHeader);
            NUD_LOG("before saveCachedSymbol __CFBundleUserLanguages offset=0x%llx%s", (unsigned long long)offset, _CFBundleUserLanguages ? "" : " WARNING: NULL lookup result");
            saveCachedSymbol(@"__CFBundleUserLanguages", coreFoundationHeader, offset);
            NUD_LOG("saveCachedSymbol __CFBundleUserLanguages complete");
        }
        // set _CFBundleUserLanguages to selected languages
        NUD_LOG("before creating replacement language array");
        NSMutableArray* newUserLanguages = [NSMutableArray arrayWithObjects:selectedLanguage, nil];
        NUD_LOG("before writing __CFBundleUserLanguages address=%p value=%p", _CFBundleUserLanguages, (__bridge void *)newUserLanguages);
        *_CFBundleUserLanguages = (__bridge CFMutableArrayRef)newUserLanguages;
        NUD_LOG("__CFBundleUserLanguages write complete");
    } else {
        NUD_LOG("no selected language; before removing AppleLanguages");
        [newStandardUserDefaults removeObjectForKey:@"AppleLanguages"];
    }
#endif
    
    NUD_LOG("before preparing Library/Preferences directory");
    // Create Library/Preferences folder in app's data folder in case it does not exist
    NSFileManager* fm = NSFileManager.defaultManager;
    NSURL* libraryPath = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL* preferenceFolderPath = [libraryPath URLByAppendingPathComponent:@"Preferences"];
    if(![fm fileExistsAtPath:preferenceFolderPath.path]) {
        NUD_LOG("before creating Library/Preferences");
        NSError* error = nil;
        BOOL created = [fm createDirectoryAtPath:preferenceFolderPath.path withIntermediateDirectories:YES attributes:@{} error:&error];
        NUD_LOG("create Library/Preferences result=%d errorCode=%ld", created, (long)error.code);
    }
    NUD_LOG("END");
#undef NUD_LOG
}

NSArray* appleIdentifierPrefixes = @[
    @"com.apple.",
    @"group.com.apple.",
    @"systemgroup.com.apple."
];

bool isAppleIdentifier(NSString* identifier) {
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
