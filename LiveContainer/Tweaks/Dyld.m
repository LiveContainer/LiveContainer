//
//  Dyld.m
//  LiveContainer
//
//  Created by s s on 2025/2/7.
//
#include <dlfcn.h>
#include <stdlib.h>
#include <stdint.h>
#include <errno.h>
#include <stdatomic.h>
#include <os/lock.h>
#include <sys/mman.h>
#include <ctype.h>
#include <ifaddrs.h>
#include <sys/socket.h>
#include <net/if.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <CFNetwork/CFNetwork.h>
#import "../../fishhook/fishhook.h"
#import "../../litehook/src/litehook.h"
#import "LCMachOUtils.h"
#include "mach_excServer.h"
#import "../utils.h"
#import "CoreLocation+GuestHooks.h"
#import "AVFoundation+GuestHooks.h"
#import <AuthenticationServices/AuthenticationServices.h>
#import <objc/runtime.h>
#import <Security/Security.h>
#import "FoundationPrivate.h"
#import <objc/message.h>
#import "../dyld_bypass_validation.h"
@import Darwin;
@import Foundation;
@import MachO;

typedef uint32_t dyld_platform_t;

typedef struct {
    dyld_platform_t platform;
    uint32_t        version;
} dyld_build_version_t;

uint32_t lcImageIndex = 0;
uint32_t appMainImageIndex = 0;
void* appExecutableHandle = 0;
bool hookedDlopen = false;
bool tweakLoaderLoaded = false;
bool appExecutableFileTypeOverwritten = false;
const char* lcMainBundlePath = NULL;

void* (*orig_dlopen)(const char *path, int mode) = dlopen;
void* (*orig_dlsym)(void * __handle, const char * __symbol) = dlsym;
uint32_t (*orig_dyld_image_count)(void) = _dyld_image_count;
const struct mach_header* (*orig_dyld_get_image_header)(uint32_t image_index) = _dyld_get_image_header;
intptr_t (*orig_dyld_get_image_vmaddr_slide)(uint32_t image_index) = _dyld_get_image_vmaddr_slide;
const char* (*orig_dyld_get_image_name)(uint32_t image_index) = _dyld_get_image_name;
// VPN Detection Bypass hooks
static CFDictionaryRef (*orig_CFNetworkCopySystemProxySettings)(void);
static CFDictionaryRef (*orig_CNCopyCurrentNetworkInfo)(CFStringRef interfaceName);
static int (*orig_getifaddrs)(struct ifaddrs **ifap);
static unsigned int (*orig_if_nametoindex)(const char *ifname);
static char *(*orig_if_indextoname)(unsigned int ifindex, char *ifname);
static struct if_nameindex *(*orig_if_nameindex)(void);
static BOOL gDidRunDyldHooksInit = NO;
static BOOL gSpoofNetworkInfoEnabled = NO;
static BOOL gSpoofWiFiAddressEnabled = NO;
static BOOL gSpoofCellularAddressEnabled = NO;
static NSString *gSpoofWiFiAddress = nil;
static NSString *gSpoofCellularAddress = nil;
static NSString *gSpoofWiFiSSID = nil;
static NSString *gSpoofWiFiBSSID = nil;
// Signal handlers
int (*orig_fcntl)(int fildes, int cmd, void *param) = 0;
int (*orig_sigaction)(int sig, const struct sigaction *restrict act, struct sigaction *restrict oact);
static int (*orig_csops)(pid_t pid, unsigned int ops, void *useraddr, size_t usersize) = NULL;
static int (*orig_csops_audittoken)(pid_t pid, unsigned int ops, void *useraddr, size_t usersize, audit_token_t *token) = NULL;
static BOOL gEnableGuestSelfCSOpsShim = NO;
// Apple Sign In
// TODO
// SSL Pinning
static IMP orig_afSecurityPolicySetSSLPinningMode = NULL;
static IMP orig_afSecurityPolicySetAllowInvalidCertificates = NULL;
static IMP orig_afSecurityPolicyPolicyWithPinningMode = NULL;
static IMP orig_afSecurityPolicyPolicyWithPinningModeWithPinnedCertificates = NULL;
static IMP orig_tskPinningValidatorEvaluateTrust = NULL;
static IMP orig_customURLConnectionDelegateIsFingerprintTrusted = NULL;
// SSL/TLS function pointers for low-level hooks
static OSStatus (*orig_SSLSetSessionOption)(SSLContextRef context, SSLSessionOption option, Boolean value) = NULL;
static SSLContextRef (*orig_SSLCreateContext)(CFAllocatorRef alloc, SSLProtocolSide protocolSide, SSLConnectionType connectionType) = NULL;
static OSStatus (*orig_SSLHandshake)(SSLContextRef context) = NULL;
// SSL Killswitch 3
static OSStatus (*orig_SecTrustEvaluate)(SecTrustRef, SecTrustResultType *);
static bool (*orig_SecTrustEvaluateWithError)(SecTrustRef, CFErrorRef *);
static OSStatus (*orig_SecTrustEvaluateAsync)(SecTrustRef, dispatch_queue_t, SecTrustCallback);
static OSStatus (*orig_SecTrustEvaluateAsyncWithError)(SecTrustRef, dispatch_queue_t, SecTrustWithErrorCallback);
static OSStatus (*orig_SecTrustEvaluateFastAsync)(SecTrustRef, dispatch_queue_t, SecTrustCallback);
// BoringSSL
static void (*orig_SSL_set_custom_verify)(void *, int, int (*)(void *, uint8_t *));
static void (*orig_SSL_CTX_set_custom_verify)(void *, int, int (*)(void *, uint8_t *));
// Bundle
static NSString *originalGuestBundleId = nil;
static NSString *liveContainerBundleId = nil;
static NSString *hostTeamIdentifier = nil;
static BOOL useSelectiveBundleIdSpoofing = NO;
static BOOL useBundleIdentityCompatibilityShims = NO;
static BOOL hideProvisioningArtifacts = NO;
static BOOL didInstallSelectiveBundleHooks = NO;
static NSString* (*orig_NSBundle_bundleIdentifier)(id self, SEL _cmd);
static NSDictionary* (*orig_NSBundle_infoDictionary)(id self, SEL _cmd);
static id (*orig_NSBundle_objectForInfoDictionaryKey)(id self, SEL _cmd, NSString *key);
static NSString* (*orig_NSBundle_pathForResource_ofType)(id self, SEL _cmd, NSString *name, NSString *ext);
static NSURL* (*orig_NSBundle_URLForResource_withExtension)(id self, SEL _cmd, NSString *name, NSString *ext);
static NSURL* (*orig_NSBundle_appStoreReceiptURL)(id self, SEL _cmd);
static BOOL (*orig_NSFileManager_fileExistsAtPath)(id self, SEL _cmd, NSString *path);
static BOOL (*orig_UIApplication_canOpenURL_guest)(id self, SEL _cmd, NSURL *url);

// LC specific variables
uint32_t guestAppSdkVersion = 0;
uint32_t guestAppSdkVersionSet = 0;
bool (*orig_dyld_program_sdk_at_least)(void* dyldPtr, dyld_build_version_t version);
uint32_t (*orig_dyld_get_program_sdk_version)(void* dyldPtr);
static bool bypassSSLPinning = false;
void CoreLocationGuestHooksInit(void);
void AVFoundationGuestHooksInit(void);

// Global variable to track Sign in with Apple context
static BOOL isSignInWithAppleActive = NO;

static void overwriteAppExecutableFileType(void) {
    struct mach_header_64* appImageMachOHeader = (struct mach_header_64*) orig_dyld_get_image_header(appMainImageIndex);
    kern_return_t kret = builtin_vm_protect(mach_task_self(), (vm_address_t)appImageMachOHeader, sizeof(appImageMachOHeader), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    if(kret != KERN_SUCCESS) {
        NSLog(@"[LC] failed to change appImageMachOHeader to rw");
    } else {
        NSLog(@"[LC] changed appImageMachOHeader to rw");
        appImageMachOHeader->filetype = MH_EXECUTE;
        builtin_vm_protect(mach_task_self(), (vm_address_t)appImageMachOHeader, sizeof(appImageMachOHeader), false,  PROT_READ);
    }
}

// MARK: ImageName Filtering
// Cache for loaded tweak names
static NSSet<NSString *> *loadedTweakNames = nil;

static void detectConfiguredTweaksEarly(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet<NSString *> *mutable = [[NSMutableSet alloc] init];

        @try {
            // Method 1: Check environment variable before TweakLoader unsets it
            const char *tweakFolderC = getenv("LC_GLOBAL_TWEAKS_FOLDER");
            if (tweakFolderC) {
                NSString *globalTweakFolder = @(tweakFolderC);
                NSArray *globalTweaks = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:globalTweakFolder error:nil];

                for (NSString *tweakName in globalTweaks) {
                    if ([tweakName hasSuffix:@".dylib"]) {
                        [mutable addObject:tweakName];
                        NSLog(@"[LC] 🕵️ Early detection - will hide global tweak: %@", tweakName);
                    }
                }
            }

            // Method 2: Use hardcoded path as fallback
            NSString *lcBundlePath = [[NSBundle mainBundle] bundlePath];
            NSString *globalTweakFolder = [lcBundlePath stringByAppendingPathComponent:@"Frameworks/TweakLoader.framework/GlobalTweaks"];

            if ([[NSFileManager defaultManager] fileExistsAtPath:globalTweakFolder]) {
                NSArray *globalTweaks = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:globalTweakFolder error:nil];

                for (NSString *tweakName in globalTweaks) {
                    if ([tweakName hasSuffix:@".dylib"]) {
                        [mutable addObject:tweakName];
                        NSLog(@"[LC] 🕵️ Early detection - will hide global tweak: %@", tweakName);
                    }
                }
            }

            // Method 3: App-specific tweaks
            NSString *tweakFolderName = NSUserDefaults.guestAppInfo[@"LCTweakFolder"];
            if (tweakFolderName.length > 0) {
                NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                NSString *tweakFolderPath = [documentsPath stringByAppendingPathComponent:tweakFolderName];

                NSArray *appTweaks = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tweakFolderPath error:nil];

                for (NSString *tweakName in appTweaks) {
                    if ([tweakName hasSuffix:@".dylib"]) {
                        [mutable addObject:tweakName];
                        NSLog(@"[LC] 🕵️ Early detection - will hide app-specific tweak: %@", tweakName);
                    }
                }
            }

            NSLog(@"[LC] 🕵️ Early detection complete - total tweaks to hide: %lu", (unsigned long)mutable.count);

        } @catch (NSException *exception) {
            NSLog(@"[LC] ❌ Error in early tweak detection: %@", exception.reason);
        }

        // Freeze as immutable set for safe reads from hook paths.
        loadedTweakNames = [mutable copy] ?: [NSSet set];
    });
}

// static bool shouldHideLibrary(const char* imageName) {
//     if (!imageName) return false;

//     // Convert to lowercase for case-insensitive comparison
//     char lowerImageName[1024];
//     strlcpy(lowerImageName, imageName, sizeof(lowerImageName));
//     for (int i = 0; lowerImageName[i]; i++) {
//         lowerImageName[i] = tolower(lowerImageName[i]);
//     }

//     // MARK: TODO: Add dynamically by enumarating injected dylibs
//     return (strstr(lowerImageName, "substrate") ||      // All substrate variants
//             strstr(lowerImageName, "tweakloader") ||    // TweakLoader
//             strstr(lowerImageName, "flex") ||           // Flex
//             strstr(lowerImageName, "frida") ||          // Frida
//             strstr(lowerImageName, "livecontainershared"));   // LiveContainerShared
// }
// Enhanced shouldHideLibrary function
static bool shouldHideLibrary(const char* imageName) {
    if (!imageName) return false;

    NSString *fileName = [@(imageName) lastPathComponent];

    // Check against pre-detected configured tweaks
    if (loadedTweakNames && [loadedTweakNames containsObject:fileName]) {
        return true;
    }

    // Convert to lowercase for hardcoded patterns
    char lowerImageName[1024];
    strlcpy(lowerImageName, imageName, sizeof(lowerImageName));
    for (int i = 0; lowerImageName[i]; i++) {
        lowerImageName[i] = tolower(lowerImageName[i]);
    }

    // Keep critical hardcoded patterns
    return (strstr(lowerImageName, "substrate") ||
            strstr(lowerImageName, "tweakloader") ||
            strstr(lowerImageName, "livecontainershared"));
}

static void ensureAppMainIndexIsSet(void) {
    if (appMainImageIndex != 0) {
        return; // Already found
    }

    // Find the guest app executable (not LiveContainer)
    int imageCount = orig_dyld_image_count();
    for(int i = 0; i < imageCount; ++i) {
        const struct mach_header* currentImageHeader = orig_dyld_get_image_header(i);
        const char* imageName = orig_dyld_get_image_name(i);

        if(currentImageHeader && currentImageHeader->filetype == MH_EXECUTE &&
           imageName && i != lcImageIndex && !strstr(imageName, "LiveContainer.app")) {

            appMainImageIndex = i;
            NSLog(@"[LC] Found guest app at index %d: %s", i, imageName);
            return;
        }
    }

    NSLog(@"[LC] ERROR: Could not find guest app executable!");
}

// Helper for LiveContainer special case handling
// static bool isLiveContainerImage(uint32_t imageIndex, const char* imageName) {
//     return imageIndex == lcImageIndex || (imageName && strstr(imageName, "LiveContainer"));
// }

// static uint32_t handleLiveContainerReplacement(uint32_t imageIndex) {
//     if (imageIndex == lcImageIndex) {
//         if (!appExecutableFileTypeOverwritten) {
//             overwriteAppExecutableFileType();
//             appExecutableFileTypeOverwritten = true;
//         }
//         return appMainImageIndex;
//     }
//     return imageIndex;
// }

// static inline int translateImageIndex(int origin) {
//     if(origin == lcImageIndex) {
//         if(!appExecutableFileTypeOverwritten) {
//             overwriteAppExecutableFileType();
//             appExecutableFileTypeOverwritten = true;
//         }

//         return appMainImageIndex;
//     }

//     // find tweakloader index
//     if(tweakLoaderLoaded && tweakLoaderIndex == 0) {
//         const char* tweakloaderPath = [[[[NSUserDefaults lcMainBundle] bundlePath] stringByAppendingPathComponent:@"Frameworks/TweakLoader.dylib"] UTF8String];
//         if(tweakloaderPath) {
//             uint32_t imageCount = orig_dyld_image_count();
//             for(uint32_t i = imageCount - 1; i >= 0; --i) {
//                 const char* imgName = orig_dyld_get_image_name(i);
//                 if(imgName && strcmp(imgName, tweakloaderPath) == 0) {
//                     tweakLoaderIndex = i;
//                     break;
//                 }
//             }
//         }

//         if(tweakLoaderIndex == 0) {
//             tweakLoaderIndex = -1; // can't find, don't search again in the future
//         }
//     }

//     if(tweakLoaderLoaded && tweakLoaderIndex > 0 && origin >= tweakLoaderIndex) {
//         return origin + 2;
//     } else if(origin >= appMainImageIndex) {
//         return origin + 1;
//     }
//     return origin;
// }

// MARK: Dyld Section

void* hook_dlsym(void * __handle, const char * __symbol) {
    // Hide jailbreak detection symbols
    if (__symbol && (
        // MobileSubstrate/Substrate
        strcmp(__symbol, "MSHookFunction") == 0 ||
        strcmp(__symbol, "MSHookMessageEx") == 0 ||
        strcmp(__symbol, "MSFindSymbol") == 0 ||
        strcmp(__symbol, "MSGetImageByName") == 0 ||
        strcmp(__symbol, "MSImageFromName") == 0 ||
        strcmp(__symbol, "MSSymbolFromName") == 0 ||
        strcmp(__symbol, "_MSHookFunction") == 0 ||

        // fishhook (since you use it!)
        strcmp(__symbol, "rebind_symbols") == 0 ||
        strcmp(__symbol, "rebind_symbols_image") == 0 ||
        strcmp(__symbol, "_rebindings_head") == 0 ||
        strcmp(__symbol, "prepend_rebindings") == 0 ||
        strcmp(__symbol, "rebind_symbols_for_image") == 0 ||
        strcmp(__symbol, "_rebind_symbols_for_image") == 0 ||
        strcmp(__symbol, "perform_rebinding_with_section") == 0 ||

        // libhooker
        strcmp(__symbol, "LHHookFunction") == 0 ||
        strcmp(__symbol, "LHHookFunctions") == 0 ||
        strcmp(__symbol, "LHFindSymbol") == 0 ||

         // Theos/Logo
        strcmp(__symbol, "_logos_method_orig") == 0 ||
        strcmp(__symbol, "_logos_method_called") == 0 ||
        strcmp(__symbol, "_logos_register_hook") == 0 ||
        strcmp(__symbol, "_logos_method_replaced") == 0 ||

        // Objective-C runtime introspection: Crashing some apps
        // strcmp(__symbol, "method_exchangeImplementations") == 0 ||
        // strcmp(__symbol, "class_getInstanceMethod") == 0 ||
        // strcmp(__symbol, "class_addMethod") == 0 ||
        // strcmp(__symbol, "method_getImplementation") == 0 ||
        // strcmp(__symbol, "method_setImplementation") == 0 ||
        // strcmp(__symbol, "class_copyMethodList") == 0 ||
        // strcmp(__symbol, "class_getMethodImplementation") == 0 ||
        // strcmp(__symbol, "method_getName") == 0 ||
        // strcmp(__symbol, "method_getTypeEncoding") == 0 ||
        // strcmp(__symbol, "object_getClass") == 0 ||
        // strcmp(__symbol, "objc_getAssociatedObject") == 0 ||
        // strcmp(__symbol, "objc_setAssociatedObject") == 0 ||

        // Litehook-specific symbols
        strcmp(__symbol, "litehook_find_dsc_symbol") == 0 ||
        strcmp(__symbol, "litehook_find_symbol") == 0 ||
        strcmp(__symbol, "litehook_hook_function") == 0 ||
        strcmp(__symbol, "litehook_unhook_function") == 0 ||
        strcmp(__symbol, "_litehook_find_dsc_symbol") == 0 ||
        strcmp(__symbol, "_litehook_find_symbol") == 0 ||

        // NOT USED - DSC iteration functions
        // strcmp(__symbol, "dyld_shared_cache_some_image_only_contains_addr") == 0 ||
        // strcmp(__symbol, "dyld_shared_cache_iterate_text") == 0 ||
        // strcmp(__symbol, "_dyld_shared_cache_contains_path") == 0 ||

        // NOT USED - Mach-O parsing (you use dlsym instead)
        // strcmp(__symbol, "getsectiondata") == 0 ||
        // strcmp(__symbol, "getsegmentdata") == 0 ||
        // strcmp(__symbol, "_dyld_get_image_slide") == 0 ||

        strcmp(__symbol, "ZzBuildHook") == 0 ||
        strcmp(__symbol, "DobbyHook") == 0 ||
        strcmp(__symbol, "pspawn_hook") == 0)) {
        return NULL;  // Hide these symbols
    }

    if(__handle == (void*)RTLD_MAIN_ONLY) {
        if(strcmp(__symbol, MH_EXECUTE_SYM) == 0) {
            if(!appExecutableFileTypeOverwritten) {
                overwriteAppExecutableFileType();
                appExecutableFileTypeOverwritten = true;
            }
            return (void*)orig_dyld_get_image_header(appMainImageIndex);
        }
        __handle = appExecutableHandle;
    } else if (__handle != (void*)RTLD_SELF && __handle != (void*)RTLD_NEXT) {
        void* ans = orig_dlsym(__handle, __symbol);
        if(!ans) {
            return 0;
        }
        for(int i = 0; i < gRebindCount; i++) {
            global_rebind rebind = gRebinds[i];
            if(ans == rebind.replacee) {
                return rebind.replacement;
            }
        }
        return ans;
    }

    __attribute__((musttail)) return orig_dlsym(__handle, __symbol);
}

// uint32_t hook_dyld_image_count(void) {
//     return orig_dyld_image_count() - 1 - (uint32_t)tweakLoaderLoaded;
// }
uint32_t hook_dyld_image_count(void) {
    uint32_t count = orig_dyld_image_count();

    // Count visible (non-hidden) images INCLUDING LiveContainer (which will be replaced)
    uint32_t visibleCount = 0;
    for(uint32_t i = 0; i < count; i++) {
        const char* imageName = orig_dyld_get_image_name(i);
        if(!shouldHideLibrary(imageName)) {
            visibleCount++;
        }
    }

    return visibleCount;
}

// const struct mach_header* hook_dyld_get_image_header(uint32_t image_index) {
//     __attribute__((musttail)) return orig_dyld_get_image_header(translateImageIndex(image_index));
// }
const struct mach_header* hook_dyld_get_image_header(uint32_t image_index) {
    // ALWAYS handle LiveContainer replacement first (at virtual index level)
    if(image_index == lcImageIndex) {
        ensureAppMainIndexIsSet();
        if(!appExecutableFileTypeOverwritten) {
            overwriteAppExecutableFileType();
            appExecutableFileTypeOverwritten = true;
        }
        return orig_dyld_get_image_header(appMainImageIndex);
    }

    // Before we're ready to hide libraries, use simple passthrough
    if(!appExecutableFileTypeOverwritten) {
        return orig_dyld_get_image_header(image_index);
    }

    // After we're ready, use the hiding logic
    uint32_t realCount = orig_dyld_image_count();
    uint32_t visibleIndex = 0;

    for(uint32_t i = 0; i < realCount; i++) {
        const char* imageName = orig_dyld_get_image_name(i);

        if(shouldHideLibrary(imageName)) {
            continue;
        }

        if(visibleIndex == image_index) {
            return orig_dyld_get_image_header(i);
        }

        visibleIndex++;
    }

    return NULL;
}

// intptr_t hook_dyld_get_image_vmaddr_slide(uint32_t image_index) {
//     __attribute__((musttail)) return orig_dyld_get_image_vmaddr_slide(translateImageIndex(image_index));
// }
intptr_t hook_dyld_get_image_vmaddr_slide(uint32_t image_index) {
    // ALWAYS handle LiveContainer replacement first (at virtual index level)
    if(image_index == lcImageIndex) {
        if(!appExecutableFileTypeOverwritten) {
            overwriteAppExecutableFileType();
            appExecutableFileTypeOverwritten = true;
        }
        return orig_dyld_get_image_vmaddr_slide(appMainImageIndex);
    }

    // Before we're ready to hide libraries, use simple passthrough
    if(!appExecutableFileTypeOverwritten) {
        return orig_dyld_get_image_vmaddr_slide(image_index);
    }

    // After we're ready, use the hiding logic
    uint32_t realCount = orig_dyld_image_count();
    uint32_t visibleIndex = 0;

    for(uint32_t i = 0; i < realCount; i++) {
        const char* imageName = orig_dyld_get_image_name(i);

        if(shouldHideLibrary(imageName)) {
            continue;
        }

        if(visibleIndex == image_index) {
            return orig_dyld_get_image_vmaddr_slide(i);
        }

        visibleIndex++;
    }

    return 0;
}

// const char* hook_dyld_get_image_name(uint32_t image_index) {
//     __attribute__((musttail)) return orig_dyld_get_image_name(translateImageIndex(image_index));
// }
const char* hook_dyld_get_image_name(uint32_t image_index) {
    // ALWAYS handle LiveContainer replacement first (at virtual index level)
    if(image_index == lcImageIndex) {
        ensureAppMainIndexIsSet();
        if(!appExecutableFileTypeOverwritten) {
            overwriteAppExecutableFileType();
            appExecutableFileTypeOverwritten = true;
        }
        return orig_dyld_get_image_name(appMainImageIndex);
    }

    // Before we're ready to hide libraries, use simple passthrough
    if(!appExecutableFileTypeOverwritten) {
        return orig_dyld_get_image_name(image_index);
    }

    // Use EXACT SAME logic as hook_dyld_image_count
    uint32_t realCount = orig_dyld_image_count();
    uint32_t visibleIndex = 0;

    for(uint32_t i = 0; i < realCount; i++) {
        const char* imageName = orig_dyld_get_image_name(i);

        if(shouldHideLibrary(imageName)) {
            continue;
        }

        if(visibleIndex == image_index) {
            return imageName;
        }

        visibleIndex++;
    }

    return NULL;
}

void hideLiveContainerImageCallback(const struct mach_header* header, intptr_t vmaddr_slide) {
    Dl_info info;
    dladdr(header, &info);
    if(!strncmp(info.dli_fname, lcMainBundlePath, strlen(lcMainBundlePath)) || strstr(info.dli_fname, "/procursus/") != 0) {
        char fakePath[PATH_MAX];
        snprintf(fakePath, sizeof(fakePath), "/usr/lib/%p.dylib", header);
        kern_return_t ret = vm_protect(mach_task_self(), (vm_address_t)info.dli_fname, PATH_MAX, false, PROT_READ | PROT_WRITE);
        if(ret != KERN_SUCCESS) {
            os_thread_self_restrict_tpro_to_rw();
        }
        strcpy((char *)info.dli_fname, fakePath);
        if(ret != KERN_SUCCESS) {
            os_thread_self_restrict_tpro_to_ro();
        }
    }
}

void* getDSCAddr(void) {
    task_dyld_info_data_t dyldInfo;

    uint32_t count = TASK_DYLD_INFO_COUNT;
    task_info(mach_task_self_, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &count);
    struct dyld_all_image_infos *infos = (struct dyld_all_image_infos *)dyldInfo.all_image_info_addr;
    return (void*)infos->sharedCacheBaseAddress;
}

void* getCachedSymbol(NSString* symbolName, mach_header_u* header) {
    NSDictionary* symbolOffsetDict = [NSUserDefaults.lcSharedDefaults objectForKey:@"symbolOffsetCache"][symbolName];
    if(!symbolOffsetDict) {
        return NULL;
    }
    NSData* cachedSymbolUUID = symbolOffsetDict[@"uuid"];
    if(!cachedSymbolUUID) {
        return NULL;
    }
    const uint8_t* uuid = LCGetMachOUUID(header);
    if(!uuid || memcmp(uuid, [cachedSymbolUUID bytes], 16)) {
        return NULL;
    }

    return (void*)header + [symbolOffsetDict[@"offset"] unsignedLongLongValue];
}

void saveCachedSymbol(NSString* symbolName, mach_header_u* header, uint64_t offset) {
    NSMutableDictionary* allSymbolOffsetDict = [[NSUserDefaults.lcSharedDefaults objectForKey:@"symbolOffsetCache"] mutableCopy];
    if(!allSymbolOffsetDict) {
        allSymbolOffsetDict = [[NSMutableDictionary alloc] init];
    }

    allSymbolOffsetDict[symbolName] = @{
        @"uuid": [NSData dataWithBytes:LCGetMachOUUID(header) length:16],
        @"offset": @(offset),
    };
    [NSUserDefaults.lcSharedDefaults setObject:allSymbolOffsetDict forKey:@"symbolOffsetCache"];
}

bool hook_dyld_program_sdk_at_least(void* dyldApiInstancePtr, dyld_build_version_t version) {
    // we are targeting ios, so we hard code 2
    if(version.platform == 0xffffffff){
        return version.version <= guestAppSdkVersionSet;
    } else if (version.platform == 2){
        return version.version <= guestAppSdkVersion;
    } else {
        return false;
    }
}

uint32_t hook_dyld_get_program_sdk_version(void* dyldApiInstancePtr) {
    return guestAppSdkVersion;
}

bool performHookDyldApi(const char* functionName, uint32_t adrpOffset, void** origFunction, void* hookFunction) {

    uint32_t* baseAddr = dlsym(RTLD_DEFAULT, functionName);
    assert(baseAddr != 0);
    /*
     arm64e 26.4b1+ has extra 20 instructions between adrpOffset and adrp
     arm64e
     1ad450b90  e10300aa   mov     x1, x0
     1ad450b94  487b2090   adrp    x8, dyld4::gAPIs
     1ad450b98  000140f9   ldr     x0, [x8]  {dyld4::gAPIs} may contain offset
     1ad450b9c  100040f9   ldr     x16, [x0]
     1ad450ba0  f10300aa   mov     x17, x0
     1ad450ba4  517fecf2   movk    x17, #0x63fa, lsl #0x30
     1ad450ba8  301ac1da   autda   x16, x17
     1ad450bac  114780d2   mov     x17, #0x238
     1ad450bb0  1002118b   add     x16, x16, x17
     1ad450bb4  020240f9   ldr     x2, [x16]
     1ad450bb8  e30310aa   mov     x3, x16
     1ad450bbc  f00303aa   mov     x16, x3
     1ad450bc0  7085f3f2   movk    x16, #0x9c2b, lsl #0x30
     1ad450bc4  50081fd7   braa    x2, x16

     arm64
     00000001ac934c80         mov        x1, x0
     00000001ac934c84         adrp       x8, #0x1f462d000
     00000001ac934c88         ldr        x0, [x8, #0xf88]                            ; __ZN5dyld45gDyldE
     00000001ac934c8c         ldr        x8, [x0]
     00000001ac934c90         ldr        x2, [x8, #0x258]
     00000001ac934c94         br         x2
     */
    uint32_t* adrpInstPtr = baseAddr + adrpOffset;
    if ((*adrpInstPtr & 0x9f000000) != 0x90000000) {
        adrpOffset += 20;
        adrpInstPtr = baseAddr + adrpOffset;
    }
    assert ((*adrpInstPtr & 0x9f000000) == 0x90000000);
    void* gdyldPtr = (void*)aarch64_emulate_adrp_ldr(*adrpInstPtr, *(baseAddr + adrpOffset + 1), (uint64_t)(baseAddr + adrpOffset));
    
    assert(gdyldPtr != 0);
    assert(*(void**)gdyldPtr != 0);
    void* vtablePtr = **(void***)gdyldPtr;

    void* vtableFunctionPtr = 0;
    uint32_t* movInstPtr = baseAddr + adrpOffset + 6;

    if((*movInstPtr & 0x7F800000) == 0x52800000) {
        // arm64e, mov imm + add + ldr
        uint32_t imm16 = (*movInstPtr & 0x1FFFE0) >> 5;
        vtableFunctionPtr = vtablePtr + imm16;
    } else if ((*movInstPtr & 0xFFE00C00) == 0xF8400C00) {
        // arm64e, ldr immediate Pre-index 64bit
        uint32_t imm9 = (*movInstPtr & 0x1FF000) >> 12;
        vtableFunctionPtr = vtablePtr + imm9;
    } else {
        // arm64
        uint32_t* ldrInstPtr2 = baseAddr + adrpOffset + 3;
        assert((*ldrInstPtr2 & 0xBFC00000) == 0xB9400000);
        uint32_t size2 = (*ldrInstPtr2 & 0xC0000000) >> 30;
        uint32_t imm12_2 = (*ldrInstPtr2 & 0x3FFC00) >> 10;
        vtableFunctionPtr = vtablePtr + (imm12_2 << size2);
    }


    kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)vtableFunctionPtr, sizeof(uintptr_t), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    assert(ret == KERN_SUCCESS);
    *origFunction = (void*)*(void**)vtableFunctionPtr;
    *(uint64_t*)vtableFunctionPtr = (uint64_t)hookFunction;
    builtin_vm_protect(mach_task_self(), (mach_vm_address_t)vtableFunctionPtr, sizeof(uintptr_t), false, PROT_READ);
    return true;
}

bool initGuestSDKVersionInfo(void) {
    void* dyldBase = getDyldBase();
    // it seems Apple is constantly changing findVersionSetEquivalent's signature so we directly search sVersionMap instead
    uint32_t* versionMapPtr = getCachedSymbol(@"__ZN5dyld3L11sVersionMapE", dyldBase);
    if(!versionMapPtr) {
#if !TARGET_OS_SIMULATOR
        const char* dyldPath = "/usr/lib/dyld";
        uint64_t offset = LCFindSymbolOffset(dyldPath, "__ZN5dyld3L11sVersionMapE");
#else
        void *result = litehook_find_symbol(dyldBase, "__ZN5dyld3L11sVersionMapE");
        uint64_t offset = (uint64_t)result - (uint64_t)dyldBase;
#endif
        versionMapPtr = dyldBase + offset;
        saveCachedSymbol(@"__ZN5dyld3L11sVersionMapE", dyldBase, offset);
    }

    assert(versionMapPtr);
    // however sVersionMap's struct size is also unknown, but we can figure it out
    // we assume the size is 10K so we won't need to change this line until maybe iOS 40
    uint32_t* versionMapEnd = versionMapPtr + 2560;
    // ensure the first is versionSet and the third is iOS version (5.0.0)
    assert(versionMapPtr[0] == 0x07db0901 && versionMapPtr[2] == 0x00050000);
    // get struct size. we assume size is smaller then 128. appearently Apple won't have so many platforms
    uint32_t size = 0;
    for(int i = 1; i < 128; ++i) {
        // find the next versionSet (for 6.0.0)
        if(versionMapPtr[i] == 0x07dc0901) {
            size = i;
            break;
        }
    }
    assert(size);

    NSOperatingSystemVersion currentVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    uint32_t maxVersion = ((uint32_t)currentVersion.majorVersion << 16) | ((uint32_t)currentVersion.minorVersion << 8);

    uint32_t candidateVersion = 0;
    uint32_t candidateVersionEquivalent = 0;
    uint32_t newVersionSetVersion = 0;
    for(uint32_t* nowVersionMapItem = versionMapPtr; nowVersionMapItem < versionMapEnd; nowVersionMapItem += size) {
        newVersionSetVersion = nowVersionMapItem[2];
        if (newVersionSetVersion > guestAppSdkVersion) { break; }
        candidateVersion = newVersionSetVersion;
        candidateVersionEquivalent = nowVersionMapItem[0];
        if(newVersionSetVersion >= maxVersion) { break; }
    }

    if (newVersionSetVersion == 0xffffffff && candidateVersion == 0) {
        candidateVersionEquivalent = newVersionSetVersion;
    }

    guestAppSdkVersionSet = candidateVersionEquivalent;

    return true;
}

#if TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR
void DyldHookLoadableIntoProcess(void) {
    uint32_t *patchAddr = (uint32_t *)litehook_find_symbol(getDyldBase(), "__ZNK6mach_o6Header19loadableIntoProcessENS_8PlatformE7CStringb");
    size_t patchSize = sizeof(uint32_t[2]);

    kern_return_t kret;
    kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, patchSize, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    assert(kret == KERN_SUCCESS);

    patchAddr[0] = 0xD2800020; // mov x0, #1
    patchAddr[1] = 0xD65F03C0; // ret

    kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, patchSize, false, PROT_READ | PROT_EXEC);
    assert(kret == KERN_SUCCESS);
}
#endif

// MARK: VPN Section

static BOOL shouldFilterVPNInterfaceNameCStr(const char *name) {
    if (!name || name[0] == '\0') {
        return NO;
    }

    // utun interfaces are a high-signal VPN/proxy indicator.
    if (strncmp(name, "utun", 4) == 0) {
        return YES;
    }

    return (strncmp(name, "tap", 3) == 0 ||
            strncmp(name, "tun", 3) == 0 ||
            strncmp(name, "ppp", 3) == 0 ||
            strncmp(name, "bridge", 6) == 0 ||
            strncmp(name, "ipsec", 5) == 0 ||
            strncmp(name, "vtun", 4) == 0 ||
            strncmp(name, "l2tp", 4) == 0 ||
            strncmp(name, "ne", 2) == 0 ||
            strncmp(name, "gif", 3) == 0 ||
            strncmp(name, "stf", 3) == 0 ||
            strncmp(name, "wg", 2) == 0 ||
            strncmp(name, "pptp", 4) == 0);
}

static void lc_overwriteInterfaceName(char *name, size_t buflen) {
    if (!name || buflen == 0) {
        return;
    }
    strlcpy(name, "en0", buflen);
}

static uint32_t lc_findSafeInterfaceIndex(void) {
    uint32_t index = if_nametoindex("en0");
    if (index != 0) {
        return index;
    }

    index = if_nametoindex("pdp_ip0");
    if (index != 0) {
        return index;
    }

    struct if_nameindex *interfaces = if_nameindex();
    if (!interfaces) {
        return 0;
    }

    uint32_t fallback = 0;
    for (struct if_nameindex *entry = interfaces;
         entry->if_index != 0 && entry->if_name != NULL;
         entry++) {
        if (!shouldFilterVPNInterfaceNameCStr(entry->if_name)) {
            fallback = entry->if_index;
            break;
        }
    }

    if_freenameindex(interfaces);
    return fallback;
}

static BOOL lc_shouldSpoofNetworkInfoForInterface(CFStringRef interfaceName) {
    if (!interfaceName) {
        return YES;
    }
    if (CFGetTypeID(interfaceName) != CFStringGetTypeID()) {
        return YES;
    }
    if (CFStringCompare(interfaceName, CFSTR("en0"), 0) == kCFCompareEqualTo) {
        return YES;
    }
    return CFStringCompare(interfaceName, CFSTR("awdl0"), 0) == kCFCompareEqualTo;
}

static CFDictionaryRef lc_buildSpoofedNetworkInfoDictionary(void) {
    NSString *ssid = gSpoofWiFiSSID.length > 0 ? gSpoofWiFiSSID : @"Public Network";
    NSString *bssid = gSpoofWiFiBSSID.length > 0 ? gSpoofWiFiBSSID : @"22:66:99:00:11:22";
    NSData *ssidData = [ssid dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];

    NSDictionary *info = @{
        @"SSID": ssid,
        @"BSSID": bssid,
        @"SSIDDATA": ssidData,
    };
    return CFBridgingRetain(info);
}

static CFDictionaryRef hook_CNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    if (gSpoofNetworkInfoEnabled && lc_shouldSpoofNetworkInfoForInterface(interfaceName)) {
        return lc_buildSpoofedNetworkInfoDictionary();
    }

    if (orig_CNCopyCurrentNetworkInfo) {
        return orig_CNCopyCurrentNetworkInfo(interfaceName);
    }
    return NULL;
}

static void lc_applyAddressSpoofToIfaddrsNode(struct ifaddrs *node) {
    if (!node || !node->ifa_name || !node->ifa_addr || node->ifa_addr->sa_family != AF_INET) {
        return;
    }

    struct sockaddr_in *inAddr = (struct sockaddr_in *)node->ifa_addr;
    if (!inAddr) {
        return;
    }

    const char *name = node->ifa_name;
    if (gSpoofWiFiAddressEnabled && gSpoofWiFiAddress.length > 0 && strcmp(name, "en0") == 0) {
        inAddr->sin_addr.s_addr = inet_addr(gSpoofWiFiAddress.UTF8String);
        return;
    }

    if (gSpoofCellularAddressEnabled && gSpoofCellularAddress.length > 0 &&
        (strcmp(name, "pdp_ip0") == 0 || strcmp(name, "en1") == 0)) {
        inAddr->sin_addr.s_addr = inet_addr(gSpoofCellularAddress.UTF8String);
    }
}

static BOOL lc_isValidIPv4Address(NSString *candidate) {
    if (candidate.length == 0) return NO;
    struct in_addr tmp = {0};
    return inet_pton(AF_INET, candidate.UTF8String, &tmp) == 1;
}

static BOOL lc_guestBool(NSDictionary *guestAppInfo, NSString *primaryKey, NSString *legacyKey) {
    id primary = primaryKey ? guestAppInfo[primaryKey] : nil;
    if (primary != nil) return [primary boolValue];
    id legacy = legacyKey ? guestAppInfo[legacyKey] : nil;
    return legacy != nil ? [legacy boolValue] : NO;
}

static NSString *lc_guestString(NSDictionary *guestAppInfo, NSString *primaryKey, NSString *legacyKey) {
    id primary = primaryKey ? guestAppInfo[primaryKey] : nil;
    if ([primary isKindOfClass:[NSString class]] && [(NSString *)primary length] > 0) {
        return primary;
    }
    id legacy = legacyKey ? guestAppInfo[legacyKey] : nil;
    if ([legacy isKindOfClass:[NSString class]] && [(NSString *)legacy length] > 0) {
        return legacy;
    }
    return nil;
}

static void lc_configureNetworkSpoofing(NSDictionary *guestAppInfo) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *info = [guestAppInfo isKindOfClass:[NSDictionary class]] ? guestAppInfo : @{};

        gSpoofNetworkInfoEnabled = lc_guestBool(info, @"deviceSpoofNetworkInfo", @"enableSpoofNetworkInfo");
        gSpoofWiFiAddressEnabled = lc_guestBool(info, @"deviceSpoofWiFiAddressEnabled", @"enableSpoofWiFi");
        gSpoofCellularAddressEnabled = lc_guestBool(info, @"deviceSpoofCellularAddressEnabled", @"enableSpoofCellular");

        gSpoofWiFiAddress = [lc_guestString(info, @"deviceSpoofWiFiAddress", @"wifiAddress") copy];
        gSpoofCellularAddress = [lc_guestString(info, @"deviceSpoofCellularAddress", @"cellularAddress") copy];
        gSpoofWiFiSSID = [lc_guestString(info, @"deviceSpoofWiFiSSID", @"wifiSSID") copy];
        gSpoofWiFiBSSID = [lc_guestString(info, @"deviceSpoofWiFiBSSID", @"wifiBSSID") copy];

        if (info[@"spoofNetwork"] != nil && [info[@"spoofNetwork"] boolValue]) {
            gSpoofNetworkInfoEnabled = YES;
        }

        if (!lc_isValidIPv4Address(gSpoofWiFiAddress)) {
            gSpoofWiFiAddress = nil;
            gSpoofWiFiAddressEnabled = NO;
        } else if (!gSpoofWiFiAddressEnabled) {
            gSpoofWiFiAddressEnabled = YES;
        }

        if (!lc_isValidIPv4Address(gSpoofCellularAddress)) {
            gSpoofCellularAddress = nil;
            gSpoofCellularAddressEnabled = NO;
        } else if (!gSpoofCellularAddressEnabled) {
            gSpoofCellularAddressEnabled = YES;
        }
    });
}

static CFDictionaryRef hook_CFNetworkCopySystemProxySettings(void) {
    // Return completely empty dictionary - exactly like cellular connection
    NSDictionary *emptySettings = @{};

    return CFBridgingRetain(emptySettings);
}

static int hook_getifaddrs(struct ifaddrs **ifap) {
    if (!orig_getifaddrs) {
        return -1;
    }

    int result = orig_getifaddrs(ifap);
    if (result != 0 || !ifap || !*ifap) {
        return result;
    }

    // NOTE: Do NOT unlink/free nodes from the getifaddrs() list.
    // Apple's getifaddrs/freeifaddrs implementation may share allocations between nodes
    // (e.g., ifa_name pointers), so freeing a subset can corrupt the remaining list and crash.
    // Instead, sanitize VPN-marking interface names in-place so callers don't see high-signal names
    // like "utunX".
    for (struct ifaddrs *node = *ifap; node != NULL; node = node->ifa_next) {
        if (!node->ifa_name) {
            continue;
        }
        if (!shouldFilterVPNInterfaceNameCStr(node->ifa_name)) {
            continue;
        }

        // NSLog(@"[LC] 🎭 getifaddrs - filtering VPN interface: %s", node->ifa_name);
        lc_overwriteInterfaceName(node->ifa_name, IFNAMSIZ);
    }

    if ((gSpoofWiFiAddressEnabled && gSpoofWiFiAddress.length > 0) ||
        (gSpoofCellularAddressEnabled && gSpoofCellularAddress.length > 0)) {
        for (struct ifaddrs *node = *ifap; node != NULL; node = node->ifa_next) {
            lc_applyAddressSpoofToIfaddrsNode(node);
        }
    }

    return result;
}

static char *hook_if_indextoname(unsigned int ifindex, char *ifname) {
    if (!orig_if_indextoname) {
        errno = ENOSYS;
        return NULL;
    }

    char *result = orig_if_indextoname(ifindex, ifname);
    if (result && ifname && shouldFilterVPNInterfaceNameCStr(ifname)) {
        static BOOL loggedHookHit = NO;
        if (!loggedHookHit) {
            loggedHookHit = YES;
            NSLog(@"[LC] ✅ hook hit: if_indextoname");
        }

        NSLog(@"[LC] 🎭 if_indextoname - filtering VPN interface index %u (%s)",
              ifindex,
              ifname);
        lc_overwriteInterfaceName(ifname, IFNAMSIZ);
    }

    return result;
}

static struct if_nameindex *hook_if_nameindex(void) {
    if (!orig_if_nameindex) {
        return NULL;
    }

    struct if_nameindex *list = orig_if_nameindex();
    if (!list) {
        return NULL;
    }

    static BOOL loggedHookHit = NO;
    static BOOL loggedCompaction = NO;
    struct if_nameindex *readPtr = list;
    struct if_nameindex *writePtr = list;
    unsigned int removedCount = 0;

    while (readPtr->if_index != 0 && readPtr->if_name != NULL) {
        if (shouldFilterVPNInterfaceNameCStr(readPtr->if_name)) {
            if (!loggedHookHit) {
                loggedHookHit = YES;
                NSLog(@"[LC] ✅ hook hit: if_nameindex");
            }

            NSLog(@"[LC] 🎭 if_nameindex - removing VPN interface index %u (%s)",
                  readPtr->if_index,
                  readPtr->if_name);
            removedCount++;
            readPtr++;
            continue;
        }

        if (writePtr != readPtr) {
            *writePtr = *readPtr;
        }
        writePtr++;
        readPtr++;
    }

    // Terminate at compacted length so callers observe fewer interfaces.
    writePtr->if_index = 0;
    writePtr->if_name = NULL;

    if (removedCount > 0 && !loggedCompaction) {
        loggedCompaction = YES;
        NSLog(@"[LC] 🎭 if_nameindex - compacted interface list, removed %u VPN entries", removedCount);
    }

    return list;
}

static unsigned int hook_if_nametoindex(const char *ifname) {
    if (!orig_if_nametoindex) {
        errno = ENOSYS;
        return 0;
    }

    if (!ifname || !shouldFilterVPNInterfaceNameCStr(ifname)) {
        return orig_if_nametoindex(ifname);
    }

    static BOOL loggedHookHit = NO;
    if (!loggedHookHit) {
        loggedHookHit = YES;
        NSLog(@"[LC] ✅ hook hit: if_nametoindex");
    }

    uint32_t safeIndex = lc_findSafeInterfaceIndex();
    if (safeIndex != 0) {
        NSLog(@"[LC] 🎭 if_nametoindex - remapping VPN interface lookup: %s -> ifindex %u",
              ifname,
              safeIndex);
        errno = 0;
        return safeIndex;
    }

    NSLog(@"[LC] 🎭 if_nametoindex - hiding VPN interface lookup: %s", ifname);
    errno = ENXIO;
    return 0;
}

// MARK: Security / Code-Signing Hooks

static inline BOOL lc_shouldRewriteSelfCSFlags(pid_t pid, unsigned int ops, void *useraddr, size_t usersize) {
    if (!gEnableGuestSelfCSOpsShim) return NO;
    if (ops != CS_OPS_STATUS) return NO;
    if (!useraddr || usersize < sizeof(uint32_t)) return NO;
    return (pid == getpid());
}

static inline void lc_rewriteSelfCSFlagsInPlace(void *useraddr) {
    uint32_t *flags = (uint32_t *)useraddr;
    uint32_t originalFlags = *flags;
    uint32_t rewrittenFlags = (originalFlags & ~((uint32_t)CS_GET_TASK_ALLOW)) | ((uint32_t)CS_INSTALLER);
    *flags = rewrittenFlags;

    static BOOL loggedRewrite = NO;
    if (!loggedRewrite && originalFlags != rewrittenFlags) {
        loggedRewrite = YES;
        NSLog(@"[LC] 🎭 csops shim active for self: 0x%08X -> 0x%08X", originalFlags, rewrittenFlags);
    }
}

static int hook_csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize) {
    int rv = -1;
    if (orig_csops) {
        rv = orig_csops(pid, ops, useraddr, usersize);
    } else {
        errno = ENOSYS;
        return -1;
    }

    if (rv == 0 && lc_shouldRewriteSelfCSFlags(pid, ops, useraddr, usersize)) {
        lc_rewriteSelfCSFlagsInPlace(useraddr);
    }
    return rv;
}

static int hook_csops_audittoken(pid_t pid, unsigned int ops, void *useraddr, size_t usersize, audit_token_t *token) {
    int rv = -1;
    if (orig_csops_audittoken) {
        rv = orig_csops_audittoken(pid, ops, useraddr, usersize, token);
    } else {
        errno = ENOSYS;
        return -1;
    }

    if (rv == 0 && lc_shouldRewriteSelfCSFlags(pid, ops, useraddr, usersize)) {
        lc_rewriteSelfCSFlagsInPlace(useraddr);
    }
    return rv;
}

// MARK: SSL Pinning
// TODO: Fix detection in Alamofire (Alamofire Error Server Trust Failure)
// TODO: Add SSL-killswitch 3
// TODO: Add BoringSSL hooks
// TODO: Add Flutter/Dart Hooks

static void hook_afSecurityPolicySetSSLPinningMode(id self, SEL _cmd, NSUInteger mode) {
    NSLog(@"[LC] 🔓 AFNetworking: setSSLPinningMode called with mode %lu, forcing to 0 (None)", (unsigned long)mode);

    // Call original with mode 0 (AFSSLPinningModeNone)
    void (*original)(id, SEL, NSUInteger) = (void (*)(id, SEL, NSUInteger))orig_afSecurityPolicySetSSLPinningMode;
    original(self, _cmd, 0);
}

static void hook_afSecurityPolicySetAllowInvalidCertificates(id self, SEL _cmd, BOOL allow) {
    NSLog(@"[LC] 🔓 AFNetworking: setAllowInvalidCertificates called with %d, forcing to YES", allow);

    // Call original with YES
    void (*original)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))orig_afSecurityPolicySetAllowInvalidCertificates;
    original(self, _cmd, YES);
}

static id hook_afSecurityPolicyPolicyWithPinningMode(id self, SEL _cmd, NSUInteger mode) {
    NSLog(@"[LC] 🔓 AFNetworking: policyWithPinningMode called with mode %lu, forcing to 0 (None)", (unsigned long)mode);

    // Call original with mode 0 (AFSSLPinningModeNone)
    id (*original)(id, SEL, NSUInteger) = (id (*)(id, SEL, NSUInteger))orig_afSecurityPolicyPolicyWithPinningMode;
    return original(self, _cmd, 0);
}

static id hook_afSecurityPolicyPolicyWithPinningModeWithPinnedCertificates(id self, SEL _cmd, NSUInteger mode, NSSet *pinnedCertificates) {
    NSLog(@"[LC] 🔓 AFNetworking: policyWithPinningMode:withPinnedCertificates called with mode %lu, forcing to 0 (None)", (unsigned long)mode);

    // Call original with mode 0 (AFSSLPinningModeNone)
    id (*original)(id, SEL, NSUInteger, NSSet *) = (id (*)(id, SEL, NSUInteger, NSSet *))orig_afSecurityPolicyPolicyWithPinningModeWithPinnedCertificates;
    return original(self, _cmd, 0, pinnedCertificates);
}

// MARK: TrustKit Bypass

static BOOL hook_tskPinningValidatorEvaluateTrust(id self, SEL _cmd, SecTrustRef trust, NSString *hostname) {
    NSLog(@"[LC] 🔓 TrustKit: evaluateTrust:forHostname called for %@, returning YES", hostname);

    // Always return YES (trust is valid)
    return YES;
}

// MARK: Cordova SSL Certificate Checker Bypass

static BOOL hook_customURLConnectionDelegateIsFingerprintTrusted(id self, SEL _cmd, NSString *fingerprint) {
    NSLog(@"[LC] 🔓 Cordova SSLCertificateChecker: isFingerprintTrusted called, returning YES");

    // Always return YES (fingerprint is trusted)
    return YES;
}

// MARK: NSURLSession Challenge Bypass

static void hook_urlSessionDidReceiveChallenge(id self, SEL _cmd, NSURLSession *session, NSURLAuthenticationChallenge *challenge, void (^completionHandler)(NSURLSessionAuthChallengeDisposition, NSURLCredential *)) {
    NSLog(@"[LC] 🔓 NSURLSession: URLSession:didReceiveChallenge:completionHandler bypassing certificate validation");

    // Create credential for the server trust and use it
    NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
    [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];

    // Call completion handler with success
    completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
}

// MARK: Low-Level SSL/TLS Hooks

static OSStatus hook_SSLSetSessionOption(SSLContextRef context, SSLSessionOption option, Boolean value) {
    // kSSLSessionOptionBreakOnServerAuth = 0
    if (option == 0) {
        NSLog(@"[LC] 🔓 SSL: SSLSetSessionOption called with kSSLSessionOptionBreakOnServerAuth, blocking");
        return noErr; // Don't allow modification of this option
    }

    return orig_SSLSetSessionOption(context, option, value);
}

static SSLContextRef hook_SSLCreateContext(CFAllocatorRef alloc, SSLProtocolSide protocolSide, SSLConnectionType connectionType) {
    SSLContextRef context = orig_SSLCreateContext(alloc, protocolSide, connectionType);

    if (context && orig_SSLSetSessionOption) {
        // Immediately set kSSLSessionOptionBreakOnServerAuth to disable cert validation
        orig_SSLSetSessionOption(context, 0, true); // kSSLSessionOptionBreakOnServerAuth = 0
        NSLog(@"[LC] 🔓 SSL: SSLCreateContext called, disabled certificate validation");
    }

    return context;
}

static OSStatus hook_SSLHandshake(SSLContextRef context) {
    OSStatus result = orig_SSLHandshake(context);

    // errSSLServerAuthCompared = -9481
    if (result == -9481) {
        NSLog(@"[LC] 🔓 SSL: SSLHandshake got errSSLServerAuthCompared, calling again to bypass");
        return orig_SSLHandshake(context);
    }

    return result;
}

// MARK: SSL Pinning Bypass Setup

static void setupAFNetworkingHooks(void) {
    Class afSecurityPolicy = NSClassFromString(@"AFSecurityPolicy");
    if (!afSecurityPolicy) {
        return;
    }

    NSLog(@"[LC] 🔓 Found AFNetworking, hooking SSL pinning methods");

    // Hook instance methods using direct method replacement
    Method setSSLPinningModeMethod = class_getInstanceMethod(afSecurityPolicy, @selector(setSSLPinningMode:));
    if (setSSLPinningModeMethod) {
        orig_afSecurityPolicySetSSLPinningMode = method_getImplementation(setSSLPinningModeMethod);
        method_setImplementation(setSSLPinningModeMethod, (IMP)hook_afSecurityPolicySetSSLPinningMode);
    }

    Method setAllowInvalidCertificatesMethod = class_getInstanceMethod(afSecurityPolicy, @selector(setAllowInvalidCertificates:));
    if (setAllowInvalidCertificatesMethod) {
        orig_afSecurityPolicySetAllowInvalidCertificates = method_getImplementation(setAllowInvalidCertificatesMethod);
        method_setImplementation(setAllowInvalidCertificatesMethod, (IMP)hook_afSecurityPolicySetAllowInvalidCertificates);
    }

    // Hook class methods - keep as is since they work
    Method policyMethod = class_getClassMethod(afSecurityPolicy, @selector(policyWithPinningMode:));
    if (policyMethod) {
        orig_afSecurityPolicyPolicyWithPinningMode = method_getImplementation(policyMethod);
        method_setImplementation(policyMethod, (IMP)hook_afSecurityPolicyPolicyWithPinningMode);
    }

    Method policyWithCertsMethod = class_getClassMethod(afSecurityPolicy, @selector(policyWithPinningMode:withPinnedCertificates:));
    if (policyWithCertsMethod) {
        orig_afSecurityPolicyPolicyWithPinningModeWithPinnedCertificates = method_getImplementation(policyWithCertsMethod);
        method_setImplementation(policyWithCertsMethod, (IMP)hook_afSecurityPolicyPolicyWithPinningModeWithPinnedCertificates);
    }
}

static void setupTrustKitHooks(void) {
    Class tskPinningValidator = NSClassFromString(@"TSKPinningValidator");
    if (!tskPinningValidator) {
        return;
    }

    NSLog(@"[LC] 🔓 Found TrustKit, hooking pinning validation");

    Method evaluateTrustMethod = class_getInstanceMethod(tskPinningValidator, @selector(evaluateTrust:forHostname:));
    if (evaluateTrustMethod) {
        orig_tskPinningValidatorEvaluateTrust = method_getImplementation(evaluateTrustMethod);
        method_setImplementation(evaluateTrustMethod, (IMP)hook_tskPinningValidatorEvaluateTrust);
    }
}

static void setupCordovaHooks(void) {
    Class customURLConnectionDelegate = NSClassFromString(@"CustomURLConnectionDelegate");
    if (!customURLConnectionDelegate) {
        return;
    }

    NSLog(@"[LC] 🔓 Found Cordova SSLCertificateChecker plugin, hooking fingerprint validation");

    Method isFingerprintTrustedMethod = class_getInstanceMethod(customURLConnectionDelegate, @selector(isFingerprintTrusted:));
    if (isFingerprintTrustedMethod) {
        orig_customURLConnectionDelegateIsFingerprintTrusted = method_getImplementation(isFingerprintTrustedMethod);
        method_setImplementation(isFingerprintTrustedMethod, (IMP)hook_customURLConnectionDelegateIsFingerprintTrusted);
    }
}

static void setupNSURLSessionHooks(void) {
    // Find all classes that implement URLSession:didReceiveChallenge:completionHandler:
    unsigned int classCount;
    Class *classes = objc_copyClassList(&classCount);

    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        Method method = class_getInstanceMethod(cls, @selector(URLSession:didReceiveChallenge:completionHandler:));

        if (method) {
            NSLog(@"[LC] 🔓 Found NSURLSession delegate in class %s, hooking challenge method", class_getName(cls));

            // Get original implementation before replacing
            IMP originalImp = method_getImplementation(method);

            // Replace with our hook
            method_setImplementation(method, (IMP)hook_urlSessionDidReceiveChallenge);
        }
    }

    free(classes);
}

static void setupLowLevelSSLHooks(void) {
    NSLog(@"[LC] 🔓 Setting up low-level SSL/TLS hooks");

    // Hook SSL functions using fishhook
    struct rebinding ssl_rebindings[] = {
        {"SSLSetSessionOption", (void *)hook_SSLSetSessionOption, (void **)&orig_SSLSetSessionOption},
        {"SSLCreateContext", (void *)hook_SSLCreateContext, (void **)&orig_SSLCreateContext},
        {"SSLHandshake", (void *)hook_SSLHandshake, (void **)&orig_SSLHandshake},
    };

    rebind_symbols(ssl_rebindings, 3);
}

static void setupSSLPinningBypass(void) {
    NSLog(@"[LC] 🔓 Initializing SSL pinning bypass");

    // Framework-level hooks
    setupAFNetworkingHooks();
    setupTrustKitHooks();
    setupCordovaHooks();
    setupNSURLSessionHooks();

    // Low-level SSL/TLS hooks
    setupLowLevelSSLHooks();

    NSLog(@"[LC] 🔓 SSL pinning bypass setup complete");
}

// MARK: SSL Killswitch 3
static OSStatus hook_SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result) {
    OSStatus res = orig_SecTrustEvaluate(trust, result);
    if (result) *result = kSecTrustResultProceed;
    return errSecSuccess;
}

static bool hook_SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error) {
    if (error && *error) *error = NULL;
    return true;
}

static OSStatus hook_SecTrustEvaluateAsync(SecTrustRef trust, dispatch_queue_t queue, SecTrustCallback result) {
    dispatch_async(queue, ^{ result(trust, true); });
    return errSecSuccess;
}

static OSStatus hook_SecTrustEvaluateAsyncWithError(SecTrustRef trust, dispatch_queue_t queue, SecTrustWithErrorCallback result) {
    dispatch_async(queue, ^{ result(trust, true, NULL); });
    return errSecSuccess;
}

static OSStatus hook_SecTrustEvaluateFastAsync(SecTrustRef trust, dispatch_queue_t queue, SecTrustCallback result) {
    dispatch_async(queue, ^{ result(trust, true); });
    return errSecSuccess;
}

// MARK: BoringSSL Hooks
static int hook_verify_callback(void *ssl, uint8_t *out_alert) {
    return 0; // ssl_verify_ok
}

static void hook_SSL_set_custom_verify(void *ssl, int mode, int (*callback)(void *, uint8_t *)) {
    orig_SSL_set_custom_verify(ssl, 0, hook_verify_callback);
}

static void hook_SSL_CTX_set_custom_verify(void *ctx, int mode, int (*callback)(void *, uint8_t *)) {
    orig_SSL_CTX_set_custom_verify(ctx, 0, hook_verify_callback);
}

// MARK : Signal Handlers

int hook_sigaction(int sig, const struct sigaction *restrict act, struct sigaction *restrict oact) {
    // Call the original function first
    int result = orig_sigaction(sig, act, oact);

    // If this is a query (act is NULL) and oact is not NULL, spoof the result
    if (act == NULL && oact != NULL) {
        // Make it look like no signal handler is installed
        memset(oact, 0, sizeof(struct sigaction));
        oact->sa_handler = SIG_DFL; // Default handler

        // NSLog(@"[LC] 🎭 Hiding signal handler for signal %d", sig);
    }

    return result;
}

// Advanced Signal handler hook
// int hook_sigaction(int sig, const struct sigaction *restrict act, struct sigaction *restrict oact) {
//     int result = orig_sigaction(sig, act, oact);

//     if (act == NULL && oact != NULL) {
//         // List of signals commonly checked by anti-debugging
//         static const int suspiciousSignals[] = {
//             SIGTRAP,  // Debugger breakpoints
//             SIGSTOP,  // Process stopping
//             SIGTSTP,  // Terminal stop
//             SIGCONT,  // Continue after stop
//             SIGSEGV,  // Segmentation fault (crash reporters)
//             SIGBUS,   // Bus error
//             SIGILL,   // Illegal instruction
//             SIGABRT,  // Abort signal
//             SIGFPE,   // Floating point exception
//         };

//         // Check if this signal is commonly monitored
//         bool shouldSpoof = false;
//         for (int i = 0; i < sizeof(suspiciousSignals)/sizeof(int); i++) {
//             if (sig == suspiciousSignals[i]) {
//                 shouldSpoof = true;
//                 break;
//             }
//         }

//         if (shouldSpoof) {
//             // Clear the signal handler to look clean
//             memset(oact, 0, sizeof(struct sigaction));
//             oact->sa_handler = SIG_DFL;
//             NSLog(@"[LC] 🎭 Spoofed signal handler for signal %d (%s)", sig, strsignal(sig));
//         }
//     }

//     return result;
// }

// MARK: Bundle ID Section
// Context detection function - this is the key intelligence
static BOOL shouldUseLiveContainerBundleId(void) {
    // Get the call stack to determine context
    NSArray *callStack = [NSThread callStackSymbols];

    // Check for system framework calls that need LiveContainer's bundle ID
    for (NSString *frame in callStack) {
        // Notification permission requests
        if ([frame containsString:@"UserNotifications"] ||
            [frame containsString:@"UNUserNotificationCenter"] ||
            [frame containsString:@"requestAuthorizationWithOptions"]) {
            return YES;
        }

        // File picker and document interaction
        if ([frame containsString:@"UIDocumentPickerViewController"] ||
            [frame containsString:@"UIDocumentInteractionController"] ||
            [frame containsString:@"documentPicker"] ||
            [frame containsString:@"_UIDocumentPicker"]) {
            return YES;
        }

        // Photo library access
        if ([frame containsString:@"Photos"] ||
            [frame containsString:@"PHPhotoLibrary"] ||
            [frame containsString:@"PHAuthorizationStatus"]) {
            return YES;
        }

        // Camera and microphone permissions
        if ([frame containsString:@"AVCaptureDevice"] ||
            [frame containsString:@"AVAudioSession"] ||
            [frame containsString:@"requestAccessForMediaType"]) {
            return YES;
        }

        // Location services
        if ([frame containsString:@"CoreLocation"] ||
            [frame containsString:@"CLLocationManager"] ||
            [frame containsString:@"requestWhenInUseAuthorization"]) {
            return YES;
        }

        // Contacts access
        if ([frame containsString:@"ContactsUI"] ||
            [frame containsString:@"CNContactStore"] ||
            [frame containsString:@"requestAccessForEntityType"]) {
            return YES;
        }

        // App Store services that rely on host app identity
        if ([frame containsString:@"StoreKit"] ||
            [frame containsString:@"SKStoreProductViewController"]) {
            return YES;
        }

        // Keychain access (system level)
        if ([frame containsString:@"SecItem"]) {
            return YES;
        }
    }

    // Check for specific security validation patterns that should see original bundle ID
    for (NSString *frame in callStack) {
        // Internal security checks - these should see original bundle ID
        if ([frame containsString:@"SecurityGuardSDK"] ||
            [frame containsString:@"security"] ||
            [frame containsString:@"guard"] ||
            [frame containsString:@"validation"] ||
            [frame containsString:@"integrity"] ||
            [frame containsString:@"verify"] ||
            [frame containsString:@"checkBundle"] ||
            [frame containsString:@"yw_1222"]) { // Your specific security file
            return NO;
        }

        // Anti-tampering checks
        if ([frame containsString:@"tamper"] ||
            [frame containsString:@"jailbreak"] ||
            [frame containsString:@"debug"] ||
            [frame containsString:@"hook"]) {
            return NO;
        }
    }

    // Default: use original bundle ID for unknown contexts
    return NO;
}

static NSString *LCResolvedBundleIDForCurrentContext(void) {
    NSString *guestBundleId = NSUserDefaults.lcGuestAppId;
    if (guestBundleId.length == 0) {
        guestBundleId = originalGuestBundleId;
    }

    if (useSelectiveBundleIdSpoofing) {
        BOOL useLCBundleID = shouldUseLiveContainerBundleId();
        NSString *bundleIDToExpose = useLCBundleID ? liveContainerBundleId : originalGuestBundleId;
        if (bundleIDToExpose.length > 0) {
            return bundleIDToExpose;
        }
    }
    if (guestBundleId.length > 0) {
        return guestBundleId;
    }
    if (originalGuestBundleId.length > 0) {
        return originalGuestBundleId;
    }
    return NSBundle.mainBundle.bundleIdentifier;
}

static NSString *LCRewrittenAccessGroup(NSString *accessGroup, NSString *fallbackBundleID) {
    if (hostTeamIdentifier.length == 0) {
        return [accessGroup isKindOfClass:NSString.class] ? accessGroup : nil;
    }
    if ([accessGroup isKindOfClass:NSString.class] && accessGroup.length > 0) {
        NSRange dotRange = [accessGroup rangeOfString:@"."];
        if (dotRange.location != NSNotFound && dotRange.location + 1 < accessGroup.length) {
            NSString *suffix = [accessGroup substringFromIndex:dotRange.location + 1];
            return [NSString stringWithFormat:@"%@.%@", hostTeamIdentifier, suffix];
        }
    }
    if (fallbackBundleID.length > 0) {
        return [NSString stringWithFormat:@"%@.%@", hostTeamIdentifier, fallbackBundleID];
    }
    return [accessGroup isKindOfClass:NSString.class] ? accessGroup : nil;
}

static NSString *LCRewrittenAppIdentifierPrefix(void) {
    if (hostTeamIdentifier.length == 0) {
        return nil;
    }
    return [hostTeamIdentifier hasSuffix:@"."] ? hostTeamIdentifier : [hostTeamIdentifier stringByAppendingString:@"."];
}

static void LCApplyBundleIdentityCompatibility(NSMutableDictionary *dictionary, NSString *fallbackBundleID) {
    if (!useBundleIdentityCompatibilityShims || ![dictionary isKindOfClass:NSDictionary.class]) {
        return;
    }
    NSString *rewrittenGroup = LCRewrittenAccessGroup(dictionary[@"SharedKeychainAccessGroup"], fallbackBundleID);
    if (rewrittenGroup.length > 0) {
        dictionary[@"SharedKeychainAccessGroup"] = rewrittenGroup;
    }

    NSString *rewrittenPrefix = LCRewrittenAppIdentifierPrefix();
    if (rewrittenPrefix.length > 0) {
        id existingPrefix = dictionary[@"AppIdentifierPrefix"];
        if ([existingPrefix isKindOfClass:NSArray.class]) {
            dictionary[@"AppIdentifierPrefix"] = @[rewrittenPrefix];
        } else {
            dictionary[@"AppIdentifierPrefix"] = rewrittenPrefix;
        }
    }
}

static BOOL LCIsEmbeddedMobileProvisionRequest(NSString *name, NSString *ext) {
    if (![name isKindOfClass:NSString.class] || name.length == 0) {
        return NO;
    }
    NSString *lowerName = name.lowercaseString;
    NSString *lowerExt = [ext isKindOfClass:NSString.class] ? ext.lowercaseString : @"";
    if ([lowerName isEqualToString:@"embedded"] && [lowerExt isEqualToString:@"mobileprovision"]) {
        return YES;
    }
    if ([lowerName isEqualToString:@"embedded.mobileprovision"]) {
        return YES;
    }
    return [lowerName hasSuffix:@"/embedded.mobileprovision"];
}

static BOOL LCShouldHideProvisioningPath(NSString *path) {
    if (!hideProvisioningArtifacts || ![path isKindOfClass:NSString.class] || path.length == 0) {
        return NO;
    }
    return [path.lowercaseString hasSuffix:@"embedded.mobileprovision"];
}

static BOOL LCShouldBypassGuestCanOpenURLBlock(void) {
    NSArray<NSString *> *callStack = [NSThread callStackSymbols];
    for (NSString *frame in callStack) {
        if ([frame containsString:@"UIKit+GuestHooks"] ||
            [frame containsString:@"LCSharedUtils"] ||
            [frame containsString:@"LaunchAppExtension"]) {
            return YES;
        }
    }
    return NO;
}

static BOOL LCShouldBlockGuestCanOpenURL(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) {
        return NO;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (scheme.length == 0) {
        return NO;
    }
    if ([scheme hasPrefix:@"livecontainer"]) {
        return YES;
    }
    static NSSet<NSString *> *blockedSchemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedSchemes = [NSSet setWithArray:@[
            @"sidestore",
        ]];
    });
    return [blockedSchemes containsObject:scheme];
}

static BOOL hook_UIApplication_canOpenURL_guest(id self, SEL _cmd, NSURL *url) {
    if (!LCShouldBypassGuestCanOpenURLBlock() && LCShouldBlockGuestCanOpenURL(url)) {
        return NO;
    }
    if (orig_UIApplication_canOpenURL_guest) {
        return orig_UIApplication_canOpenURL_guest(self, _cmd, url);
    }
    return NO;
}

static NSString* hook_NSBundle_bundleIdentifier(id self, SEL _cmd) {
    NSString* result = orig_NSBundle_bundleIdentifier(self, _cmd);

    if (![self isEqual:[NSBundle mainBundle]]) {
        return result;
    }

    NSString *bundleIDToExpose = LCResolvedBundleIDForCurrentContext();
    if (bundleIDToExpose.length > 0) {
        return bundleIDToExpose;
    }
    return result;
}

static NSDictionary* hook_NSBundle_infoDictionary(id self, SEL _cmd) {
    NSDictionary* result = orig_NSBundle_infoDictionary(self, _cmd);

    if (![self isEqual:[NSBundle mainBundle]]) {
        return result;
    }

    if (!useSelectiveBundleIdSpoofing && !useBundleIdentityCompatibilityShims) {
        return result;
    }

    NSMutableDictionary* modifiedDict = [result mutableCopy];
    if (!modifiedDict) {
        return result;
    }

    NSString *bundleIDToExpose = LCResolvedBundleIDForCurrentContext();
    if (bundleIDToExpose.length == 0) {
        return result;
    }

    modifiedDict[@"CFBundleIdentifier"] = bundleIDToExpose;

    LCApplyBundleIdentityCompatibility(modifiedDict, bundleIDToExpose);
    return [modifiedDict copy];
}

static id hook_NSBundle_objectForInfoDictionaryKey(id self, SEL _cmd, NSString *key) {
    if (![self isEqual:[NSBundle mainBundle]]) {
        return orig_NSBundle_objectForInfoDictionaryKey(self, _cmd, key);
    }

    id originalValue = orig_NSBundle_objectForInfoDictionaryKey(self, _cmd, key);
    if (![key isKindOfClass:NSString.class]) {
        return originalValue;
    }

    NSString *bundleIDToExpose = LCResolvedBundleIDForCurrentContext();
    if ([key isEqualToString:@"CFBundleIdentifier"] && bundleIDToExpose.length > 0) {
        return bundleIDToExpose;
    }

    if (useBundleIdentityCompatibilityShims) {
        if ([key isEqualToString:@"SharedKeychainAccessGroup"]) {
            NSString *rewrittenGroup = LCRewrittenAccessGroup(originalValue, bundleIDToExpose);
            if (rewrittenGroup.length > 0) {
                return rewrittenGroup;
            }
        }
        if ([key isEqualToString:@"AppIdentifierPrefix"]) {
            NSString *rewrittenPrefix = LCRewrittenAppIdentifierPrefix();
            if (rewrittenPrefix.length > 0) {
                if ([originalValue isKindOfClass:NSArray.class]) {
                    return @[rewrittenPrefix];
                }
                return rewrittenPrefix;
            }
        }
    }
    return originalValue;
}

static NSString *hook_NSBundle_pathForResource_ofType(id self, SEL _cmd, NSString *name, NSString *ext) {
    if (hideProvisioningArtifacts &&
        [self isEqual:NSBundle.mainBundle] &&
        LCIsEmbeddedMobileProvisionRequest(name, ext)) {
        return nil;
    }
    if (orig_NSBundle_pathForResource_ofType) {
        return orig_NSBundle_pathForResource_ofType(self, _cmd, name, ext);
    }
    return nil;
}

static NSURL *hook_NSBundle_URLForResource_withExtension(id self, SEL _cmd, NSString *name, NSString *ext) {
    if (hideProvisioningArtifacts &&
        [self isEqual:NSBundle.mainBundle] &&
        LCIsEmbeddedMobileProvisionRequest(name, ext)) {
        return nil;
    }
    if (orig_NSBundle_URLForResource_withExtension) {
        return orig_NSBundle_URLForResource_withExtension(self, _cmd, name, ext);
    }
    return nil;
}

static NSURL *hook_NSBundle_appStoreReceiptURL(id self, SEL _cmd) {
    NSURL *url = orig_NSBundle_appStoreReceiptURL ? orig_NSBundle_appStoreReceiptURL(self, _cmd) : nil;
    if (!hideProvisioningArtifacts || ![self isEqual:NSBundle.mainBundle] || ![url isKindOfClass:NSURL.class]) {
        return url;
    }
    NSString *last = url.lastPathComponent.lowercaseString ?: @"";
    if ([last isEqualToString:@"sandboxreceipt"]) {
        return [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"receipt"];
    }
    return url;
}

static BOOL hook_NSFileManager_fileExistsAtPath(id self, SEL _cmd, NSString *path) {
    if (LCShouldHideProvisioningPath(path)) {
        return NO;
    }
    if (orig_NSFileManager_fileExistsAtPath) {
        return orig_NSFileManager_fileExistsAtPath(self, _cmd, path);
    }
    return NO;
}

static NSString *LCExpectedHostBundleIdentifier(void) {
    void *task = SecTaskCreateFromSelf(NULL);
    if (!task) return nil;

    CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("application-identifier"), NULL);
    CFRelease(task);
    if (!value) return nil;

    NSString *applicationIdentifier = CFBridgingRelease(value);
    NSRange dotRange = [applicationIdentifier rangeOfString:@"."];
    if (dotRange.location == NSNotFound || dotRange.location + 1 >= applicationIdentifier.length) {
        return nil;
    }
    return [applicationIdentifier substringFromIndex:dotRange.location + 1];
}

static NSString *LCExpectedHostTeamIdentifier(void) {
    void *task = SecTaskCreateFromSelf(NULL);
    if (!task) return nil;

    CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("application-identifier"), NULL);
    CFRelease(task);
    if (!value) return nil;

    NSString *applicationIdentifier = CFBridgingRelease(value);
    NSRange dotRange = [applicationIdentifier rangeOfString:@"."];
    if (dotRange.location == NSNotFound || dotRange.location == 0) {
        return nil;
    }
    return [applicationIdentifier substringToIndex:dotRange.location];
}

static void configureSelectiveBundleIdSpoofing(NSDictionary *guestAppInfo, BOOL hideLiveContainer) {
    NSString *originalFromConfig = guestAppInfo[@"LCOrignalBundleIdentifier"];
    if ([originalFromConfig isKindOfClass:NSString.class] && originalFromConfig.length > 0) {
        originalGuestBundleId = originalFromConfig;
    } else {
        originalGuestBundleId = NSUserDefaults.lcGuestAppId ?: NSBundle.mainBundle.bundleIdentifier;
    }

    NSString *entitlementBundleID = LCExpectedHostBundleIdentifier();
    liveContainerBundleId = entitlementBundleID ?: NSUserDefaults.lcMainBundle.bundleIdentifier;
    if (liveContainerBundleId.length == 0) {
        liveContainerBundleId = NSBundle.mainBundle.bundleIdentifier;
    }

    BOOL forceHostBundle = [guestAppInfo[@"doUseLCBundleId"] boolValue];
    useSelectiveBundleIdSpoofing = hideLiveContainer || forceHostBundle;
    useBundleIdentityCompatibilityShims = YES;
    hideProvisioningArtifacts = YES;
    hostTeamIdentifier = LCExpectedHostTeamIdentifier();
    if ((!useSelectiveBundleIdSpoofing && !useBundleIdentityCompatibilityShims && !hideProvisioningArtifacts) ||
        didInstallSelectiveBundleHooks) {
        return;
    }

    Class bundleClass = NSBundle.class;
    Method bundleIdentifierMethod = class_getInstanceMethod(bundleClass, @selector(bundleIdentifier));
    if (bundleIdentifierMethod && !orig_NSBundle_bundleIdentifier) {
        orig_NSBundle_bundleIdentifier = (NSString *(*)(id, SEL))method_setImplementation(bundleIdentifierMethod, (IMP)hook_NSBundle_bundleIdentifier);
    }

    Method infoDictionaryMethod = class_getInstanceMethod(bundleClass, @selector(infoDictionary));
    if (infoDictionaryMethod && !orig_NSBundle_infoDictionary) {
        orig_NSBundle_infoDictionary = (NSDictionary *(*)(id, SEL))method_setImplementation(infoDictionaryMethod, (IMP)hook_NSBundle_infoDictionary);
    }

    Method objectForInfoDictionaryKeyMethod = class_getInstanceMethod(bundleClass, @selector(objectForInfoDictionaryKey:));
    if (objectForInfoDictionaryKeyMethod && !orig_NSBundle_objectForInfoDictionaryKey) {
        orig_NSBundle_objectForInfoDictionaryKey = (id (*)(id, SEL, NSString *))method_setImplementation(objectForInfoDictionaryKeyMethod, (IMP)hook_NSBundle_objectForInfoDictionaryKey);
    }

    Method pathForResourceMethod = class_getInstanceMethod(bundleClass, @selector(pathForResource:ofType:));
    if (pathForResourceMethod && !orig_NSBundle_pathForResource_ofType) {
        orig_NSBundle_pathForResource_ofType = (NSString *(*)(id, SEL, NSString *, NSString *))method_setImplementation(pathForResourceMethod, (IMP)hook_NSBundle_pathForResource_ofType);
    }

    Method urlForResourceMethod = class_getInstanceMethod(bundleClass, @selector(URLForResource:withExtension:));
    if (urlForResourceMethod && !orig_NSBundle_URLForResource_withExtension) {
        orig_NSBundle_URLForResource_withExtension = (NSURL *(*)(id, SEL, NSString *, NSString *))method_setImplementation(urlForResourceMethod, (IMP)hook_NSBundle_URLForResource_withExtension);
    }

    Method appStoreReceiptURLMethod = class_getInstanceMethod(bundleClass, @selector(appStoreReceiptURL));
    if (appStoreReceiptURLMethod && !orig_NSBundle_appStoreReceiptURL) {
        orig_NSBundle_appStoreReceiptURL = (NSURL *(*)(id, SEL))method_setImplementation(appStoreReceiptURLMethod, (IMP)hook_NSBundle_appStoreReceiptURL);
    }

    Method fileExistsMethod = class_getInstanceMethod(NSFileManager.class, @selector(fileExistsAtPath:));
    if (fileExistsMethod && !orig_NSFileManager_fileExistsAtPath) {
        orig_NSFileManager_fileExistsAtPath = (BOOL (*)(id, SEL, NSString *))method_setImplementation(fileExistsMethod, (IMP)hook_NSFileManager_fileExistsAtPath);
    }

    Class uiApplicationClass = objc_getClass("UIApplication");
    Method canOpenURLMethod = class_getInstanceMethod(uiApplicationClass, @selector(canOpenURL:));
    if (canOpenURLMethod && !orig_UIApplication_canOpenURL_guest) {
        orig_UIApplication_canOpenURL_guest = (BOOL (*)(id, SEL, NSURL *))method_setImplementation(canOpenURLMethod, (IMP)hook_UIApplication_canOpenURL_guest);
    }

    didInstallSelectiveBundleHooks = YES;
}

// MARK: Init / Guest Context

static void lc_applyGuestContextConfiguration(NSDictionary *guestAppInfo, bool hideLiveContainer) {
    lc_configureNetworkSpoofing(guestAppInfo);
    bypassSSLPinning = [guestAppInfo[@"bypassSSLPinning"] boolValue];
    configureSelectiveBundleIdSpoofing(guestAppInfo, hideLiveContainer);

    BOOL hasGuestContext = [guestAppInfo isKindOfClass:[NSDictionary class]];
    id csopsShimSetting = guestAppInfo[@"deviceSpoofMaskCSOpsFlags"];
    if (!hasGuestContext) {
        gEnableGuestSelfCSOpsShim = NO;
    } else if (csopsShimSetting != nil && [csopsShimSetting respondsToSelector:@selector(boolValue)]) {
        gEnableGuestSelfCSOpsShim = [csopsShimSetting boolValue];
    } else {
        // Default on for guest app testing; can be disabled per app via deviceSpoofMaskCSOpsFlags=false.
        gEnableGuestSelfCSOpsShim = YES;
    }
    NSLog(@"[LC] 🎭 self csops flag shim %@", gEnableGuestSelfCSOpsShim ? @"enabled" : @"disabled");
}

// MARK: Init / Dyld Core

static void lc_resolveDyldRuntimeContext(void) {
    int imageCount = _dyld_image_count();
    for (int i = 0; i < imageCount; ++i) {
        const struct mach_header *currentImageHeader = _dyld_get_image_header(i);
        if (currentImageHeader->filetype == MH_EXECUTE) {
            lcImageIndex = i;
            break;
        }
    }

    if (NSUserDefaults.isLiveProcess) {
        lcMainBundlePath = NSUserDefaults.lcMainBundle.bundlePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.fileSystemRepresentation;
    } else {
        lcMainBundlePath = NSUserDefaults.lcMainBundle.bundlePath.fileSystemRepresentation;
    }
    orig_dyld_get_image_header = _dyld_get_image_header;
}

static void lc_installDyldCoreHooks(bool hideLiveContainer) {
    // Hook dlsym to solve RTLD_MAIN_ONLY, hook other functions to hide LiveContainer itself.
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, dlsym, hook_dlsym, nil);
    if (!hideLiveContainer) {
        return;
    }

    detectConfiguredTweaksEarly();
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, _dyld_image_count, hook_dyld_image_count, nil);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, _dyld_get_image_header, hook_dyld_get_image_header, nil);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, _dyld_get_image_vmaddr_slide, hook_dyld_get_image_vmaddr_slide, nil);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, _dyld_get_image_name, hook_dyld_get_image_name, nil);
    rebind_symbols((struct rebinding[1]){
        {"sigaction", (void *)hook_sigaction, (void **)&orig_sigaction},
    }, 1);
}

// MARK: Init / Network

static void lc_installNetworkSpoofingHooks(void) {
    rebind_symbols((struct rebinding[8]){
        {"CFNetworkCopySystemProxySettings", (void *)hook_CFNetworkCopySystemProxySettings, (void **)&orig_CFNetworkCopySystemProxySettings},
        {"CNCopyCurrentNetworkInfo", (void *)hook_CNCopyCurrentNetworkInfo, (void **)&orig_CNCopyCurrentNetworkInfo},
        {"getifaddrs", (void *)hook_getifaddrs, (void **)&orig_getifaddrs},
        {"if_nametoindex", (void *)hook_if_nametoindex, (void **)&orig_if_nametoindex},
        {"if_indextoname", (void *)hook_if_indextoname, (void **)&orig_if_indextoname},
        {"if_nameindex", (void *)hook_if_nameindex, (void **)&orig_if_nameindex},
        {"csops", (void *)hook_csops, (void **)&orig_csops},
        {"csops_audittoken", (void *)hook_csops_audittoken, (void **)&orig_csops_audittoken},
    }, 8);
    NSLog(@"[LC] 🌐 fishhook rebound base network hooks: CFNetworkCopySystemProxySettings=%p CNCopyCurrentNetworkInfo=%p getifaddrs=%p",
          orig_CFNetworkCopySystemProxySettings,
          orig_CNCopyCurrentNetworkInfo,
          orig_getifaddrs);
    NSLog(@"[LC] 🌐 fishhook rebound if_nametoindex=%p if_indextoname=%p if_nameindex=%p",
          orig_if_nametoindex,
          orig_if_indextoname,
          orig_if_nameindex);
}

// MARK: Init / Optional Features

static BOOL lc_applySDKVersionSpoofing(uint32_t spoofSDKVersion) {
    if (!spoofSDKVersion) {
        return YES;
    }

    guestAppSdkVersion = spoofSDKVersion;
    return (initGuestSDKVersionInfo() &&
            performHookDyldApi("dyld_program_sdk_at_least", 1, (void **)&orig_dyld_program_sdk_at_least, hook_dyld_program_sdk_at_least) &&
            performHookDyldApi("dyld_get_program_sdk_version", 0, (void **)&orig_dyld_get_program_sdk_version, hook_dyld_get_program_sdk_version));
}

static void lc_installGuestAddons(NSDictionary *guestAppInfo) {
    if (guestAppInfo[@"spoofGPS"] && [guestAppInfo[@"spoofGPS"] boolValue]) {
        CoreLocationGuestHooksInit();
    }

    if (guestAppInfo[@"spoofCamera"] && [guestAppInfo[@"spoofCamera"] boolValue]) {
        AVFoundationGuestHooksInit();
    }
}

static void lc_configureDlopenRuntimeHook(bool hookDlopen) {
    hookedDlopen = hookDlopen;
    if (!hookDlopen) {
        return;
    }
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, dlopen, jitless_hook_dlopen, nil);
}

// MARK: Init
void DyldHooksInit(bool hideLiveContainer, bool hookDlopen, uint32_t spoofSDKVersion) {
    if (gDidRunDyldHooksInit) {
        return;
    }
    gDidRunDyldHooksInit = YES;

    NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
    lc_applyGuestContextConfiguration(guestAppInfo, hideLiveContainer);
    lc_resolveDyldRuntimeContext();
    lc_installDyldCoreHooks(hideLiveContainer);
    lc_installNetworkSpoofingHooks();

    if (bypassSSLPinning) {
        setupSSLPinningBypass();
    }

    appExecutableFileTypeOverwritten = !hideLiveContainer;
    if (!lc_applySDKVersionSpoofing(spoofSDKVersion)) {
        return;
    }

    lc_installGuestAddons(guestAppInfo);
    lc_configureDlopenRuntimeHook(hookDlopen);

#if TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR
    DyldHookLoadableIntoProcess();
#endif
}

void* getGuestAppHeader(void) {
    return (void*)orig_dyld_get_image_header(appMainImageIndex);
}

#pragma mark - Fix black screen
#if !TARGET_OS_SIMULATOR
#define HOOK_LOCK_1ST_ARG void *ptr,
#else
#define HOOK_LOCK_1ST_ARG
#endif
// Guard the temporary libdyld lock-hook patching. This patch is process-global, so keep it serialized.
static os_unfair_lock gDlopenNoLockPatchLock = OS_UNFAIR_LOCK_INIT;

// Only skip locking for the calling thread while dlopen_nolock is executing.
static __thread BOOL gIgnoreDyldRecursiveLockOnThisThread = NO;
static __thread int gDlopenNoLockDepth = 0;

// The lock pointer we ignore (initialized once, thread-safely).
static _Atomic(void *) lockPtrToIgnore = NULL;

static inline void *lc_getLockPtrToIgnoreOrInit(void *observedLock) {
    void *current = atomic_load_explicit(&lockPtrToIgnore, memory_order_acquire);
    if (current == NULL && observedLock != NULL) {
        void *expected = NULL;
        atomic_compare_exchange_strong_explicit(&lockPtrToIgnore,
                                               &expected,
                                               observedLock,
                                               memory_order_release,
                                               memory_order_relaxed);
        current = atomic_load_explicit(&lockPtrToIgnore, memory_order_acquire);
    }
    return current;
}

void hook_libdyld_os_unfair_recursive_lock_lock_with_options(HOOK_LOCK_1ST_ARG void* lock, uint32_t options) {
    void *ignorePtr = lc_getLockPtrToIgnoreOrInit(lock);
    if (gIgnoreDyldRecursiveLockOnThisThread && ignorePtr != NULL && lock == ignorePtr) {
        return;
    }
    os_unfair_recursive_lock_lock_with_options(lock, options);
}
void hook_libdyld_os_unfair_recursive_lock_unlock(HOOK_LOCK_1ST_ARG void* lock) {
    void *ignorePtr = atomic_load_explicit(&lockPtrToIgnore, memory_order_acquire);
    if (gIgnoreDyldRecursiveLockOnThisThread && ignorePtr != NULL && lock == ignorePtr) {
        return;
    }
    os_unfair_recursive_lock_unlock(lock);
}

void *dlopen_nolock(const char *path, int mode) {
    if (gDlopenNoLockDepth > 0) {
        // Avoid deadlocking on the patch lock if dlopen_nolock is re-entered on the same thread.
        if (hookedDlopen) {
            return jitless_hook_dlopen(path, mode);
        }
        return dlopen(path, mode);
    }
    gDlopenNoLockDepth++;

    os_unfair_lock_lock(&gDlopenNoLockPatchLock);

    void *result = NULL;
    BOOL previousIgnore = gIgnoreDyldRecursiveLockOnThisThread;

    const char *libdyldPath = "/usr/lib/system/libdyld.dylib";
    mach_header_u *libdyldHeader = LCGetLoadedImageHeader(0, libdyldPath);
    assert(libdyldHeader != NULL);
#if !TARGET_OS_SIMULATOR
    NSString *lockUnlockPtrName = @"dyld4::LibSystemHelpers::os_unfair_recursive_lock_lock_with_options";
    void **lockUnlockPtr = getCachedSymbol(lockUnlockPtrName, libdyldHeader);
    if(!lockUnlockPtr) {
        void **vtableLibSystemHelpers = litehook_find_dsc_symbol(libdyldPath, "__ZTVN5dyld416LibSystemHelpersE");
        void *lockFunc = litehook_find_dsc_symbol(libdyldPath, "__ZNK5dyld416LibSystemHelpers42os_unfair_recursive_lock_lock_with_optionsEP26os_unfair_recursive_lock_s24os_unfair_lock_options_t");
        void *unlockFunc = litehook_find_dsc_symbol(libdyldPath, "__ZNK5dyld416LibSystemHelpers31os_unfair_recursive_lock_unlockEP26os_unfair_recursive_lock_s");

        // Find the pointers in vtable storing the lock and unlock functions, they must be there or this loop will hit unreadable memory region and crash
        while(!lockUnlockPtr) {
            if(vtableLibSystemHelpers[0] == lockFunc) {
                lockUnlockPtr = vtableLibSystemHelpers;
                // unlockPtr stands next to lockPtr in vtable
                NSCAssert(vtableLibSystemHelpers[1] == unlockFunc, @"dyld has changed: lock and unlock functions are not next to each other");
                break;
            }
            vtableLibSystemHelpers++;
        }
        saveCachedSymbol(lockUnlockPtrName, libdyldHeader, (uintptr_t)lockUnlockPtr - (uintptr_t)libdyldHeader);
    }

    kern_return_t ret;
    ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)lockUnlockPtr, sizeof(uintptr_t[2]), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    assert(ret == KERN_SUCCESS);
    void *origLockPtr = lockUnlockPtr[0], *origUnlockPtr = lockUnlockPtr[1];
    lockUnlockPtr[0] = hook_libdyld_os_unfair_recursive_lock_lock_with_options;
    lockUnlockPtr[1] = hook_libdyld_os_unfair_recursive_lock_unlock;
    gIgnoreDyldRecursiveLockOnThisThread = YES;
    if(hookedDlopen) {
        result = jitless_hook_dlopen(path, mode);
    } else {
        result = dlopen(path, mode);
    }
    gIgnoreDyldRecursiveLockOnThisThread = previousIgnore;

    ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)lockUnlockPtr, sizeof(uintptr_t[2]), false, PROT_READ | PROT_WRITE);
    assert(ret == KERN_SUCCESS);
    lockUnlockPtr[0] = origLockPtr;
    lockUnlockPtr[1] = origUnlockPtr;

    ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)lockUnlockPtr, sizeof(uintptr_t[2]), false, PROT_READ);
    assert(ret == KERN_SUCCESS);
#else
    litehook_rebind_symbol(libdyldHeader, os_unfair_recursive_lock_lock_with_options, hook_libdyld_os_unfair_recursive_lock_lock_with_options, nil);
    litehook_rebind_symbol(libdyldHeader, os_unfair_recursive_lock_unlock, hook_libdyld_os_unfair_recursive_lock_unlock, nil);
    gIgnoreDyldRecursiveLockOnThisThread = YES;
    if (hookedDlopen) {
        result = jitless_hook_dlopen(path, mode);
    } else {
        result = dlopen(path, mode);
    }
    gIgnoreDyldRecursiveLockOnThisThread = previousIgnore;
    litehook_rebind_symbol(libdyldHeader, hook_libdyld_os_unfair_recursive_lock_lock_with_options, os_unfair_recursive_lock_lock_with_options, nil);
    litehook_rebind_symbol(libdyldHeader, hook_libdyld_os_unfair_recursive_lock_unlock, os_unfair_recursive_lock_unlock, nil);
#endif

    os_unfair_lock_unlock(&gDlopenNoLockPatchLock);
    gDlopenNoLockDepth--;

    return result;
}

#pragma mark - Workaround `file system sandbox blocked mmap()`
// when using multitask app in private container, we need to temporarily hook dyld's mmap
mach_port_t excPort;
void *exception_handler(void *unused) {
    mach_msg_server(mach_exc_server, sizeof(union __RequestUnion__catch_mach_exc_subsystem), excPort, MACH_MSG_OPTION_NONE);
    abort();
}

void *jitless_hook_dlopen(const char *path, int mode) {
    if (!excPort) {
        searchDyldFunctions();
        mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &excPort);
        mach_port_insert_right(mach_task_self(), excPort, excPort, MACH_MSG_TYPE_MAKE_SEND);
        pthread_t thread;
        pthread_create(&thread, NULL, exception_handler, NULL);
    }

    // save old thread states
    exception_mask_t mask = EXC_MASK_BREAKPOINT;
    mach_msg_type_number_t masksCnt = 1;
    exception_handler_t handler = excPort;
    exception_behavior_t behavior = EXCEPTION_STATE | MACH_EXCEPTION_CODES;
    thread_state_flavor_t flavor = ARM_THREAD_STATE64;
    arm_debug_state64_t origDebugState;
    mach_port_t thread = mach_thread_self();
    thread_get_state(thread, ARM_DEBUG_STATE64, (thread_state_t)&origDebugState, &(mach_msg_type_number_t){ARM_DEBUG_STATE64_COUNT});
    thread_swap_exception_ports(thread, mask, handler, behavior, flavor, &mask, &masksCnt, &handler, &behavior, &flavor);
    assert(masksCnt == 1);
    
    // hook dyld's mmap
    arm_debug_state64_t hookDebugState = {
        .__bvr = {(uint64_t)orig_dyld_mmap},
        .__bcr = {0x1e5},
    };
    thread_set_state(thread, ARM_DEBUG_STATE64, (thread_state_t)&hookDebugState, ARM_DEBUG_STATE64_COUNT);

    // fixup @loader_path since we cannot use musttail here
    void *result;
    void *callerAddr = __builtin_return_address(0);
    struct dl_info info;
    if (path && !strncmp(path, "@loader_path/", 13) && dladdr(callerAddr, &info)) {
        char resolvedPath[PATH_MAX];
        snprintf(resolvedPath, sizeof(resolvedPath), "%s/%s", dirname((char *)info.dli_fname), path + 13);
        result = orig_dlopen(resolvedPath, mode);
    } else {
        result = orig_dlopen(path, mode);
    }

    // restore old thread states
    thread_set_state(thread, ARM_DEBUG_STATE64, (thread_state_t)&origDebugState, ARM_DEBUG_STATE64_COUNT);
    thread_swap_exception_ports(thread, mask, handler, behavior, flavor, &mask, &masksCnt, &handler, &behavior, &flavor);
    
    return result;
}

void* jitless_hook_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset) {
    void *map = __mmap(addr, len, prot, flags, fd, offset);
    // only handle mapping __TEXT segment from fd outside of permitted path
    if (map != MAP_FAILED || !(prot & PROT_EXEC) || fd < 0) return map;

    // to get around `file system sandbox blocked mmap()` we temporarily move it to permitted path
    char filePath[PATH_MAX];
    if (fcntl(fd, F_GETPATH, filePath) != 0) return map;
    char newTmpPath[PATH_MAX];
    sprintf(newTmpPath, "%s/Documents/%p.dylib", getenv("LP_HOME_PATH"), addr);
    rename(filePath, newTmpPath);
    map = __mmap(addr, len, prot, flags, fd, offset);
    rename(newTmpPath, filePath);

    return map;
}

kern_return_t catch_mach_exception_raise_state( mach_port_t exception_port, exception_type_t exception, const mach_exception_data_t code, mach_msg_type_number_t codeCnt, int *flavor, const thread_state_t old_state, mach_msg_type_number_t old_stateCnt, thread_state_t new_state, mach_msg_type_number_t *new_stateCnt) {
    arm_thread_state64_t *old = (arm_thread_state64_t *)old_state;
    arm_thread_state64_t *new = (arm_thread_state64_t *)new_state;
    uint64_t pc = arm_thread_state64_get_pc(*old);
    // TODO: merge with dyld bypass?
    if(pc == (uint64_t)orig_dyld_mmap) {
        *new = *old;
        *new_stateCnt = old_stateCnt;
        arm_thread_state64_set_pc_fptr(*new, jitless_hook_mmap);
        return KERN_SUCCESS;
    }
    NSLog(@"[DyldLVBypass] Unknown breakpoint at pc: %p", (void*)pc);
    return KERN_FAILURE;
}

kern_return_t catch_mach_exception_raise(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, mach_exception_data_t code, mach_msg_type_number_t codeCnt) {
    abort();
}

kern_return_t catch_mach_exception_raise_state_identity(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, mach_exception_data_t code, mach_msg_type_number_t codeCnt, int *flavor, thread_state_t old_state, mach_msg_type_number_t old_stateCnt, thread_state_t new_state, mach_msg_type_number_t *new_stateCnt) {
    abort();
}
