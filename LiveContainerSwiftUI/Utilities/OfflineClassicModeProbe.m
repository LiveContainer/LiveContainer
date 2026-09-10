#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <mach-o/loader.h>
#import <mach-o/utils.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "LCUtils.h"

void bypass_os_variant_has_internal_content(void (^block)(void));

static BOOL LCSetScalarIvar(id object, const char *name, const void *value, size_t size) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar) return NO;
    ptrdiff_t offset = ivar_getOffset(ivar);
    memcpy((uint8_t *)(__bridge void *)object + offset, value, size);
    return YES;
}

@interface LCStaticDiskUsage : NSObject
@end

@implementation LCStaticDiskUsage
- (NSNumber *)staticUsage { return @0; }
@end

@interface LCFakeApplicationRecord : NSObject
@end

@implementation LCFakeApplicationRecord
- (unsigned)codeSignatureVersion { return 0; }
- (BOOL)wasBuiltWithThreadSanitizer { return NO; }
@end

@interface LCFakeApplicationIdentity : NSObject
@end

@implementation LCFakeApplicationIdentity
@end

@interface LCFakeProcessIdentity : NSObject <NSCopying>
@end

@implementation LCFakeProcessIdentity
- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}
@end

@interface LCFakeApplicationProxy : NSObject

- (instancetype)initWithBundle:(NSBundle *)bundle
                  executableURL:(NSURL *)executableURL
                     sdkVersion:(NSString *)sdkVersion
                   entitlements:(NSDictionary *)entitlements;

@property(nonatomic, readonly) NSBundle *bundle;
@property(nonatomic, readonly) NSURL *executableURL;
@property(nonatomic, readonly) NSString *linkedSDKVersion;
@property(nonatomic, readonly) NSDictionary *codeEntitlements;

@end

@interface _LSApplicationState

@end

@interface LSBundleInfoCachedValues : NSObject
- (instancetype) _initWithKeys:(NSSet*)keys forDictionary:(NSDictionary*)dict;
@end

@interface SBApplicationInfo : NSObject
- (instancetype)_initWithApplicationProxy:(id)proxy record:(id)record appIdentity:(id)identity processIdentity:(id)identity2 overrideURL:(NSURL*)overrideURL;
@end

@interface SBApplication : NSObject
- (instancetype)initWithApplicationInfo:(SBApplicationInfo*)info;
- (NSInteger)_defaultClassicMode;
@end

@implementation LCFakeApplicationProxy {
    _LSApplicationState *_state;
    LCStaticDiskUsage *_diskUsage;
    NSUUID *_cacheGUID;
}

- (instancetype)initWithBundle:(NSBundle *)bundle
                  executableURL:(NSURL *)executableURL
                     sdkVersion:(NSString *)sdkVersion
                   entitlements:(NSDictionary *)entitlements {
    self = [super init];
    if (self) {
        _bundle = bundle;
        _executableURL = executableURL;
        _linkedSDKVersion = [sdkVersion copy];
        _codeEntitlements = [entitlements copy] ?: @{};
        
        _LSApplicationState* state = [PrivClass(_LSApplicationState) alloc];
        uint64_t stateFlags = 0x14;
        LCSetScalarIvar(state, "_stateFlags", &stateFlags, sizeof(stateFlags));
        _state = state;
        
        _diskUsage = [LCStaticDiskUsage new];
        _cacheGUID = [NSUUID UUID];
    }
    return self;
}

// LSBundleProxy-compatible surface.
- (NSString *)bundleIdentifier { return self.bundle.bundleIdentifier; }
- (NSURL *)bundleURL { return self.bundle.bundleURL; }
- (NSString *)bundleVersion {
    return [self.bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"0";
}
- (NSString *)bundleType { return @"Application"; }
- (NSString *)localizedName {
    return [self.bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
        ?: [self.bundle objectForInfoDictionaryKey:@"CFBundleName"]
        ?: self.bundleIdentifier;
}
- (NSString *)localizedShortName { return [self localizedName]; }
- (NSString *)bundleExecutable {
    return [self.bundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
}
- (NSString *)canonicalExecutablePath { return self.executableURL.path; }
- (NSString *)sdkVersion { return self.linkedSDKVersion; }
- (NSURL *)bundleContainerURL { return self.bundleURL.URLByDeletingLastPathComponent; }
- (NSURL *)dataContainerURL { return nil; }
- (NSURL *)containerURL { return nil; }
- (NSUInteger)sequenceNumber { return 0; }
- (NSUInteger)compatibilityState { return 0; }
- (NSUUID *)cacheGUID { return _cacheGUID; }
- (NSNumber*)genreID { return @0; }

- (LSBundleInfoCachedValues *)objectsForInfoDictionaryKeys:(NSSet *)keys {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:keys.count];
    
    for (NSString *key in keys) {
        id value = [self.bundle objectForInfoDictionaryKey:key];
        if (value) result[key] = value;
    }
    
    return [[PrivClass(LSBundleInfoCachedValues) alloc] _initWithKeys:keys forDictionary:result];
}

- (NSDictionary *)entitlementValuesForKeys:(NSSet *)keys {
    return [[PrivClass(LSBundleInfoCachedValues) alloc] _initWithKeys:keys forDictionary:@{}];
}

- (NSDictionary *)entitlements { return self.codeEntitlements; }
- (NSDictionary *)environmentVariables { return @{}; }
- (NSArray *)machOUUIDs { return @[]; }
- (NSDictionary *)groupContainerURLs { return @{}; }
- (NSString *)shortVersionString {
    return [self.bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
}
- (NSString *)applicationIdentifier {
    return self.codeEntitlements[@"application-identifier"] ?: self.bundleIdentifier;
}
- (NSString *)appIDPrefix { return nil; }
- (NSString *)applicationDSID { return nil; }
- (NSNumber *)platform { return @2; } // iOS
- (NSNumber *)staticDiskUsage { return @0; }
- (NSNumber *)dynamicDiskUsage { return @0; }

// LSApplicationProxy-compatible surface used by FBSApplicationInfo and
// SBApplicationInfo while the designated initializer is running.
- (id)appState { return _state; }
- (NSString *)applicationType { return @"User"; }
- (NSArray *)deviceFamily {
    id value = [self.bundle objectForInfoDictionaryKey:@"UIDeviceFamily"];
    return [value isKindOfClass:NSArray.class] ? value : nil;
}
- (NSArray *)requiredDeviceCapabilities {
    id value = [self.bundle objectForInfoDictionaryKey:@"UIRequiredDeviceCapabilities"];
    return [value isKindOfClass:NSArray.class] ? value : nil;
}
- (NSString *)signerIdentity { return nil; }
- (NSString *)teamID { return self.codeEntitlements[@"com.apple.developer.team-identifier"]; }
- (NSString *)teamIdentifier { return [self teamID]; }
- (BOOL)profileValidated { return YES; }
- (BOOL)UPPValidated { return NO; }
- (BOOL)freeProfileValidated { return NO; }
- (BOOL)isBetaApp { return NO; }
- (BOOL)isBeta { return NO; }
- (BOOL)isRestricted { return NO; }
- (BOOL)isPlaceholder { return NO; }
- (BOOL)isInstalled { return YES; }
- (BOOL)isDeletable { return NO; }
- (BOOL)isDeletableIgnoringRestrictions { return NO; }
- (BOOL)isRemoveableSystemApp { return NO; }
- (BOOL)isRemovedSystemApp { return NO; }
- (BOOL)isAppUpdate { return NO; }
- (BOOL)isDeviceBasedVPP { return NO; }
- (BOOL)isPurchasedReDownload { return NO; }
- (BOOL)isWhitelisted { return YES; }
- (BOOL)missingRequiredSINF { return NO; }
- (BOOL)fileSharingEnabled { return NO; }
- (BOOL)hasMIDBasedSINF { return YES; }
- (BOOL)isGameCenterEnabled { return NO; }
- (BOOL)gameCenterEverEnabled { return NO; }
- (BOOL)isArcadeApp { return NO; }
- (NSUInteger)installType { return 1; }
- (NSUInteger)originalInstallType { return 1; }
- (NSInteger)deviceManagementPolicy { return 0; }
- (NSNumber *)ratingRank { return @0; }
- (NSNumber *)itemID { return nil; }
- (NSNumber *)purchaserDSID { return nil; }
- (NSNumber *)downloaderDSID { return nil; }
- (id)diskUsage { return _diskUsage; }
- (NSString *)genre { return nil; }
- (NSArray *)subgenres { return nil; }
- (NSString *)vendorName { return nil; }
- (NSArray*)UIBackgroundModes { return nil; }
- (NSArray*)appTags { return nil; }
- (BOOL)supportsMultiwindow { return nil; }
- (LCFakeApplicationRecord*)correspondingApplicationRecord { return nil; }
- (LCFakeApplicationRecord*)fbs_correspondingApplicationRecord { return nil; }
@end

void LCLoadSpringBoardFramework(void) {
    bypass_os_variant_has_internal_content(^{
        dlerror();
        void *springBoard = dlopen("/System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard",
                                   RTLD_LAZY | RTLD_GLOBAL);
        
        NSCAssert(springBoard, @"Cannot load SpringBoard.framework: %s",
                  dlerror() ?: "unknown dlopen error");
    });
}

static NSString *LCVersionString(uint32_t version) {
    return [NSString stringWithFormat:@"%u.%u.%u",
            version >> 16, (version >> 8) & 0xff, version & 0xff];
}

NSNumber *LCGetDefaultClassicMode(NSURL *appURL) {
    NSBundle *bundle = [NSBundle bundleWithURL:appURL];
    NSURL *executableURL = bundle.executableURL;
    assert(bundle && executableURL);
    
    static Class SBApplicationClass;
    static Class SBApplicationInfoClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        LCLoadSpringBoardFramework();
        SBApplicationClass = PrivClass(SBApplication);
        SBApplicationInfoClass = PrivClass(SBApplicationInfo);
    });
    
    __block uint32_t sdk = 0;
    LCParseMachO(executableURL.fileSystemRepresentation, true, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
        sdk = dyld_get_sdk_version((const struct mach_header *)header);
    });
    
    LCFakeApplicationProxy *proxy = [[LCFakeApplicationProxy alloc]
                                     initWithBundle:bundle
                                     executableURL:executableURL
                                     sdkVersion:LCVersionString(sdk)
                                     entitlements:@{}];
    
    SBApplicationInfo* sbAppInfo = [[SBApplicationInfoClass alloc] _initWithApplicationProxy:proxy record:[LCFakeApplicationRecord new] appIdentity:[LCFakeApplicationIdentity new] processIdentity:[LCFakeProcessIdentity new] overrideURL:appURL ];
    assert(sbAppInfo);
    SBApplication* sbApp = [[SBApplicationClass alloc] initWithApplicationInfo:sbAppInfo];
    assert(sbApp);
    NSInteger mode = [sbApp _defaultClassicMode];
    return @(mode);
}
