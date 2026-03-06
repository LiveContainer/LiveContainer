#import "FoundationPrivate.h"
#import "LCMachOUtils.h"
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "utils.h"

#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <objc/runtime.h>

#include <dlfcn.h>
#include <execinfo.h>
#include <signal.h>
#include <sys/mman.h>
#include <stdlib.h>
#include "../litehook/src/litehook.h"
#import "Tweaks/Tweaks.h"
#include <mach-o/ldsyms.h>
#import "Tweaks/DeviceSpoofing.h"

static int (*appMain)(int, char**);
NSUserDefaults *lcUserDefaults;
NSUserDefaults *lcSharedDefaults;
NSString *lcAppGroupPath;
NSString* lcAppUrlScheme;
NSBundle* lcMainBundle;
NSDictionary* guestAppInfo;
NSDictionary* guestContainerInfo;
NSString* lcGuestAppId;
bool isLiveProcess = false;
bool isSharedBundle = false;
bool isSideStore = false;
bool sideStoreExist = false;

static NSString *originalGuestBundleId = nil;
static NSString *liveContainerBundleId = nil;
static BOOL useSelectiveBundleIdSpoofing = NO;

static NSString *LCSpoofBuildForSystemVersion(NSString *version) {
    static NSDictionary<NSString *, NSString *> *versionToBuild = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        versionToBuild = @{
            @"26.0": @"23A341",
            @"26.0.1": @"23A355",
            @"26.1": @"23B85",
            @"26.2": @"23C55",
            @"26.2.1": @"23C71",
            @"26.3": @"23D127",
            @"18.6": @"22G86",
            @"18.6.1": @"22G90",
            @"18.6.2": @"22G100",
        };
    });
    return versionToBuild[version];
}

static NSString *LCDefaultStorageCapacityForProfile(NSString *profile) {
    static NSDictionary<NSString *, NSString *> *profileToCapacity = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        profileToCapacity = @{
            @"iPhone 17 Pro Max": @"256",
            @"iPhone 17 Pro": @"256",
            @"iPhone 17": @"256",
            @"iPhone 17 Air": @"256",
            @"iPhone 16 Pro Max": @"256",
            @"iPhone 16 Pro": @"128",
            @"iPhone 16": @"128",
            @"iPhone 16e": @"128",
            @"iPhone 15 Pro Max": @"256",
            @"iPhone 15 Pro": @"128",
            @"iPhone 14 Pro Max": @"128",
            @"iPhone 14 Pro": @"128",
            @"iPhone 13 Pro Max": @"128",
            @"iPhone 13 Pro": @"128",
        };
    });

    NSString *resolvedProfile = [profile isKindOfClass:NSString.class] && profile.length > 0 ? profile : @"iPhone 17";
    return profileToCapacity[resolvedProfile] ?: @"256";
}

static NSTimeInterval LCUptimeSecondsFromPreset(NSString *preset) {
    NSString *value = [[preset ?: @"medium" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value isEqualToString:@"short"]) return 2 * 3600;      // midpoint of 1-4h
    if ([value isEqualToString:@"medium"]) return 12 * 3600;    // midpoint of 4-24h
    if ([value isEqualToString:@"long"]) return 48 * 3600;      // midpoint of 1-3d
    if ([value isEqualToString:@"week"]) return 5 * 24 * 3600;  // midpoint of 3-7d
    if ([value isEqualToString:@"month"]) return 30 * 24 * 3600;
    if ([value isEqualToString:@"year"]) return 365 * 24 * 3600;

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*([0-9]+)\\s*([a-z]+)\\s*$" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    if (match && match.numberOfRanges >= 3) {
        NSString *countString = [value substringWithRange:[match rangeAtIndex:1]];
        NSString *unit = [[value substringWithRange:[match rangeAtIndex:2]] lowercaseString];
        NSInteger count = countString.integerValue;
        if (count > 0) {
            if ([unit isEqualToString:@"h"] || [unit isEqualToString:@"hr"] || [unit isEqualToString:@"hour"] || [unit isEqualToString:@"hours"]) return count * 3600.0;
            if ([unit isEqualToString:@"d"] || [unit isEqualToString:@"day"] || [unit isEqualToString:@"days"]) return count * 24.0 * 3600.0;
            if ([unit isEqualToString:@"w"] || [unit isEqualToString:@"wk"] || [unit isEqualToString:@"week"] || [unit isEqualToString:@"weeks"]) return count * 7.0 * 24.0 * 3600.0;
            if ([unit isEqualToString:@"mo"] || [unit isEqualToString:@"month"] || [unit isEqualToString:@"months"]) return count * 30.0 * 24.0 * 3600.0;
            if ([unit isEqualToString:@"y"] || [unit isEqualToString:@"yr"] || [unit isEqualToString:@"year"] || [unit isEqualToString:@"years"]) return count * 365.0 * 24.0 * 3600.0;
        }
    }

    return 12 * 3600;
}

static NSSet<NSString *> *LCAddonScopedLegacyKeys(void) {
    static NSSet<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"spoofGPS",
            @"spoofLatitude",
            @"spoofLongitude",
            @"spoofAltitude",
            @"spoofLocationName",
            @"spoofCamera",
            @"spoofCameraType",
            @"spoofCameraImagePath",
            @"spoofCameraVideoPath",
            @"spoofCameraLoop",
            @"spoofCameraUseVideoAudio",
            @"spoofCameraMode",
            @"spoofCameraTransformOrientation",
            @"spoofCameraTransformScale",
            @"spoofCameraTransformFlip",
        ]];
    });
    return keys;
}

static BOOL LCIsContainerScopedAddonKey(NSString *key) {
    if (![key isKindOfClass:NSString.class] || key.length == 0) {
        return NO;
    }
    if ([key hasPrefix:@"deviceSpoof"] || [key hasPrefix:@"enableSpoof"]) {
        return YES;
    }
    return [LCAddonScopedLegacyKeys() containsObject:key];
}

static NSDictionary *LCGuestAppInfoWithMergedAddonSettings(NSDictionary *appInfo,
                                                            NSString *containerId,
                                                            NSDictionary *containerInfo) {
    if (![appInfo isKindOfClass:NSDictionary.class]) {
        return appInfo;
    }

    NSMutableDictionary *merged = [appInfo mutableCopy];
    if (!merged) {
        return appInfo;
    }

    NSMutableDictionary *legacyScopedFallback = [NSMutableDictionary dictionary];
    for (id keyObj in appInfo) {
        if (![keyObj isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *key = (NSString *)keyObj;
        if (!LCIsContainerScopedAddonKey(key)) {
            continue;
        }
        id value = appInfo[key];
        if (value != nil && ![value isKindOfClass:NSNull.class]) {
            legacyScopedFallback[key] = value;
        }
    }

    NSDictionary *containerSettings = nil;
    id settingsByContainerObj = appInfo[@"LCAddonSettingsByContainer"];
    if ([settingsByContainerObj isKindOfClass:NSDictionary.class] && containerId.length > 0) {
        id settingsObj = ((NSDictionary *)settingsByContainerObj)[containerId];
        if ([settingsObj isKindOfClass:NSDictionary.class]) {
            containerSettings = settingsObj;
        }
    }

    NSArray<NSString *> *existingKeys = [merged.allKeys copy];
    for (id keyObj in existingKeys) {
        if (![keyObj isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *key = (NSString *)keyObj;
        if (LCIsContainerScopedAddonKey(key)) {
            [merged removeObjectForKey:key];
        }
    }

    if (containerSettings) {
        for (id keyObj in containerSettings) {
            if (![keyObj isKindOfClass:NSString.class]) {
                continue;
            }
            NSString *key = (NSString *)keyObj;
            id value = containerSettings[key];
            if (LCIsContainerScopedAddonKey(key) && value != nil && ![value isKindOfClass:NSNull.class]) {
                merged[key] = value;
            }
        }
    }

    for (id keyObj in legacyScopedFallback) {
        if (![keyObj isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *key = (NSString *)keyObj;
        if (merged[key] == nil) {
            id value = legacyScopedFallback[key];
            if (value != nil && ![value isKindOfClass:NSNull.class]) {
                merged[key] = value;
            }
        }
    }

    BOOL spoofIDFV = [containerInfo[@"spoofIdentifierForVendor"] boolValue];
    id scopedSpoofIDFV = containerSettings[@"deviceSpoofIdentifiers"];
    if ([scopedSpoofIDFV respondsToSelector:@selector(boolValue)]) {
        spoofIDFV = [scopedSpoofIDFV boolValue];
    }
    merged[@"deviceSpoofIdentifiers"] = @(spoofIDFV);

    NSString *vendorID = @"";
    id scopedVendorID = containerSettings[@"deviceSpoofVendorID"];
    if ([scopedVendorID isKindOfClass:NSString.class]) {
        vendorID = (NSString *)scopedVendorID;
    } else {
        id fallbackVendorID = containerInfo[@"spoofedIdentifierForVendor"];
        if ([fallbackVendorID isKindOfClass:NSString.class]) {
            vendorID = (NSString *)fallbackVendorID;
        }
    }

    if (spoofIDFV) {
        if (vendorID.length == 0) {
            vendorID = NSUUID.UUID.UUIDString;
        }
        merged[@"deviceSpoofVendorID"] = vendorID;
    } else {
        [merged removeObjectForKey:@"deviceSpoofVendorID"];
    }

    if (containerId.length > 0) {
        merged[@"LCDataUUID"] = containerId;
    }

    NSLog(@"[LC] addon merge container=%@ hasContainerSettings=%@ spoofGPS=%@ lat=%@ lon=%@",
          containerId ?: @"(nil)",
          containerSettings ? @"YES" : @"NO",
          merged[@"spoofGPS"],
          merged[@"spoofLatitude"],
          merged[@"spoofLongitude"]);

    return [merged copy];
}

@implementation NSUserDefaults(LiveContainer)
+ (instancetype)lcUserDefaults {
    return lcUserDefaults;
}
+ (instancetype)lcSharedDefaults {
    return lcSharedDefaults;
}
+ (NSString *)lcAppGroupPath {
    return lcAppGroupPath;
}
+ (NSString *)lcAppUrlScheme {
    return lcAppUrlScheme;
}
+ (NSBundle *)lcMainBundle {
    return lcMainBundle;
}
+ (NSDictionary *)guestAppInfo {
    return guestAppInfo;
}

+ (NSDictionary *)guestContainerInfo {
    return guestContainerInfo;
}

+ (bool)isLiveProcess {
    return isLiveProcess;
}
+ (bool)isSharedApp {
    return isSharedBundle;
}
+ (bool)isSideStore {
    return isSideStore;
}
+ (bool)sideStoreExist {
    return sideStoreExist;
}

+ (NSString*)lcGuestAppId {
    return lcGuestAppId;
}
@end

static BOOL checkJITEnabled() {
#if TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR
    return YES;
#else
    if([lcUserDefaults boolForKey:@"LCIgnoreJITOnLaunch"]) {
        return NO;
    }
    // check if jailbroken
    if (access("/var/mobile", R_OK) == 0) {
        return YES;
    }
    
    if(@available(iOS 26.0 ,*))  {
        return false;
    }

    // check csflags
    int flags;
    csops(getpid(), 0, &flags, sizeof(flags));
    return (flags & CS_DEBUGGED) != 0;
#endif
}

static uint64_t rnd64(uint64_t v, uint64_t r) {
    r--;
    return (v + r) & ~r;
}

void overwriteMainCFBundle(void) {
    // Overwrite CFBundleGetMainBundle
    uint32_t *pc = (uint32_t *)CFBundleGetMainBundle;
    void **mainBundleAddr = 0;
    while (true) {
        uint64_t addr = aarch64_get_tbnz_jump_address(*pc, (uint64_t)pc);
        if (addr) {
            // adrp <- pc-1
            // tbnz <- pc
            // ...
            // ldr  <- addr
            mainBundleAddr = (void **)aarch64_emulate_adrp_ldr(*(pc-1), *(uint32_t *)addr, (uint64_t)(pc-1));
            break;
        }
        ++pc;
    }
    assert(mainBundleAddr != NULL);
    *mainBundleAddr = (__bridge void *)NSBundle.mainBundle._cfBundle;
}

void overwriteMainNSBundle(NSBundle *newBundle) {
    // Overwrite NSBundle.mainBundle
    // iOS 16: x19 is _MergedGlobals
    // iOS 17: x19 is _MergedGlobals+4

    NSString *oldPath = NSBundle.mainBundle.executablePath;
    uint32_t *mainBundleImpl = (uint32_t *)method_getImplementation(class_getClassMethod(NSBundle.class, @selector(mainBundle)));
    for (int i = 0; i < 20; i++) {
        void **_MergedGlobals = (void **)aarch64_emulate_adrp_add(mainBundleImpl[i], mainBundleImpl[i+1], (uint64_t)&mainBundleImpl[i]);
        if (!_MergedGlobals) continue;

        // In iOS 17, adrp+add gives _MergedGlobals+4, so it uses ldur instruction instead of ldr
        if ((mainBundleImpl[i+4] & 0xFF000000) == 0xF8000000) {
            uint64_t ptr = (uint64_t)_MergedGlobals - 4;
            _MergedGlobals = (void **)ptr;
        }

        for (int mgIdx = 0; mgIdx < 20; mgIdx++) {
            if (_MergedGlobals[mgIdx] == (__bridge void *)NSBundle.mainBundle) {
                _MergedGlobals[mgIdx] = (__bridge void *)newBundle;
                break;
            }
        }
    }

    assert(![NSBundle.mainBundle.executablePath isEqualToString:oldPath]);
}

int hook__NSGetExecutablePath_overwriteExecPath(char*** dyldApiInstancePtr, char* newPath, uint32_t* bufsize) {
    assert(dyldApiInstancePtr != 0);
    char** dyldConfig = dyldApiInstancePtr[1];
    assert(dyldConfig != 0);
    
    char** mainExecutablePathPtr = 0;
    // mainExecutablePath is at 0x10 for iOS 15~18.3.2, 0x20 for iOS 18.4+
    if(dyldConfig[2] != 0 && dyldConfig[2][0] == '/') {
        mainExecutablePathPtr = dyldConfig + 2;
    } else if (dyldConfig[4] != 0 && dyldConfig[4][0] == '/') {
        mainExecutablePathPtr = dyldConfig + 4;
    } else {
        assert(mainExecutablePathPtr != 0);
    }

    kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)mainExecutablePathPtr, sizeof(mainExecutablePathPtr), false, PROT_READ | PROT_WRITE);
    if(ret != KERN_SUCCESS) {
        assert(os_tpro_is_supported());
        os_thread_self_restrict_tpro_to_rw();
    }
    *mainExecutablePathPtr = newPath;
    if(ret != KERN_SUCCESS) {
        os_thread_self_restrict_tpro_to_ro();
    }

    return 0;
}

void overwriteExecPath(const char *newExecPath) {
    // dyld4 stores executable path in a different place (iOS 15.0 +)
    // https://github.com/apple-oss-distributions/dyld/blob/ce1cc2088ef390df1c48a1648075bbd51c5bbc6a/dyld/DyldAPIs.cpp#L802
    int (*orig__NSGetExecutablePath)(void* dyldPtr, char* buf, uint32_t* bufsize);
    performHookDyldApi("_NSGetExecutablePath", 2, (void**)&orig__NSGetExecutablePath, hook__NSGetExecutablePath_overwriteExecPath);
    _NSGetExecutablePath((char*)newExecPath, NULL);
    // put the original function back
    performHookDyldApi("_NSGetExecutablePath", 2, (void**)&orig__NSGetExecutablePath, orig__NSGetExecutablePath);
}

static void *getAppEntryPoint(void *handle) {
    uint32_t entryoff = 0;
    const struct mach_header_64 *header = (struct mach_header_64 *)getGuestAppHeader();
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds > 0; ++i) {
        if(command->cmd == LC_MAIN) {
            struct entry_point_command ucmd = *(struct entry_point_command *)imageHeaderPtr;
            entryoff = ucmd.entryoff;
            break;
        }
        imageHeaderPtr += command->cmdsize;
        command = (struct load_command *)imageHeaderPtr;
    }
    assert(entryoff > 0);
    return (void *)header + entryoff;
}

static NSString* invokeAppMain(NSString *selectedApp, NSString *selectedContainer, int argc, char *argv[]) {
    NSString *appError = nil;
    if([[lcUserDefaults objectForKey:@"LCWaitForDebugger"] boolValue]) {
        sleep(100);
    }
    if (!LCSharedUtils.certificatePassword && !isSideStore) {
#if !TARGET_OS_SIMULATOR
        if(@available(iOS 26.0 ,*))  {
            return @"JITLess mode is required since iOS 26. Please set it up in settings.";
        }
#endif
        // First of all, let's check if we have JIT
        for (int i = 0; i < 10 && !checkJITEnabled(); i++) {
            usleep(1000*100);
        }
        if (!checkJITEnabled()) {
            appError = @"JIT was not enabled. If you want to use LiveContainer without JIT, setup JITLess mode in settings.";
            return appError;
        }
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *docPath = [NSString stringWithFormat:@"%s/Documents", getenv("LC_HOME_PATH")];
    
    NSURL *appGroupFolder = nil;
    
    NSString *bundlePath = 0;
    if(!isSideStore) {
        bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, selectedApp];
    } else if (isLiveProcess) {
        bundlePath = [[NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"Frameworks/SideStoreApp.framework"] path];
    } else {
        bundlePath = [[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Frameworks/SideStoreApp.framework"] path];
    }
    

    guestAppInfo = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", bundlePath]];

    // not found locally, let's look for the app in shared folder
    if(!guestAppInfo) {
        NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[LCSharedUtils appGroupID]];
        appGroupFolder = [appGroupPath URLByAppendingPathComponent:@"LiveContainer"];
        bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", appGroupFolder.path, selectedApp];
        guestAppInfo = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", bundlePath]];
        isSharedBundle = true;
    }
    
    if(!guestAppInfo) {
        return @"App bundle not found! Unable to read LCAppInfo.plist.";
    }
    
    if([guestAppInfo[@"doUseLCBundleId"] boolValue] ) {
        NSMutableDictionary* infoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
        CFErrorRef error = NULL;
        void* taskSelf = SecTaskCreateFromSelf(NULL);
        CFTypeRef value = SecTaskCopyValueForEntitlement(taskSelf, CFSTR("application-identifier"), &error);
        CFRelease(taskSelf);
        if (value) {
            NSString *entStr = (__bridge NSString *)value;
            CFRelease(value);
            NSRange dotRange = [entStr rangeOfString:@"."];
            if (dotRange.location != NSNotFound) {
                NSString *expectedBundleId = [entStr substringFromIndex:dotRange.location + 1];
                if(![infoPlist[@"CFBundleIdentifier"] isEqualToString:expectedBundleId]) {
                    infoPlist[@"CFBundleIdentifier"] = expectedBundleId;
                    [infoPlist writeBinToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
                }
            }
        }
    }
    
    NSBundle *appBundle = [[NSBundle alloc] initWithPathForMainBundle:bundlePath];
    
    if(!appBundle) {
        return @"App not found";
    }
    
    // find container in Info.plist
    NSString* dataUUID = selectedContainer;
    if(!dataUUID) {
        dataUUID = guestAppInfo[@"LCDataUUID"];
    }

    if(dataUUID == nil) {
        return @"Container not found!";
    }
    
    if(isLiveProcess && !isSideStore) {
        lcAppUrlScheme = [lcUserDefaults stringForKey:@"hostUrlScheme"];
        [lcUserDefaults removeObjectForKey:@"hostUrlScheme"];
    }
    
    NSError *error;



    // Setup tweak loader
    NSString *tweakFolder = nil;
    if (isSharedBundle) {
        tweakFolder = [appGroupFolder.path  stringByAppendingPathComponent:@"Tweaks"];
    } else {
        tweakFolder = [docPath stringByAppendingPathComponent:@"Tweaks"];
    }
    setenv("LC_GLOBAL_TWEAKS_FOLDER", tweakFolder.UTF8String, 1);

    // Update TweakLoader symlink
    NSString *tweakLoaderPath = [tweakFolder stringByAppendingPathComponent:@"TweakLoader.dylib"];
    if (![fm fileExistsAtPath:tweakLoaderPath]) {
        remove(tweakLoaderPath.UTF8String);
        NSString *bundlePath = NSBundle.mainBundle.bundlePath;
        if([bundlePath hasSuffix:@"PlugIns/LiveProcess.appex"]) {
            // traverse back to LiveContainer.app
            bundlePath = bundlePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
        }
        NSString *target = [bundlePath stringByAppendingPathComponent:@"Frameworks/TweakLoader.dylib"];
        symlink(target.UTF8String, tweakLoaderPath.UTF8String);
    }

    // If JIT is enabled, bypass library validation so we can load arbitrary binaries
    bool isJitEnabled = checkJITEnabled();
    if (isJitEnabled) {
        init_bypassDyldLibValidation();
    }

    // Locate dyld image name address
    const char **path = _CFGetProcessPath();
    const char *oldPath = *path;
    
    // Overwrite @executable_path
    const char *appExecPath = appBundle.executablePath.fileSystemRepresentation;
    *path = appExecPath;
    overwriteExecPath(appExecPath);
    
    // Overwrite NSUserDefaults
    if([guestAppInfo[@"doUseLCBundleId"] boolValue]) {
        lcGuestAppId = guestAppInfo[@"LCOrignalBundleIdentifier"];
    } else {
        lcGuestAppId = appBundle.bundleIdentifier;
        
    }

    // Overwrite home and tmp path
    NSString *newHomePath = nil;
    NSArray<NSDictionary*>* containers = guestAppInfo[@"LCContainers"];
    NSURL* bookmarkURL = nil;

    // see if the container contains a bookmark. if so, resolve it and report error upon failure.
    if(containers && [containers isKindOfClass:NSArray.class]) {
        for(NSDictionary* container in containers){
            if(![container isKindOfClass:NSDictionary.class]) {
                continue;
            }
            if([container[@"folderName"] isEqualToString:dataUUID]) {
                NSData* bookmarkData = container[@"bookmarkData"];
                if(bookmarkData && [bookmarkData isKindOfClass:NSData.class]) {
                    // we will be killed by watchdog before timedout, so we set this error beforehand.
                    [lcUserDefaults setObject:@"Bookmark resolution timed out. Is the data storage offline?" forKey:@"error"];
                    NSError* err = nil;
                    BOOL isStale = false;
                    bookmarkURL = [NSURL URLByResolvingBookmarkData:bookmarkData options:0 relativeToURL:nil bookmarkDataIsStale:&isStale error:&err];
                    bool access = [bookmarkURL startAccessingSecurityScopedResource];
                    if(!bookmarkURL || !access) {
                        return [@"Bookmark resolution failed or unable to access the container. You might need to readd the data storage. %@" stringByAppendingString:err.localizedDescription];
                    }
                    [lcUserDefaults removeObjectForKey:@"error"];
                }
                break;
            }
        }
    }
    
    if(isSideStore) {
        if(isLiveProcess) {
            newHomePath = [lcUserDefaults stringForKey:@"specifiedSideStoreContainerPath"];;
            [lcUserDefaults removeObjectForKey:@"specifiedSideStoreContainerPath"];
        } else {
            newHomePath = [docPath stringByAppendingPathComponent:@"SideStore"];
        }
    } else if (bookmarkURL) {
        newHomePath = bookmarkURL.path;
    } else if(isSharedBundle) {
        newHomePath = [NSString stringWithFormat:@"%@/Data/Application/%@", appGroupFolder.path, dataUUID];
        
    } else {
        newHomePath = [NSString stringWithFormat:@"%@/Data/Application/%@", docPath, dataUUID];
    }
    
    
    NSString *newTmpPath = [newHomePath stringByAppendingPathComponent:@"tmp"];
    remove(newTmpPath.UTF8String);
    symlink(getenv("TMPDIR"), newTmpPath.UTF8String);
    
    if([guestAppInfo[@"doSymlinkInbox"] boolValue]) {
        NSString* inboxSymlinkPath = [NSString stringWithFormat:@"%s/%@-Inbox", getenv("TMPDIR"), [appBundle bundleIdentifier]];
        NSString* inboxPath = [newHomePath stringByAppendingPathComponent:@"Inbox"];
        
        if (![fm fileExistsAtPath:inboxPath]) {
            [fm createDirectoryAtPath:inboxPath withIntermediateDirectories:YES attributes:nil error:&error];
        }
        if([fm fileExistsAtPath:inboxSymlinkPath]) {
            NSString* fileType = [fm attributesOfItemAtPath:inboxSymlinkPath error:&error][NSFileType];
            if(fileType == NSFileTypeDirectory) {
                NSArray* contents = [fm contentsOfDirectoryAtPath:inboxSymlinkPath error:&error];
                for(NSString* content in contents) {
                    [fm moveItemAtPath:[inboxSymlinkPath stringByAppendingPathComponent:content] toPath:[inboxPath stringByAppendingPathComponent:content] error:&error];
                }
                [fm removeItemAtPath:inboxSymlinkPath error:&error];
            }
        }
        

        symlink(inboxPath.UTF8String, inboxSymlinkPath.UTF8String);
    } else {
        NSString* inboxSymlinkPath = [NSString stringWithFormat:@"%s/%@-Inbox", getenv("TMPDIR"), [appBundle bundleIdentifier]];
        NSDictionary* targetAttribute = [fm attributesOfItemAtPath:inboxSymlinkPath error:&error];
        if(targetAttribute) {
            if(targetAttribute[NSFileType] == NSFileTypeSymbolicLink) {
                [fm removeItemAtPath:inboxSymlinkPath error:&error];
            }
        }

    }
    
    setenv("CFFIXED_USER_HOME", newHomePath.UTF8String, 1);
    setenv("HOME", newHomePath.UTF8String, 1);
    // we don't change TMP's env in case some apps clear cache by directly deleting the tmp folder,
    // which if symlinked, the new tmp cannot be recreated (#1040, #1125) or the app may camplain about the tmp folder being a symlimk (#884)

    // Setup directories
    NSArray *dirList = @[@"Library/Caches", @"Library/Cookies", @"Documents", @"SystemData"];
    for (NSString *dir in dirList) {
        NSString *dirPath = [newHomePath stringByAppendingPathComponent:dir];
        [fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSString* containerInfoPath = [newHomePath stringByAppendingPathComponent:@"LCContainerInfo.plist"];
    guestContainerInfo = [NSDictionary dictionaryWithContentsOfFile:containerInfoPath];
    guestAppInfo = LCGuestAppInfoWithMergedAddonSettings(guestAppInfo, dataUUID, guestContainerInfo);
    
    [LCSharedUtils setContainerUsingByLC:lcAppUrlScheme folderName:dataUUID auditToken:0];

    // Overwrite NSBundle
    overwriteMainNSBundle(appBundle);

    // Overwrite CFBundle
    overwriteMainCFBundle();

    // Overwrite executable info
    if(!appBundle.executablePath) {
        return @"App's executable path not found. Please try force re-signing or reinstalling this app.";
    }

    NSMutableArray<NSString *> *objcArgv = NSProcessInfo.processInfo.arguments.mutableCopy;
    objcArgv[0] = appBundle.executablePath;
    [NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:objcArgv];
    NSProcessInfo.processInfo.processName = appBundle.infoDictionary[@"CFBundleExecutable"];
    *_CFGetProgname() = NSProcessInfo.processInfo.processName.UTF8String;
    Class swiftNSProcessInfo = NSClassFromString(@"_NSSwiftProcessInfo");
    if(swiftNSProcessInfo) {
        // Swizzle the arguments method to return the ObjC arguments
        SEL selector = @selector(arguments);
        method_setImplementation(class_getInstanceMethod(swiftNSProcessInfo, selector), class_getMethodImplementation(NSProcessInfo.class, selector));
    }
    
    // hook NSUserDefault before running libraries' initializers
    NUDGuestHooksInit();
    if(!isSideStore) {
        SecItemGuestHooksInit();
        NSFMGuestHooksInit();
        initDead10ccFix();
    }
    
    // Initialize Ghost-style device spoofing (profile-based with per-feature overrides)
    BOOL useProfileSpoofing = [guestAppInfo[@"deviceSpoofingEnabled"] boolValue];
    BOOL legacyContainerIDFVEnabled = [guestContainerInfo[@"spoofIdentifierForVendor"] boolValue];
    LCDeviceSpoofingBeginConfiguration();
    LCSetDeviceSpoofingEnabled(NO);
    // Reset per-launch version/kernel overrides so previous guest settings cannot leak.
    LCSetSpoofedSystemVersion(nil);
    LCSetSpoofedBuildVersion(nil);
    LCSetSpoofedKernelVersion(nil);
    LCSetSpoofedKernelRelease(nil);

    if(useProfileSpoofing) {
        NSString *deviceProfile = guestAppInfo[@"deviceSpoofProfile"];
        if (deviceProfile.length == 0) {
            deviceProfile = @"iPhone 17";
        }
        LCSetDeviceProfile(deviceProfile);
        // Always derive CPU core count and RAM from selected device profile.
        // Clearing custom overrides prevents stale cross-launch mismatches.
        LCSetSpoofedCPUCount(0);
        LCSetSpoofedPhysicalMemory(0);

        // Independent iOS version override
        NSString *customVersion = guestAppInfo[@"deviceSpoofCustomVersion"];
        if (customVersion.length > 0) {
            LCSetSpoofedSystemVersion(customVersion);
            NSString *mappedBuild = LCSpoofBuildForSystemVersion(customVersion);
            if (mappedBuild.length > 0) {
                LCSetSpoofedBuildVersion(mappedBuild);
            }
        }
        NSString *buildOverride = guestAppInfo[@"deviceSpoofBuildVersion"];
        if (buildOverride.length == 0) {
            buildOverride = guestAppInfo[@"iosVersionBuild"];
        }
        if (buildOverride.length > 0) {
            LCSetSpoofedBuildVersion(buildOverride);
        }

        // Device name spoofing
        if ([guestAppInfo[@"deviceSpoofDeviceName"] boolValue]) {
            NSString *deviceName = guestAppInfo[@"deviceSpoofDeviceNameValue"];
            if (deviceName.length > 0) {
                LCSetSpoofedDeviceName(deviceName);
            }
        }

        // Carrier spoofing
        if ([guestAppInfo[@"deviceSpoofCarrier"] boolValue]) {
            NSString *carrierName = guestAppInfo[@"deviceSpoofCarrierName"];
            if (carrierName.length > 0) {
                LCSetSpoofedCarrierName(carrierName);
            }
            NSString *carrierMCC = guestAppInfo[@"deviceSpoofMCC"];
            if (carrierMCC.length > 0) {
                LCSetSpoofedCarrierMCC(carrierMCC);
            }
            NSString *carrierMNC = guestAppInfo[@"deviceSpoofMNC"];
            if (carrierMNC.length > 0) {
                LCSetSpoofedCarrierMNC(carrierMNC);
            }
            NSString *carrierCountry = guestAppInfo[@"deviceSpoofCarrierCountry"];
            if (carrierCountry.length > 0) {
                LCSetSpoofedCarrierCountryCode(carrierCountry);
                LCSetSpoofedPreferredCountryCode(carrierCountry);
            }
        }

        BOOL spoofCellularType = [guestAppInfo[@"deviceSpoofCellularTypeEnabled"] boolValue] ||
                                 [guestAppInfo[@"enableSpoofCellularType"] boolValue];
        id cellularTypeObj = guestAppInfo[@"deviceSpoofCellularType"] ?: guestAppInfo[@"cellularType"];
        if (!spoofCellularType &&
            guestAppInfo[@"deviceSpoofCellularTypeEnabled"] == nil &&
            guestAppInfo[@"enableSpoofCellularType"] == nil &&
            cellularTypeObj != nil) {
            spoofCellularType = YES;
        }
        if (spoofCellularType && cellularTypeObj != nil) {
            LCSetSpoofedCellularType([cellularTypeObj integerValue]);
        }

        BOOL spoofNetworkInfo = [guestAppInfo[@"deviceSpoofNetworkInfo"] boolValue] ||
                                [guestAppInfo[@"enableSpoofNetworkInfo"] boolValue];
        LCSetNetworkInfoSpoofingEnabled(spoofNetworkInfo);

        NSString *wifiSSID = guestAppInfo[@"deviceSpoofWiFiSSID"];
        if (wifiSSID.length == 0) {
            wifiSSID = guestAppInfo[@"wifiSSID"];
        }
        if (wifiSSID.length > 0) {
            LCSetSpoofedWiFiSSID(wifiSSID);
        }

        NSString *wifiBSSID = guestAppInfo[@"deviceSpoofWiFiBSSID"];
        if (wifiBSSID.length == 0) {
            wifiBSSID = guestAppInfo[@"wifiBSSID"];
        }
        if (wifiBSSID.length > 0) {
            LCSetSpoofedWiFiBSSID(wifiBSSID);
        }

        BOOL spoofWiFiAddress = [guestAppInfo[@"deviceSpoofWiFiAddressEnabled"] boolValue] ||
                                [guestAppInfo[@"enableSpoofWiFi"] boolValue];
        NSString *wifiAddress = guestAppInfo[@"deviceSpoofWiFiAddress"];
        if (wifiAddress.length == 0) {
            wifiAddress = guestAppInfo[@"wifiAddress"];
        }
        if (!spoofWiFiAddress &&
            guestAppInfo[@"deviceSpoofWiFiAddressEnabled"] == nil &&
            guestAppInfo[@"enableSpoofWiFi"] == nil &&
            wifiAddress.length > 0) {
            spoofWiFiAddress = YES;
        }
        LCSetWiFiAddressSpoofingEnabled(spoofWiFiAddress);
        if (wifiAddress.length > 0) {
            LCSetSpoofedWiFiAddress(wifiAddress);
        }

        BOOL spoofCellularAddress = [guestAppInfo[@"deviceSpoofCellularAddressEnabled"] boolValue] ||
                                    [guestAppInfo[@"enableSpoofCellular"] boolValue];
        NSString *cellularAddress = guestAppInfo[@"deviceSpoofCellularAddress"];
        if (cellularAddress.length == 0) {
            cellularAddress = guestAppInfo[@"cellularAddress"];
        }
        if (!spoofCellularAddress &&
            guestAppInfo[@"deviceSpoofCellularAddressEnabled"] == nil &&
            guestAppInfo[@"enableSpoofCellular"] == nil &&
            cellularAddress.length > 0) {
            spoofCellularAddress = YES;
        }
        LCSetCellularAddressSpoofingEnabled(spoofCellularAddress);
        if (cellularAddress.length > 0) {
            LCSetSpoofedCellularAddress(cellularAddress);
        }

        // MAC address spoofing (en0)
        id macEnabledObj = guestAppInfo[@"deviceSpoofMACAddressEnabled"];
        BOOL spoofMAC = macEnabledObj ? [macEnabledObj boolValue] : NO;
        NSString *macAddress = guestAppInfo[@"deviceSpoofMACAddress"];
        if (!spoofMAC && macEnabledObj == nil && macAddress.length > 0) {
            spoofMAC = YES;
        }
        if (spoofMAC && macAddress.length > 0) {
            LCSetSpoofedMACAddress(macAddress);
        }

        // Identifier spoofing (IDFV / IDFA)
        id spoofIdentifiersObj = guestAppInfo[@"deviceSpoofIdentifiers"];
        BOOL spoofIdentifiers = spoofIdentifiersObj ? [spoofIdentifiersObj boolValue] : legacyContainerIDFVEnabled;
        if (spoofIdentifiers) {
            NSString *vendorID = guestAppInfo[@"deviceSpoofVendorID"];
            if (vendorID.length == 0) {
                vendorID = guestContainerInfo[@"spoofedIdentifierForVendor"];
            }
            if (vendorID.length > 0) {
                LCSetSpoofedVendorID(vendorID);
            }
            NSString *advertisingID = guestAppInfo[@"deviceSpoofAdvertisingID"];
            if (advertisingID.length > 0) {
                LCSetSpoofedAdvertisingID(advertisingID);
            }
        }

        // Ad tracking spoofing (optional override; auto by default)
        NSString *adTrackingMode = guestAppInfo[@"deviceSpoofAdTrackingMode"];
        if ([adTrackingMode isKindOfClass:[NSString class]] && adTrackingMode.length > 0) {
            NSString *normalized = [adTrackingMode lowercaseString];
            if ([normalized isEqualToString:@"enabled"]) {
                LCSetSpoofedAdTrackingEnabled(YES);
            } else if ([normalized isEqualToString:@"disabled"]) {
                LCSetSpoofedAdTrackingEnabled(NO);
            }
        }

        id securityMasterObj = guestAppInfo[@"deviceSpoofSecurityEnabled"];
        BOOL securityMasterEnabled = securityMasterObj ? [securityMasterObj boolValue] : YES;

        id deviceCheckerObj = guestAppInfo[@"deviceSpoofDeviceChecker"];
        if (deviceCheckerObj == nil) {
            deviceCheckerObj = guestAppInfo[@"enableSpoofDeviceChecker"];
        }
        BOOL spoofDeviceCheck = deviceCheckerObj ? [deviceCheckerObj boolValue] :
                                (securityMasterEnabled || [guestAppInfo[@"deviceSpoofIdentifiers"] boolValue]);

        id appAttestObj = guestAppInfo[@"deviceSpoofAppAttest"];
        if (appAttestObj == nil) {
            appAttestObj = guestAppInfo[@"enableSpoofAppAttest"];
        }
        BOOL spoofAppAttest = appAttestObj ? [appAttestObj boolValue] : spoofDeviceCheck;
        LCSetDeviceCheckSpoofingEnabled(spoofDeviceCheck);
        LCSetAppAttestSpoofingEnabled(spoofAppAttest);

        id cloudTokenSetting = guestAppInfo[@"deviceSpoofCloudToken"];
        if (cloudTokenSetting == nil) {
            cloudTokenSetting = guestAppInfo[@"enableSpoofCloudToken"];
        }
        BOOL spoofCloudToken = cloudTokenSetting ? [cloudTokenSetting boolValue] : securityMasterEnabled;
        LCSetICloudPrivacyProtectionEnabled(spoofCloudToken);

        // Siri privacy protection (opt-in)
        BOOL spoofSiri = [guestAppInfo[@"deviceSpoofSiriPrivacyProtection"] boolValue];
        LCSetSiriPrivacyProtectionEnabled(spoofSiri);

        // Timezone spoofing
        if ([guestAppInfo[@"deviceSpoofTimezone"] boolValue]) {
            NSString *timezone = guestAppInfo[@"deviceSpoofTimezoneValue"];
            if (timezone.length > 0) {
                LCSetSpoofedTimezone(timezone);
            }
        }

        // Locale spoofing
        BOOL spoofLocale = [guestAppInfo[@"deviceSpoofLocale"] boolValue] ||
                           [guestAppInfo[@"enableSpoofLocale"] boolValue];
        if (spoofLocale) {
            NSString *locale = guestAppInfo[@"deviceSpoofLocaleValue"];
            if (locale.length == 0) {
                locale = guestAppInfo[@"localeID"];
            }
            if (locale.length > 0) {
                LCSetSpoofedLocale(locale);
            }
        }
        NSString *currencyCode = guestAppInfo[@"deviceSpoofLocaleCurrencyCode"];
        if (currencyCode.length == 0) {
            currencyCode = guestAppInfo[@"localeCurrencyCode"];
        }
        if (currencyCode.length > 0) {
            LCSetSpoofedLocaleCurrencyCode(currencyCode);
        }
        NSString *currencySymbol = guestAppInfo[@"deviceSpoofLocaleCurrencySymbol"];
        if (currencySymbol.length == 0) {
            currencySymbol = guestAppInfo[@"localeCurrencySymbol"];
        }
        if (currencySymbol.length > 0) {
            LCSetSpoofedLocaleCurrencySymbol(currencySymbol);
        }

        NSString *preferredCountry = guestAppInfo[@"deviceSpoofPreferredCountry"];
        if (preferredCountry.length == 0) {
            preferredCountry = guestAppInfo[@"localeCountryCode"];
        }
        if (preferredCountry.length == 0) {
            preferredCountry = guestAppInfo[@"deviceSpoofCarrierCountry"];
        }
        if (preferredCountry.length > 0) {
            LCSetSpoofedPreferredCountryCode(preferredCountry);
        }

        NSString *installationID = guestAppInfo[@"deviceSpoofInstallationID"];
        if (installationID.length > 0) {
            LCSetSpoofedInstallationID(installationID);
        }

        NSString *persistentDeviceID = guestAppInfo[@"deviceSpoofPersistentDeviceID"];
        if (persistentDeviceID.length == 0) {
            persistentDeviceID = guestAppInfo[@"persistentDeviceID"];
        }
        if (persistentDeviceID.length == 0) {
            persistentDeviceID = guestAppInfo[@"deviceID"];
        }
        if (persistentDeviceID.length > 0) {
            LCSetSpoofedPersistentDeviceID(persistentDeviceID);
        }

        BOOL spoofKernelVersion = [guestAppInfo[@"deviceSpoofKernelVersionEnabled"] boolValue] ||
                                  [guestAppInfo[@"enableSpoofKernelVersion"] boolValue];
        NSString *kernelVersion = guestAppInfo[@"deviceSpoofKernelVersion"];
        NSString *kernelRelease = guestAppInfo[@"deviceSpoofKernelRelease"];
        BOOL explicitKernelOverride = (kernelVersion.length > 0 || kernelRelease.length > 0);

        // Migrate historical iPhone 17 defaults that used older T8140/T8130 kernel codes.
        // If present, prefer profile-derived kernel metadata (T8150) for consistency.
        NSString *normalizedProfile = [[[deviceProfile lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""]
                                       stringByReplacingOccurrencesOfString:@"-" withString:@""];
        BOOL isIPhone17FamilyProfile = [normalizedProfile hasPrefix:@"iphone17"];
        if (explicitKernelOverride && isIPhone17FamilyProfile) {
            NSString *normalizedKernel = kernelVersion.lowercaseString;
            BOOL hasLegacySocCode = [normalizedKernel containsString:@"release_arm64_t8140"] ||
                                    [normalizedKernel containsString:@"release_arm64_t8130"];
            BOOL hasLegacyKernelRelease = (kernelRelease.length > 0 && [kernelRelease hasPrefix:@"24."]);
            if (hasLegacySocCode || hasLegacyKernelRelease) {
                kernelVersion = @"";
                kernelRelease = @"";
                explicitKernelOverride = NO;
            }
        }

        // In profile mode, do not fallback to legacy keys to avoid stale overrides
        // superseding the selected profile's kernel metadata.
        if (!explicitKernelOverride && !useProfileSpoofing) {
            if (kernelVersion.length == 0) {
                kernelVersion = guestAppInfo[@"kernelVersion"];
            }
            if (kernelVersion.length == 0) {
                kernelVersion = guestAppInfo[@"selectedKernelVersion"];
            }
            if (kernelRelease.length == 0) {
                kernelRelease = guestAppInfo[@"kernelVersionDarwin"];
            }
            explicitKernelOverride = (kernelVersion.length > 0 || kernelRelease.length > 0);
        }

        if (!spoofKernelVersion && guestAppInfo[@"enableSpoofKernelVersion"] == nil && explicitKernelOverride) {
            spoofKernelVersion = YES;
        }
        if (spoofKernelVersion && explicitKernelOverride) {
            if (kernelVersion.length > 0) {
                LCSetSpoofedKernelVersion(kernelVersion);
            }
            if (kernelRelease.length > 0) {
                LCSetSpoofedKernelRelease(kernelRelease);
            }
        }

        BOOL spoofProximity = [guestAppInfo[@"deviceSpoofProximity"] boolValue] ||
                              [guestAppInfo[@"enableSpoofProximity"] boolValue];
        BOOL spoofOrientation = [guestAppInfo[@"deviceSpoofOrientation"] boolValue] ||
                                [guestAppInfo[@"enableSpoofOrientation"] boolValue];
        BOOL spoofGyroscope = [guestAppInfo[@"deviceSpoofGyroscope"] boolValue] ||
                              [guestAppInfo[@"enableSpoofGyroscope"] boolValue];
        LCSetProximitySpoofingEnabled(spoofProximity);
        LCSetOrientationSpoofingEnabled(spoofOrientation);
        LCSetGyroscopeSpoofingEnabled(spoofGyroscope);

        // Screen capture detection blocking
        id spoofMessageObj = guestAppInfo[@"enableSpoofMessage"];
        BOOL spoofMessage = spoofMessageObj ? [spoofMessageObj boolValue] : securityMasterEnabled;
        id spoofMailObj = guestAppInfo[@"enableSpoofMail"];
        BOOL spoofMail = spoofMailObj ? [spoofMailObj boolValue] : securityMasterEnabled;
        id spoofBugsnagObj = guestAppInfo[@"enableSpoofBugsnag"];
        BOOL spoofBugsnag = spoofBugsnagObj ? [spoofBugsnagObj boolValue] : securityMasterEnabled;
        id spoofCraneObj = guestAppInfo[@"enableSpoofCrane"];
        BOOL spoofCrane = spoofCraneObj ? [spoofCraneObj boolValue] : securityMasterEnabled;
        id spoofPasteboardObj = guestAppInfo[@"enableSpoofPasteboard"];
        BOOL spoofPasteboard = spoofPasteboardObj ? [spoofPasteboardObj boolValue] : securityMasterEnabled;
        id spoofAlbumObj = guestAppInfo[@"enableSpoofAlbum"];
        BOOL spoofAlbum = spoofAlbumObj ? [spoofAlbumObj boolValue] : securityMasterEnabled;
        id spoofAppiumObj = guestAppInfo[@"enableSpoofAppium"];
        if (spoofAppiumObj == nil) {
            spoofAppiumObj = guestAppInfo[@"deviceSpoofAppium"];
        }
        BOOL spoofAppium = spoofAppiumObj ? [spoofAppiumObj boolValue] : securityMasterEnabled;
        id spoofKeyboardObj = guestAppInfo[@"enableSpoofKeyboard"];
        if (spoofKeyboardObj == nil) {
            spoofKeyboardObj = guestAppInfo[@"deviceSpoofKeyboard"];
        }
        BOOL spoofKeyboard = spoofKeyboardObj ? [spoofKeyboardObj boolValue] : securityMasterEnabled;
        id spoofUserDefaultsObj = guestAppInfo[@"enableSpoofUserDefaults"];
        if (spoofUserDefaultsObj == nil) {
            spoofUserDefaultsObj = guestAppInfo[@"deviceSpoofUserDefaults"];
        }
        BOOL spoofUserDefaults = spoofUserDefaultsObj ? [spoofUserDefaultsObj boolValue] : securityMasterEnabled;
        id spoofEntitlementsObj = guestAppInfo[@"enableSpoofEntitlements"];
        if (spoofEntitlementsObj == nil) {
            spoofEntitlementsObj = guestAppInfo[@"deviceSpoofEntitlements"];
        }
        BOOL spoofEntitlements = spoofEntitlementsObj ? [spoofEntitlementsObj boolValue] : securityMasterEnabled;
        id spoofFileTimestampsObj = guestAppInfo[@"deviceSpoofFileTimestamps"];
        if (spoofFileTimestampsObj == nil) {
            spoofFileTimestampsObj = guestAppInfo[@"enableSpoofFileTimestamps"];
        }
        BOOL spoofFileTimestamps = spoofFileTimestampsObj ? [spoofFileTimestampsObj boolValue] : securityMasterEnabled;
        LCSetSpoofMessageEnabled(spoofMessage);
        LCSetSpoofMailEnabled(spoofMail);
        LCSetSpoofBugsnagEnabled(spoofBugsnag);
        LCSetSpoofCraneEnabled(spoofCrane);
        LCSetSpoofPasteboardEnabled(spoofPasteboard);
        LCSetSpoofAlbumEnabled(spoofAlbum);
        LCSetSpoofAppiumEnabled(spoofAppium);
        LCSetKeyboardSpoofingEnabled(spoofKeyboard);
        LCSetUserDefaultsSpoofingEnabled(spoofUserDefaults);
        LCSetEntitlementsSpoofingEnabled(spoofEntitlements);
        LCSetFileTimestampSpoofingEnabled(spoofFileTimestamps);

        id spoofScreenCaptureObj = guestAppInfo[@"deviceSpoofScreenCapture"];
        if (spoofScreenCaptureObj == nil) {
            spoofScreenCaptureObj = guestAppInfo[@"enableSpoofScreenCapture"];
        }
        BOOL spoofScreenCaptureMaster = spoofScreenCaptureObj ? [spoofScreenCaptureObj boolValue] : securityMasterEnabled;
        BOOL spoofScreenCaptureGroup = spoofScreenCaptureMaster ||
                                       spoofMessage || spoofMail || spoofBugsnag || spoofCrane ||
                                       spoofPasteboard || spoofAlbum || spoofAppium;
        if (spoofScreenCaptureGroup) {
            LCSetScreenCaptureBlockEnabled(YES);
            id albumBlacklist = guestAppInfo[@"deviceSpoofAlbumBlacklist"] ?: guestAppInfo[@"albumBlacklistArray"];
            if (spoofAlbum && [albumBlacklist isKindOfClass:[NSArray class]]) {
                LCSetAlbumBlacklistArray(albumBlacklist);
            }
        }

        // Boot time / uptime spoofing (Project-X BootTimeHooks parity)
        if ([guestAppInfo[@"deviceSpoofBootTime"] boolValue]) {
            NSString *range = guestAppInfo[@"deviceSpoofBootTimeRange"] ?: @"medium";
            id randomizeObj = guestAppInfo[@"deviceSpoofBootTimeRandomize"];
            BOOL randomize = randomizeObj ? [randomizeObj boolValue] : YES;
            if (randomize) {
                LCSetSpoofedBootTimeRange(range);
            } else {
                LCSetSpoofedUptimeSeconds(LCUptimeSecondsFromPreset(range));
            }
        }

        // Canvas/WebGL/Audio fingerprint protection (default ON to match historical profile spoofing behavior)
        id canvasSetting = guestAppInfo[@"deviceSpoofCanvasFingerprintProtection"];
        BOOL canvasProtectionEnabled = canvasSetting ? [canvasSetting boolValue] : YES;
        LCSetCanvasFingerprintProtectionEnabled(canvasProtectionEnabled);

        // User-Agent spoofing
        if ([guestAppInfo[@"deviceSpoofUserAgent"] boolValue]) {
            NSString *ua = guestAppInfo[@"deviceSpoofUserAgentValue"];
            if (ua.length > 0) {
                LCSetSpoofedUserAgent(ua);
            }
        }

        // Battery spoofing (Project-X BatteryHooks parity)
        if ([guestAppInfo[@"deviceSpoofBattery"] boolValue]) {
            id randomizeObj = guestAppInfo[@"deviceSpoofBatteryRandomize"];
            BOOL randomize = randomizeObj ? [randomizeObj boolValue] : YES;
            if (randomize) {
                LCRandomizeBattery();
            } else {
                float level = [guestAppInfo[@"deviceSpoofBatteryLevel"] floatValue];
                int state = [guestAppInfo[@"deviceSpoofBatteryState"] intValue];
                LCSetSpoofedBatteryLevel(level);
                LCSetSpoofedBatteryState(state);
            }
        }

        // Storage capacity spoofing
        if ([guestAppInfo[@"deviceSpoofStorage"] boolValue]) {
            NSString *cap = guestAppInfo[@"deviceSpoofStorageCapacity"];
            if (cap.length == 0) {
                cap = LCDefaultStorageCapacityForProfile(deviceProfile);
            }
            long long capGB = [cap longLongValue];
            if (capGB <= 0) {
                cap = LCDefaultStorageCapacityForProfile(deviceProfile);
                capGB = [cap longLongValue];
            }
            id randomizeFreeObj = guestAppInfo[@"deviceSpoofStorageRandomFree"];
            BOOL randomizeFree = randomizeFreeObj ? [randomizeFreeObj boolValue] : YES;
            LCSetStorageRandomFreeEnabled(randomizeFree);
            LCSetSpoofedStorageCapacity(capGB);
            if (!randomizeFree) {
                NSString *freeGB = guestAppInfo[@"deviceSpoofStorageFreeGB"];
                if (freeGB.length > 0) {
                    LCSetSpoofedStorageFree(freeGB);
                }
            }
        }

        // Brightness spoofing
        if ([guestAppInfo[@"deviceSpoofBrightness"] boolValue]) {
            id randomizeObj = guestAppInfo[@"deviceSpoofBrightnessRandomize"];
            BOOL randomize = randomizeObj ? [randomizeObj boolValue] : NO;
            if (randomize) {
                LCRandomizeBrightness();
            } else {
                LCSetSpoofedBrightness([guestAppInfo[@"deviceSpoofBrightnessValue"] floatValue]);
            }
        }

        // Thermal state spoofing
        if ([guestAppInfo[@"deviceSpoofThermal"] boolValue]) {
            LCSetSpoofedThermalState([guestAppInfo[@"deviceSpoofThermalState"] intValue]);
        }

        // Low power mode spoofing
        if ([guestAppInfo[@"deviceSpoofLowPowerMode"] boolValue]) {
            LCSetSpoofedLowPowerMode(YES, [guestAppInfo[@"deviceSpoofLowPowerModeValue"] boolValue]);
        }

    }
    
    // ignore setting handler from guest app
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, NSSetUncaughtExceptionHandler, hook_do_nothing, nil);
    
    BOOL hookDlopen = !isSideStore && !isSharedBundle && LCSharedUtils.certificatePassword && isLiveProcess;
    DyldHooksInit([guestAppInfo[@"hideLiveContainer"] boolValue], hookDlopen, [guestAppInfo[@"spoofSDKVersion"] unsignedIntValue]);

    LCDeviceSpoofingEndConfiguration();
    
    // Install DeviceSpoofing hooks after Dyld so Dyld stays the authoritative owner for shared hook surfaces.
    if (useProfileSpoofing) {
        LCSetDeviceSpoofingEnabled(YES);
        DeviceSpoofingGuestHooksInit();
    }
#if is32BitSupported
    bool is32bit = [guestAppInfo[@"is32bit"] boolValue];
    if(is32bit) {
        if (!isJitEnabled) {
            return @"JIT is required to run 32-bit apps.";
        }
        
        NSString *selected32BitLayer = [lcUserDefaults stringForKey:@"selected32BitLayer"];
        if(!selected32BitLayer || [selected32BitLayer length] == 0) {
            appError = @"No 32-bit translation layer installed";
            NSLog(@"[LCBootstrap] %@", appError);
            *path = oldPath;
            return appError;
        }
        NSBundle *selected32bitLayerBundle = [NSBundle bundleWithPath:[docPath stringByAppendingPathComponent:selected32BitLayer]]; //TODO make it user friendly;
        if(!selected32bitLayerBundle) {
            appError = @"The specified LiveExec32.app path is not found";
            NSLog(@"[LCBootstrap] %@", appError);
            *path = oldPath;
            return appError;
        }
        // maybe need to save selected32bitLayerBundle to static variable?
        appExecPath = strdup(selected32bitLayerBundle.executablePath.UTF8String);
    }
#endif
    if(![guestAppInfo[@"dontInjectTweakLoader"] boolValue]) {
        tweakLoaderLoaded = true;
    }
    
    // Preload executable to bypass RT_NOLOAD
    appMainImageIndex = _dyld_image_count();
    void *appHandle = dlopen_nolock(appExecPath, RTLD_LAZY|RTLD_GLOBAL|RTLD_FIRST);
    appExecutableHandle = appHandle;
    const char *dlerr = dlerror();
    
    if (!appHandle || (uint64_t)appHandle > 0xf00000000000) {
        if (dlerr) {
            appError = @(dlerr);
        } else {
            appError = @"dlopen: an unknown error occurred";
        }
        NSLog(@"[LCBootstrap] %@", appError);
        *path = oldPath;
        return appError;
    }
    
    if([guestAppInfo[@"dontInjectTweakLoader"] boolValue] && ![guestAppInfo[@"dontLoadTweakLoader"] boolValue]) {
        tweakLoaderLoaded = true;
        dlopen("@loader_path/../TweakLoader.dylib", RTLD_LAZY|RTLD_GLOBAL);
    }
    
    if(isSideStore) {
        tweakLoaderLoaded = true;
        dlopen([lcMainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/TweakLoader.dylib"].UTF8String, RTLD_LAZY|RTLD_GLOBAL);
    }
    
    if(!isSideStore && sideStoreExist && ![guestAppInfo[@"dontInjectTweakLoader"] boolValue]) {
        dlopen([lcMainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/SideStore.framework/SideStore"].UTF8String, RTLD_LAZY);
    }
    
    // Fix dynamic properties of some apps
    [NSUserDefaults performSelector:@selector(initialize)];

    // Attempt to load the bundle. 32-bit bundle will always fail because of 32-bit main executable, so ignore it
    if (
#if is32BitSupported
        !is32bit &&
#endif
        ![appBundle loadAndReturnError:&error]
        ) {
        appError = error.localizedDescription;
        NSLog(@"[LCBootstrap] loading bundle failed: %@", error);
        *path = oldPath;
        return appError;
    }
    NSLog(@"[LCBootstrap] loaded bundle");

    // Find main()
    appMain = getAppEntryPoint(appHandle);
    if (!appMain) {
        appError = @"Could not find the main entry point";
        NSLog(@"[LCBootstrap] %@", appError);
        *path = oldPath;
        return appError;
    }

    // Go!
    NSLog(@"[LCBootstrap] jumping to main %p", appMain);
    int ret;
#if is32BitSupported
    if(!is32bit) {
#endif
        argv[0] = (char *)appExecPath;
        ret = appMain(argc, argv);
#if is32BitSupported
    } else {
        char *argv32[] = {(char*)appExecPath, (char*)*path, NULL};
        ret = appMain(sizeof(argv32)/sizeof(*argv32) - 1, argv32);
    }
#endif
    return [NSString stringWithFormat:@"App returned from its main function with code %d.", ret];
}

static void exceptionHandler(NSException *exception) {
    NSString *error = [NSString stringWithFormat:@"%@\nCall stack: %@", exception.reason, exception.callStackSymbols];
    if(isLiveProcess) {
        NSExtensionContext *context = [NSClassFromString(@"LiveProcessHandler") extensionContext];
        [context cancelRequestWithError:[NSError errorWithDomain:@"LiveProcess" code:1 userInfo:@{NSLocalizedDescriptionKey: error}]];
    } else {
        [lcUserDefaults setObject:error forKey:@"error"];
    }
}

int LiveContainerMain(int argc, char *argv[]) {
    lcMainBundle = [NSBundle mainBundle];
    lcUserDefaults = NSUserDefaults.standardUserDefaults;
    
    lcSharedDefaults = [[NSUserDefaults alloc] initWithSuiteName: [LCSharedUtils appGroupID]];
    lcAppUrlScheme = NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0];
    lcAppGroupPath = [[NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[NSClassFromString(@"LCSharedUtils") appGroupID]] path];
    isLiveProcess = [lcAppUrlScheme isEqualToString:@"liveprocess"];
    setenv("LC_HOME_PATH", getenv("HOME"), 0);

    NSString *selectedApp = [lcUserDefaults stringForKey:@"selected"];
    NSString *selectedContainer = [lcUserDefaults stringForKey:@"selectedContainer"];
    if(!selectedApp) {
        NSString* selectedAppFromLaunchExtension = [lcSharedDefaults stringForKey:@"LCLaunchExtensionBundleID"];
        
        if(selectedAppFromLaunchExtension) {
            NSDate* launchDate = [lcSharedDefaults objectForKey:@"LCLaunchExtensionLaunchDate"];
            NSTimeInterval secondsSinceDate = [launchDate timeIntervalSinceNow];

            if (secondsSinceDate < 0 && secondsSinceDate >= -3.0) {
                selectedApp = selectedAppFromLaunchExtension;
                selectedContainer = [lcSharedDefaults stringForKey:@"LCLaunchExtensionContainerName"];
            }
            [lcSharedDefaults removeObjectForKey:@"LCLaunchExtensionBundleID"];
            [lcSharedDefaults removeObjectForKey:@"LCLaunchExtensionContainerName"];
        }
    }
    
    NSString* lastLaunchDataUUID;
    if(!isLiveProcess) {
        lastLaunchDataUUID = [lcUserDefaults objectForKey:@"lastLaunchDataUUID"];
    } else {
        lastLaunchDataUUID = selectedContainer;
    }
    
    // we put all files in app group after fixing 0xdead10cc. This call is here in case user upgraded lc with app's data in private Library/SharedDocuments
    [LCSharedUtils moveSharedAppFolderBack];
    
    if(lastLaunchDataUUID) {
        NSString* lastLaunchType = [lcUserDefaults objectForKey:@"lastLaunchType"];
        NSString* preferencesTo;
        if([lastLaunchType isEqualToString:@"Shared"]) {
            preferencesTo = [LCSharedUtils.appGroupPath.path stringByAppendingPathComponent:[NSString stringWithFormat:@"LiveContainer/Data/Application/%@/Library/Preferences", lastLaunchDataUUID]];
        } else {
            NSString *docPath = [NSString stringWithFormat:@"%s/Documents", getenv("LC_HOME_PATH")];
            preferencesTo = [docPath stringByAppendingPathComponent:[NSString stringWithFormat:@"Data/Application/%@/Library/Preferences", lastLaunchDataUUID]];
        }
        // recover preferences
        // this is not needed anymore, it's here for backward competability
        [LCSharedUtils dumpPreferenceToPath:preferencesTo dataUUID:lastLaunchDataUUID];
        if(!isLiveProcess) {
            [lcUserDefaults removeObjectForKey:@"lastLaunchDataUUID"];
            [lcUserDefaults removeObjectForKey:@"lastLaunchType"];
        }
    }

    if([selectedApp isEqualToString:@"ui"]) {
        selectedApp = nil;
        [lcUserDefaults removeObjectForKey:@"selected"];
        [lcUserDefaults removeObjectForKey:@"selectedContainer"];
    }
    
    if(isLiveProcess) {
        sideStoreExist = [NSFileManager.defaultManager fileExistsAtPath:[lcMainBundle.bundlePath stringByAppendingPathComponent:@"../../Frameworks/SideStoreApp.framework"]];
    } else {
        sideStoreExist = [NSFileManager.defaultManager fileExistsAtPath:[lcMainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/SideStoreApp.framework"]];
    }

    if([lcUserDefaults boolForKey:@"LCOpenSideStore"] || [selectedApp isEqualToString:@"builtinSideStore"]) {
        if(sideStoreExist) {
            isSideStore = true;
        } else {
            [lcUserDefaults setBool:NO forKey:@"LCOpenSideStore"];
        }
    }
    
    if(selectedApp && !isSideStore && !selectedContainer) {
        selectedContainer = [LCSharedUtils findDefaultContainerWithBundleId:selectedApp];
    }
    NSString* runningLC = [LCSharedUtils getContainerUsingLCSchemeWithFolderName:selectedContainer];
    // if another instance is running, we just switch to that one, these should be called after uiapplication initialized
    // however if the running lc is liveprocess and current lc is livecontainer1 we just continue
    if(selectedApp && runningLC) {
        [lcUserDefaults removeObjectForKey:@"selected"];
        [lcUserDefaults removeObjectForKey:@"selectedContainer"];
        
        if([runningLC hasSuffix:@"liveprocess"]) {
            runningLC = runningLC.stringByDeletingPathExtension;
        }
        
        NSString* selectedAppBackUp = selectedApp;
        selectedApp = nil;
        dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC));
        dispatch_after(delay, dispatch_get_main_queue(), ^{
            // Base64 encode the data
            NSString* urlStr;
            if(selectedContainer) {
                urlStr = [NSString stringWithFormat:@"%@://livecontainer-launch?bundle-name=%@&container-folder-name=%@", runningLC, selectedAppBackUp, selectedContainer];
            } else {
                urlStr = [NSString stringWithFormat:@"%@://livecontainer-launch?bundle-name=%@", runningLC, selectedAppBackUp];
            }
            
            NSURL* url = [NSURL URLWithString:urlStr];
            if([[NSClassFromString(@"UIApplication") sharedApplication] canOpenURL:url]){
                [[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];
                
                NSString *launchUrl = [lcUserDefaults stringForKey:@"launchAppUrlScheme"];
                // also pass url scheme to another lc
                if(launchUrl) {
                    [lcUserDefaults removeObjectForKey:@"launchAppUrlScheme"];

                    // Base64 encode the data
                    NSData *data = [launchUrl dataUsingEncoding:NSUTF8StringEncoding];
                    NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
                    
                    NSString* finalUrl = [NSString stringWithFormat:@"%@://open-url?url=%@", runningLC, encodedUrl];
                    NSURL* url = [NSURL URLWithString: finalUrl];
                    
                    [[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];

                }
            }
        });

    }
    
    if (selectedApp || isSideStore) {
        
        NSString *launchUrl = [lcUserDefaults stringForKey:@"launchAppUrlScheme"];
        [lcUserDefaults removeObjectForKey:@"selected"];
        [lcUserDefaults removeObjectForKey:@"selectedContainer"];
        // wait for app to launch so that it can receive the url
        if(launchUrl) {
            [lcUserDefaults removeObjectForKey:@"launchAppUrlScheme"];
            dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC));
            dispatch_after(delay, dispatch_get_main_queue(), ^{
                // Base64 encode the data
                NSData *data = [launchUrl dataUsingEncoding:NSUTF8StringEncoding];
                NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
                
                NSString* finalUrl = [NSString stringWithFormat:@"%@://open-url?url=%@", lcAppUrlScheme, encodedUrl];
                NSURL* url = [NSURL URLWithString: finalUrl];
                
                [[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];
            });
        }
        NSSetUncaughtExceptionHandler(&exceptionHandler);
        NSString *appError = invokeAppMain(selectedApp, selectedContainer, argc, argv);
        if (appError) {
            if(isLiveProcess) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                    NSExtensionContext *context = [NSClassFromString(@"LiveProcessHandler") extensionContext];
                    [context cancelRequestWithError:[NSError errorWithDomain:@"LiveProcess" code:1 userInfo:@{NSLocalizedDescriptionKey: appError}]];
                    exit(1);
                });
                // spin and wait for iOS to terminate
                CFRunLoopRun();
            } else {
                [lcUserDefaults setObject:appError forKey:@"error"];
                // potentially unrecovable state, exit now
                return 1;
            }
        }
    }
    
    if(isLiveProcess) {
        NSLog(@"LiveProcess should not launch lcui!");
        return 0;
    }
    
    // put back cookies
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *libraryURL = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;;
    NSURL *cookies2URL = [libraryURL URLByAppendingPathComponent:@"Cookies2"];
    
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:cookies2URL.path isDirectory:&isDir] && isDir) {
        NSError *error = nil;
        NSURL *cookiesURL  = [libraryURL URLByAppendingPathComponent:@"Cookies"];
        // Remove old Caches folder if exists
        if ([fm fileExistsAtPath:cookiesURL.path]) {
            if ([fm removeItemAtURL:cookiesURL error:&error]) {
                [fm moveItemAtURL:cookies2URL toURL:cookiesURL error:&error];
            } else{
                NSLog(@"Failed to remove old Cookies folder: %@", error);
            }
        }
    }
    
    void *LiveContainerSwiftUIHandle = dlopen("@executable_path/Frameworks/LiveContainerSwiftUI.framework/LiveContainerSwiftUI", RTLD_LAZY);
    assert(LiveContainerSwiftUIHandle);
    
    if(sideStoreExist) {
        void* sideStoreHandle = dlopen("@executable_path/Frameworks/SideStore.framework/SideStore", RTLD_LAZY);
    }

    if ([lcUserDefaults boolForKey:@"LCLoadTweaksToSelf"]) {
        NSString *tweakFolder = nil;
        if (isSharedBundle) {
            NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[LCSharedUtils appGroupID]];
            tweakFolder = [appGroupPath.path stringByAppendingPathComponent:@"LiveContainer/Tweaks"];
        } else {
            NSString *docPath = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
            tweakFolder = [docPath stringByAppendingPathComponent:@"Tweaks"];
        }
        setenv("LC_GLOBAL_TWEAKS_FOLDER", tweakFolder.UTF8String, 1);
        dlopen("@executable_path/Frameworks/TweakLoader.dylib", RTLD_LAZY);
    }

    int (*LiveContainerSwiftUIMain)(void) = dlsym(LiveContainerSwiftUIHandle, "main");
    return LiveContainerSwiftUIMain();

}

#ifdef DEBUG
int callAppMain(int argc, char *argv[]) {
    assert(appMain != NULL);
    __attribute__((musttail)) return appMain(argc, argv);
}
#endif
