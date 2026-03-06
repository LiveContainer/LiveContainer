@import CommonCrypto;
@import MachO;

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LCAppInfo.h"
#import "LCUtils.h"
#import "../LiveContainer/LCSharedUtils.h"

uint32_t dyld_get_sdk_version(const struct mach_header* mh);

@interface LCAppInfo()
@property UIImage* cachedIcon;
@property UIImage* cachedIconDark;
@property (nonatomic, readonly) NSMutableDictionary *lcMutableAddonSettingsByContainer;
@property (nonatomic, readonly) NSDictionary *lcCurrentContainerAddonSettings;
@property (nonatomic, readonly) NSString *lcCurrentAddonContainerId;
@end

static NSString * const kLCAddonSettingsByContainerKey = @"LCAddonSettingsByContainer";

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
    if (key.length == 0) {
        return NO;
    }
    if ([key hasPrefix:@"deviceSpoof"] || [key hasPrefix:@"enableSpoof"]) {
        return YES;
    }
    return [LCAddonScopedLegacyKeys() containsObject:key];
}

@implementation LCAppInfo

- (instancetype)initWithBundlePath:(NSString*)bundlePath {
    self = [super init];
    self.isShared = false;
	if(self) {
        _bundlePath = bundlePath;
        _infoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
        _info = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", bundlePath]];
        if(!_info) {
            _info = [[NSMutableDictionary alloc] init];
        }
        if(!_infoPlist) {
            _infoPlist = [[NSMutableDictionary alloc] init];
        }
        
        // migrate old appInfo
        if(_infoPlist[@"LCPatchRevision"] && [_info count] == 0) {
            NSArray* lcAppInfoKeys = @[
                @"LCPatchRevision",
                @"LCOrignalBundleIdentifier",
                @"LCDataUUID",
                @"LCTweakFolder",
                @"LCJITLessSignID",
                @"LCSelectedLanguage",
                @"LCExpirationDate",
                @"LCTeamId",
                @"isJITNeeded",
                @"isLocked",
                @"isHidden",
                @"doUseLCBundleId",
                @"doSymlinkInbox",
                @"bypassAssertBarrierOnQueue",
                @"signer",
                @"LCOrientationLock",
                @"cachedColor",
                @"LCContainers",
                @"hideLiveContainer",
                @"jitLaunchScriptJs"
            ];
            for(NSString* key in lcAppInfoKeys) {
                _info[key] = _infoPlist[key];
                [_infoPlist removeObjectForKey:key];
            }
            [_infoPlist writeBinToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
            [self save];
        }
        
        // fix bundle id and execName if crash when signing
        if (_infoPlist[@"LCBundleIdentifier"]) {
            _infoPlist[@"CFBundleExecutable"] = _infoPlist[@"LCBundleExecutable"];
            _infoPlist[@"CFBundleIdentifier"] = _infoPlist[@"LCBundleIdentifier"];
            [_infoPlist removeObjectForKey:@"LCBundleExecutable"];
            [_infoPlist removeObjectForKey:@"LCBundleIdentifier"];
            [_infoPlist writeBinToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
        }

        _autoSaveDisabled = false;
    }
    return self;
}

- (void)setBundlePath:(NSString*)newBundlePath {
    _bundlePath = newBundlePath;
}

- (NSMutableArray<NSString *>*)urlSchemes {
    // find all url schemes
    NSMutableArray* urlSchemes = [[NSMutableArray alloc] init];
    int nowSchemeCount = 0;
    if (_infoPlist[@"CFBundleURLTypes"]) {
        NSMutableArray* urlTypes = _infoPlist[@"CFBundleURLTypes"];

        for(int i = 0; i < [urlTypes count]; ++i) {
            NSMutableDictionary* nowUrlType = [urlTypes objectAtIndex:i];
            if (!nowUrlType[@"CFBundleURLSchemes"]){
                continue;
            }
            NSMutableArray *schemes = nowUrlType[@"CFBundleURLSchemes"];
            for(int j = 0; j < [schemes count]; ++j) {
                [urlSchemes insertObject:[schemes objectAtIndex:j] atIndex:nowSchemeCount];
                ++nowSchemeCount;
            }
        }
    }
    
    return urlSchemes;
}

- (NSString*)displayName {
    if (_infoPlist[@"CFBundleDisplayName"]) {
        return _infoPlist[@"CFBundleDisplayName"];
    } else if (_infoPlist[@"CFBundleName"]) {
        return _infoPlist[@"CFBundleName"];
    } else if (_infoPlist[@"CFBundleExecutable"]) {
        return _infoPlist[@"CFBundleExecutable"];
    } else {
        return @"App Corrupted, Please Reinstall This App";
    }
}

- (NSString*)version {
    NSString* version = _infoPlist[@"CFBundleShortVersionString"];
    if (!version) {
        version = _infoPlist[@"CFBundleVersion"];
    }
    if(version) {
        return version;
    } else {
        return @"Unknown";
    }
}

- (NSString*)bundleIdentifier {
    NSString* ans = nil;
    if([self doUseLCBundleId]) {
        ans = _info[@"LCOrignalBundleIdentifier"];
    } else {
        ans = _infoPlist[@"CFBundleIdentifier"];
    }
    if(ans) {
        return ans;
    } else {
        return @"Unknown";
    }
}

- (NSString*)dataUUID {
    return _info[@"LCDataUUID"];
}

- (NSString*)tweakFolder {
    return _info[@"LCTweakFolder"];
}

- (void)setDataUUID:(NSString *)uuid {
    _info[@"LCDataUUID"] = uuid;
    [self save];
}

- (void)setTweakFolder:(NSString *)tweakFolder {
    _info[@"LCTweakFolder"] = tweakFolder;
    [self save];
}

- (NSString*)selectedLanguage {
    return _info[@"LCSelectedLanguage"];
}

- (void)setSelectedLanguage:(NSString *)selectedLanguage {
    if([selectedLanguage isEqualToString: @""]) {
        _info[@"LCSelectedLanguage"] = nil;
    } else {
        _info[@"LCSelectedLanguage"] = selectedLanguage;
    }
    
    [self save];
}

- (NSString*)bundlePath {
    return _bundlePath;
}

- (NSMutableDictionary*)info {
    return _info;
}

- (UIImage*)iconIsDarkIcon:(BOOL)isDarkIcon {
    // if icon is already loaded in memory, return it
    if(_cachedIcon && !isDarkIcon) {
        return _cachedIcon;
    } else if (_cachedIconDark && isDarkIcon) {
        return _cachedIconDark;
    }
    
    // check if icon is cached on disk
    UIImage* uiIcon;
    NSString* cachedIconPath;
    if(isDarkIcon) {
        cachedIconPath = [_bundlePath stringByAppendingPathComponent:@"LCAppIconDark.png"];
    } else {
        cachedIconPath = [_bundlePath stringByAppendingPathComponent:@"LCAppIconLight.png"];
    }
    NSURL* cachedIconUrl = [NSURL fileURLWithPath:cachedIconPath];
    
    if([NSFileManager.defaultManager fileExistsAtPath:cachedIconPath]) {
        CGImageRef imageRef = loadCGImageFromURL(cachedIconUrl);
        uiIcon = [UIImage imageWithCGImage:imageRef];
    }
    
    // generate and save icon cache to disk
    if(!uiIcon) {
        uiIcon = [UIImage generateIconForBundleURL:[NSURL fileURLWithPath:_bundlePath] style:isDarkIcon hasBorder:YES];
        saveCGImage([uiIcon CGImage], cachedIconUrl);
    }
    
    // cache icon to memory
    if(isDarkIcon) {
        _cachedIconDark = uiIcon;
    } else {
        _cachedIcon = uiIcon;
    }

    return uiIcon;

}

- (void)clearIconCache {
    NSString* lightModeIconPath = [_bundlePath stringByAppendingPathComponent:@"LCAppIconLight.png"];
    NSString* darkModeIconPath = [_bundlePath stringByAppendingPathComponent:@"LCAppIconDark.png"];
    [NSFileManager.defaultManager removeItemAtPath:lightModeIconPath error:nil];
    [NSFileManager.defaultManager removeItemAtPath:darkModeIconPath error:nil];
    [self setCachedColor:nil];
    [self setCachedColorDark:nil];
    _cachedIcon = nil;
    _cachedIconDark = nil;
}

- (UIImage *)generateLiveContainerWrappedIconWithStyle:(GeneratedIconStyle)style {
    UIImage* icon = [UIImage generateIconForBundleURL:[NSURL fileURLWithPath:_bundlePath] style:style hasBorder:NO];
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"LCFrameShortcutIcons"]) {
        return icon;
    }

    UIImage *lcIcon = [UIImage imageNamed:@"AppIcon60x60@2x"];
    CGFloat iconXY = (lcIcon.size.width - 40) / 2;
    UIGraphicsBeginImageContextWithOptions(lcIcon.size, NO, 0.0);
    [lcIcon drawInRect:CGRectMake(0, 0, lcIcon.size.width, lcIcon.size.height)];
    CGRect rect = CGRectMake(iconXY, iconXY, 40, 40);
    [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:7] addClip];
    [icon drawInRect:rect];
    UIImage *newIcon = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newIcon;
}

- (NSDictionary *)generateWebClipConfigWithContainerId:(NSString*)containerId iconStyle:(GeneratedIconStyle)style{
    NSString* appClipUrl;
    if(containerId) {
        appClipUrl = [NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@&container-folder-name=%@", self.bundlePath.lastPathComponent, containerId];
    } else {
        appClipUrl = [NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@", self.bundlePath.lastPathComponent];
    }
    
    UIImage* icon = [self generateLiveContainerWrappedIconWithStyle:style];
    
    NSDictionary *payload = @{
        @"FullScreen": @YES,
        @"Icon": UIImagePNGRepresentation(icon),
        @"IgnoreManifestScope": @YES,
        @"IsRemovable": @YES,
        @"Label": self.displayName,
        @"PayloadDescription": [NSString stringWithFormat:@"Web Clip for launching %@ (%@) in LiveContainer", self.displayName, self.bundlePath.lastPathComponent],
        @"PayloadDisplayName": self.displayName,
        @"PayloadIdentifier": self.bundleIdentifier,
        @"PayloadType": @"com.apple.webClip.managed",
        @"PayloadUUID": NSUUID.UUID.UUIDString,
        @"PayloadVersion": @(1),
        @"Precomposed": @NO,
        @"toPayloadOrganization": @"LiveContainer",
        @"URL": appClipUrl
    };
    return @{
        @"ConsentText": @{
            @"default": [NSString stringWithFormat:@"This profile installs a web clip which opens %@ (%@) in LiveContainer", self.displayName, self.bundlePath.lastPathComponent]
        },
        @"PayloadContent": @[payload],
        @"PayloadDescription": payload[@"PayloadDescription"],
        @"PayloadDisplayName": self.displayName,
        @"PayloadIdentifier": self.bundleIdentifier,
        @"PayloadOrganization": @"LiveContainer",
        @"PayloadRemovalDisallowed": @(NO),
        @"PayloadType": @"Configuration",
        @"PayloadUUID": @"345097fb-d4f7-4a34-ab90-2e3f1ad62eed",
        @"PayloadVersion": @(1),
    };
}

- (NSString *)lcCurrentAddonContainerId {
    NSString *containerId = _info[@"LCDataUUID"];
    if ([containerId isKindOfClass:[NSString class]] && containerId.length > 0) {
        return containerId;
    }
    return nil;
}

- (NSMutableDictionary *)lcMutableAddonSettingsByContainer {
    id existing = _info[kLCAddonSettingsByContainerKey];
    NSMutableDictionary *mutable = nil;
    if ([existing isKindOfClass:[NSDictionary class]]) {
        mutable = [((NSDictionary *)existing) mutableCopy];
    }
    if (!mutable) {
        mutable = [NSMutableDictionary dictionary];
    }
    _info[kLCAddonSettingsByContainerKey] = mutable;
    return mutable;
}

- (NSDictionary *)lcCurrentContainerAddonSettings {
    NSString *containerId = self.lcCurrentAddonContainerId;
    if (containerId.length == 0) {
        return nil;
    }
    NSDictionary *settingsByContainer = _info[kLCAddonSettingsByContainerKey];
    if (![settingsByContainer isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id settings = settingsByContainer[containerId];
    return [settings isKindOfClass:[NSDictionary class]] ? settings : nil;
}

- (void)lcSyncAddonSettingsForContainer:(NSString *)containerId {
    if (containerId.length == 0) {
        return;
    }

    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *key in [_info allKeys]) {
        if (!LCIsContainerScopedAddonKey(key)) {
            continue;
        }
        id value = _info[key];
        if (value != nil) {
            settings[key] = value;
        }
    }

    NSMutableDictionary *settingsByContainer = self.lcMutableAddonSettingsByContainer;
    if (settings.count > 0) {
        settingsByContainer[containerId] = settings;
    } else {
        [settingsByContainer removeObjectForKey:containerId];
    }
}

- (void)saveAddonSettingsForContainer:(NSString *)containerId {
    [self lcSyncAddonSettingsForContainer:containerId];
    [self save];
}

- (void)loadAddonSettingsForContainer:(NSString *)containerId
          fallbackSpoofIdentifierForVendor:(BOOL)fallbackSpoofIdentifierForVendor
                           fallbackVendorID:(NSString *)fallbackVendorID {
    NSDictionary *settingsByContainer = _info[kLCAddonSettingsByContainerKey];
    NSDictionary *containerSettings = nil;
    if ([settingsByContainer isKindOfClass:[NSDictionary class]] && containerId.length > 0) {
        id settings = settingsByContainer[containerId];
        if ([settings isKindOfClass:[NSDictionary class]]) {
            containerSettings = settings;
        }
    }

    NSArray<NSString *> *existingKeys = [[_info allKeys] copy];
    for (NSString *key in existingKeys) {
        if (LCIsContainerScopedAddonKey(key)) {
            [_info removeObjectForKey:key];
        }
    }

    if (containerSettings) {
        [containerSettings enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (LCIsContainerScopedAddonKey(key) && value != nil && ![value isKindOfClass:[NSNull class]]) {
                _info[key] = value;
            }
        }];
    }

    BOOL spoofIDFV = fallbackSpoofIdentifierForVendor;
    id scopedSpoofIDFV = containerSettings[@"deviceSpoofIdentifiers"];
    if ([scopedSpoofIDFV respondsToSelector:@selector(boolValue)]) {
        spoofIDFV = [scopedSpoofIDFV boolValue];
    }
    _info[@"deviceSpoofIdentifiers"] = @(spoofIDFV);

    NSString *vendorID = @"";
    id scopedVendor = containerSettings[@"deviceSpoofVendorID"];
    if ([scopedVendor isKindOfClass:[NSString class]]) {
        vendorID = scopedVendor;
    } else if ([fallbackVendorID isKindOfClass:[NSString class]]) {
        vendorID = fallbackVendorID;
    }

    if (spoofIDFV) {
        if (vendorID.length == 0) {
            vendorID = [NSUUID UUID].UUIDString;
        }
        _info[@"deviceSpoofVendorID"] = vendorID;
    } else {
        [_info removeObjectForKey:@"deviceSpoofVendorID"];
    }
}

- (void)save {
    NSArray<NSString *> *deprecatedProxyKeys = @[
        @"spoofNetwork",
        @"proxyHost",
        @"proxyPort",
        @"proxyUsername",
        @"proxyPassword",
        @"proxyType",
        @"spoofNetworkMode"
    ];
    [_info removeObjectsForKeys:deprecatedProxyKeys];
    [self lcSyncAddonSettingsForContainer:self.lcCurrentAddonContainerId];

    if(!_autoSaveDisabled) {
        [_info writeBinToFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", _bundlePath] atomically:YES];
    }

        // Also save camera settings to guestAppInfo for hooks
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableDictionary *guestAppInfo = [[defaults objectForKey:@"guestAppInfo"] mutableCopy] ?: [@{} mutableCopy];
        
        guestAppInfo[@"hideLiveContainer"] = @(self.hideLiveContainer);

        // Keep camera values in guestAppInfo for hooks.
        guestAppInfo[@"spoofCamera"] = @(self.spoofCamera);
        guestAppInfo[@"spoofCameraVideoPath"] = self.spoofCameraVideoPath ?: @"";
        guestAppInfo[@"spoofCameraLoop"] = @(self.spoofCameraLoop);
        guestAppInfo[@"spoofCameraUseVideoAudio"] = @(self.spoofCameraUseVideoAudio);

        // Proxy configuration is retired: actively drop any legacy keys.
        [guestAppInfo removeObjectsForKeys:deprecatedProxyKeys];

        // SSL Addon
        guestAppInfo[@"bypassSSLPinning"] = @(self.bypassSSLPinning);

        [defaults setObject:guestAppInfo forKey:@"guestAppInfo"];
        [defaults synchronize];
        
        // Trigger UserDefaults change notification for hooks
        [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    }

- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(bool success, NSString* errorInfo))completetionHandler progressHandler:(void(^)(NSProgress* progress))progressHandler forceSign:(BOOL)forceSign {
    [NSUserDefaults.standardUserDefaults setObject:@(YES) forKey:@"SigningInProgress"];
    NSString *appPath = self.bundlePath;
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
    NSMutableDictionary *info = _info;
    NSMutableDictionary *infoPlist = _infoPlist;
    if (!info) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
        completetionHandler(NO, @"Info.plist not found");
        return;
    }
    NSFileManager* fm = NSFileManager.defaultManager;
    NSString *execPath = [NSString stringWithFormat:@"%@/%@", appPath, _infoPlist[@"CFBundleExecutable"]];
    
    // Update patch
    int currentPatchRev = 7;
    bool needPatch = [info[@"LCPatchRevision"] intValue] < currentPatchRev;
    if (needPatch || forceSign) {
        // copy-delete-move to avoid EXC_BAD_ACCESS (SIGKILL - CODESIGNING)
        NSString *backupPath = [NSString stringWithFormat:@"%@/%@_LiveContainerPatchBackUp", appPath, _infoPlist[@"CFBundleExecutable"]];
        NSError *err;
        [fm copyItemAtPath:execPath toPath:backupPath error:&err];
        [fm removeItemAtPath:execPath error:&err];
        [fm moveItemAtPath:backupPath toPath:execPath error:&err];
    }
    
    bool is32bit = false;
    if (needPatch) {
        __block bool has64bitSlice = NO;
        __block bool isEncrypted = false;
        NSString *error = LCParseMachO(execPath.UTF8String, false, ^(const char *path, struct mach_header_64 *header, int fd, void* filePtr) {
            if(header->cputype == CPU_TYPE_ARM64) {
                has64bitSlice |= YES;
                int patchResult = LCPatchExecSlice(path, header, ![self dontInjectTweakLoader]);
                if(patchResult & PATCH_EXEC_RESULT_NO_SPACE_FOR_TWEAKLOADER) {
                    info[@"LCTweakLoaderCantInject"] = @YES;
                    info[@"dontInjectTweakLoader"] = @YES;
                }
            }
            isEncrypted |= LCIsMachOEncrypted(header);
        });
        is32bit = !has64bitSlice;
        LCPatchAppBundleFixupARM64eSlice([NSURL fileURLWithPath:appPath]);
        if (isEncrypted) {
            error = @"The app you tried to install is encrypted. Please provide decrypted app.";
        }
        if (error) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
            completetionHandler(NO, error);
            return;
        }
        info[@"LCPatchRevision"] = @(currentPatchRev);
        forceSign = true;
        
        [self save];
    }
#if !is32BitSupported
    if(is32bit) {
        completetionHandler(NO, @"32-bit app is NOT supported!");
        return;
    }
#else
    self.is32Bit = is32bit;
#endif

    if (!LCSharedUtils.certificatePassword || is32bit || self.dontSign) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
        completetionHandler(YES, nil);
        return;
    }

    // check if iOS think this app's signature is valid, if so, we can skip any further signature check
    NSString* executablePath = [appPath stringByAppendingPathComponent:infoPlist[@"CFBundleExecutable"]];
    if(!forceSign) {
        bool signatureValid = checkCodeSignature(executablePath.UTF8String);
        
        if(signatureValid) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
            completetionHandler(YES, nil);
            return;
        }
    }
    
    if (!LCUtils.certificateData) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
        completetionHandler(NO, @"lc.signer.noCertificateFoundErr");
        return;
    }
    
    if(forceSign) {
        // remove ZSign cache since hash is changed after upgrading patch
        NSString* cachePath = [appPath stringByAppendingPathComponent:@"zsign_cache.json"];
        if([fm fileExistsAtPath:cachePath]) {
            NSError* err;
            [fm removeItemAtPath:cachePath error:&err];
        }
    }
    
    // Sign app if JIT-less is set up
        NSURL *appPathURL = [NSURL fileURLWithPath:appPath];
            // We need to temporarily fake bundle ID and main executable to sign properly
            NSString *tmpExecPath = [appPath stringByAppendingPathComponent:@"LiveContainer.tmp"];
            if (!info[@"LCBundleIdentifier"]) {
                // Don't let main executable get entitlements
                [fm copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];

                infoPlist[@"LCBundleExecutable"] = infoPlist[@"CFBundleExecutable"];
                infoPlist[@"LCBundleIdentifier"] = infoPlist[@"CFBundleIdentifier"];
                infoPlist[@"CFBundleExecutable"] = tmpExecPath.lastPathComponent;
                infoPlist[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
                [infoPlist writeBinToFile:infoPath atomically:YES];
            }
            infoPlist[@"CFBundleExecutable"] = infoPlist[@"LCBundleExecutable"];
            infoPlist[@"CFBundleIdentifier"] = infoPlist[@"LCBundleIdentifier"];
            [infoPlist removeObjectForKey:@"LCBundleExecutable"];
            [infoPlist removeObjectForKey:@"LCBundleIdentifier"];
            
            void (^signCompletionHandler)(BOOL success, NSError *error)  = ^(BOOL success, NSError *_Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    // Remove fake main executable
                    [fm removeItemAtPath:tmpExecPath error:nil];
                    
                    // Save sign ID and restore bundle ID
                    [self save];
                    [infoPlist writeBinToFile:infoPath atomically:YES];
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
                    if(!success) {
                        completetionHandler(NO, error.localizedDescription);
                    } else {
                        bool signatureValid = checkCodeSignature(executablePath.UTF8String);
                        if(signatureValid) {
                            completetionHandler(YES, [error localizedDescription]);
                        } else {
                            completetionHandler(NO, @"lc.signer.latestCertificateInvalidErr");
                        }
                    }
                    
                });
            };
            
            __block NSProgress *progress = [LCUtils signAppBundleWithZSign:appPathURL completionHandler:signCompletionHandler];

            if (progress) {
                progressHandler(progress);
            }

}

- (bool)isJITNeeded {
    if(_info[@"isJITNeeded"] != nil) {
        return [_info[@"isJITNeeded"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsJITNeeded:(bool)isJITNeeded {
    _info[@"isJITNeeded"] = [NSNumber numberWithBool:isJITNeeded];
    [self save];
    
}

- (bool)isLocked {
    if(_info[@"isLocked"] != nil) {
        return [_info[@"isLocked"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsLocked:(bool)isLocked {
    _info[@"isLocked"] = [NSNumber numberWithBool:isLocked];
    [self save];
    
}

- (bool)isHidden {
    if(_info[@"isHidden"] != nil) {
        return [_info[@"isHidden"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsHidden:(bool)isHidden {
    _info[@"isHidden"] = [NSNumber numberWithBool:isHidden];
    [self save];
    
}

- (bool)doSymlinkInbox {
    if(_info[@"doSymlinkInbox"] != nil) {
        return [_info[@"doSymlinkInbox"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDoSymlinkInbox:(bool)doSymlinkInbox {
    _info[@"doSymlinkInbox"] = [NSNumber numberWithBool:doSymlinkInbox];
    [self save];
    
}

- (bool)hideLiveContainer {
    if(_info[@"hideLiveContainer"] != nil) {
        return [_info[@"hideLiveContainer"] boolValue];
    } else {
        return YES; // default to YES
    }
}
- (void)setHideLiveContainer:(bool)hideLiveContainer {
    _info[@"hideLiveContainer"] = [NSNumber numberWithBool:hideLiveContainer];
    [self save];
}

- (bool)dontInjectTweakLoader {
    if(_info[@"dontInjectTweakLoader"] != nil) {
        return [_info[@"dontInjectTweakLoader"] boolValue];
    } else {
        return YES; // Changed from NO to YES - default to disabled injection
    }
}

- (void)setDontInjectTweakLoader:(bool)dontInjectTweakLoader {
    if([_info[@"dontInjectTweakLoader"] boolValue] == dontInjectTweakLoader) {
        return;
    }
    
    _info[@"dontInjectTweakLoader"] = [NSNumber numberWithBool:dontInjectTweakLoader];
    // we have to update patch to achieve this
    _info[@"LCPatchRevision"] = @(-1);
    [self save];
}

- (bool)dontLoadTweakLoader {
    if(_info[@"dontLoadTweakLoader"] != nil) {
        return [_info[@"dontLoadTweakLoader"] boolValue];
    } else {
        return YES; // Changed from NO to YES - default to disabled loading
    }
}

- (void)setDontLoadTweakLoader:(bool)dontLoadTweakLoader {
    _info[@"dontLoadTweakLoader"] = [NSNumber numberWithBool:dontLoadTweakLoader];
    [self save];
}

- (bool)doUseLCBundleId {
    if(_info[@"doUseLCBundleId"] != nil) {
        return [_info[@"doUseLCBundleId"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDoUseLCBundleId:(bool)doUseLCBundleId {
    _info[@"doUseLCBundleId"] = [NSNumber numberWithBool:doUseLCBundleId];
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", self.bundlePath];
    if(doUseLCBundleId) {
        _info[@"LCOrignalBundleIdentifier"] = _infoPlist[@"CFBundleIdentifier"];
        _infoPlist[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
    } else if (_info[@"LCOrignalBundleIdentifier"]) {
        _infoPlist[@"CFBundleIdentifier"] = _info[@"LCOrignalBundleIdentifier"];
        [_info removeObjectForKey:@"LCOrignalBundleIdentifier"];
    }
    [_infoPlist writeBinToFile:infoPath atomically:YES];
    [self save];
}

- (bool)fixFilePickerNew {
    if(_info[@"fixFilePickerNew"] != nil) {
        return [_info[@"fixFilePickerNew"] boolValue];
    } else {
        return NO;
    }
}

- (void)setFixFilePickerNew:(bool)fixFilePickerNew {
    _info[@"fixFilePickerNew"] = @(fixFilePickerNew);
    [self save];
}

- (bool)fixLocalNotification {
    if(_info[@"fixLocalNotification"] != nil) {
        return [_info[@"fixLocalNotification"] boolValue];
    } else {
        return NO;
    }
}

- (void)setFixLocalNotification:(bool)fixLocalNotification {
    _info[@"fixLocalNotification"] = @(fixLocalNotification);
    [self save];
}

- (LCOrientationLock)orientationLock {
    return (LCOrientationLock) [((NSNumber*) _info[@"LCOrientationLock"]) intValue];

}
- (void)setOrientationLock:(LCOrientationLock)orientationLock {
    _info[@"LCOrientationLock"] = [NSNumber numberWithInt:(int) orientationLock];
    [self save];
    
}

- (UIColor*)cachedColor {
    if(_info[@"cachedColor"] != nil) {
        NSData *colorData = _info[@"cachedColor"];
        NSError* error;
        UIColor *color = [NSKeyedUnarchiver unarchivedObjectOfClass:UIColor.class fromData:colorData error:&error];
        if (!error) {
            return color;
        } else {
            NSLog(@"[LC] failed to get color %@", error);
            return nil;
        }
    } else {
        return nil;
    }
}

- (void)setCachedColor:(UIColor*) color {
    if(color == nil) {
        _info[@"cachedColor"] = nil;
    } else {
        NSError* error;
        NSData *colorData = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:YES error:&error];
        [_info setObject:colorData forKey:@"cachedColor"];
        if(error) {
            NSLog(@"[LC] failed to set color %@", error);
        }

    }
    [self save];
}

- (UIColor*)cachedColorDark {
    if(_info[@"cachedColorDark"] != nil) {
        NSData *colorData = _info[@"cachedColorDark"];
        NSError* error;
        UIColor *color = [NSKeyedUnarchiver unarchivedObjectOfClass:UIColor.class fromData:colorData error:&error];
        if (!error) {
            return color;
        } else {
            NSLog(@"[LC] failed to get color %@", error);
            return nil;
        }
    } else {
        return nil;
    }
}

- (void)setCachedColorDark:(UIColor*)color {
    if(color == nil) {
        _info[@"cachedColorDark"] = nil;
    } else {
        NSError* error;
        NSData *colorData = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:YES error:&error];
        [_info setObject:colorData forKey:@"cachedColorDark"];
        if(error) {
            NSLog(@"[LC] failed to set color %@", error);
        }

    }
    [self save];
}

- (NSArray<NSDictionary*>* )containerInfo {
    return _info[@"LCContainers"];
}

- (void)setContainerInfo:(NSArray<NSDictionary *> *)containerInfo {
    _info[@"LCContainers"] = containerInfo;
    [self save];
}
#if is32BitSupported
- (bool)is32bit {
    if(_info[@"is32bit"] != nil) {
        return [_info[@"is32bit"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIs32bit:(bool)is32bit {
    _info[@"is32bit"] = [NSNumber numberWithBool:is32bit];
    [self save];
    
}
#endif
- (bool)dontSign {
    if(_info[@"dontSign"] != nil) {
        return [_info[@"dontSign"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDontSign:(bool)dontSign {
    _info[@"dontSign"] = [NSNumber numberWithBool:dontSign];
    [self save];
    
}

- (NSString *)jitLaunchScriptJs {
    return _info[@"jitLaunchScriptJs"];
}

- (void)setJitLaunchScriptJs:(NSString *)jitLaunchScriptJs {
    if (jitLaunchScriptJs.length > 0) {
        _info[@"jitLaunchScriptJs"] = jitLaunchScriptJs;
    } else {
        [_info removeObjectForKey:@"jitLaunchScriptJs"];
    }
    if (!_autoSaveDisabled) [self save];
}

- (bool)spoofSDKVersion {
    if(!_info[@"spoofSDKVersion"]) {
        return false;
    } else {
        return [_info[@"spoofSDKVersion"] unsignedIntValue] != 0;
    }
}

- (void)setSpoofSDKVersion:(bool)doSpoof {
    if(!doSpoof) {
        _info[@"spoofSDKVersion"] = 0;
    } else {
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", _bundlePath, _infoPlist[@"CFBundleExecutable"]];
        __block uint32_t sdkVersion = 0;
        LCParseMachO(execPath.UTF8String, true, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
            sdkVersion = dyld_get_sdk_version((const struct mach_header *)header);
        });
        NSLog(@"[LC] sdkversion = %8x", sdkVersion);
        _info[@"spoofSDKVersion"] = [NSNumber numberWithUnsignedInt:sdkVersion];
    }
    [self save];
}

// MARK: GPS Addon Section
- (bool)spoofGPS {
    if(_info[@"spoofGPS"] != nil) {
        return [_info[@"spoofGPS"] boolValue];
    } else {
        return NO;
    }
}
- (void)setSpoofGPS:(bool)spoofGPS {
    _info[@"spoofGPS"] = [NSNumber numberWithBool:spoofGPS];
    [self save];
}

- (CLLocationDegrees)spoofLatitude {
    if(_info[@"spoofLatitude"] != nil) {
        return [_info[@"spoofLatitude"] doubleValue];
    } else {
        return 37.7749;
    }
}
- (void)setSpoofLatitude:(CLLocationDegrees)spoofLatitude {
    _info[@"spoofLatitude"] = [NSNumber numberWithDouble:spoofLatitude];
    [self save];
}

- (CLLocationDegrees)spoofLongitude {
    if(_info[@"spoofLongitude"] != nil) {
        return [_info[@"spoofLongitude"] doubleValue];
    } else {
        return -122.4194;
    }
}
- (void)setSpoofLongitude:(CLLocationDegrees)spoofLongitude {
    _info[@"spoofLongitude"] = [NSNumber numberWithDouble:spoofLongitude];
    [self save];
}

- (CLLocationDistance)spoofAltitude {
    if(_info[@"spoofAltitude"] != nil) {
        return [_info[@"spoofAltitude"] doubleValue];
    } else {
        return 0.0;
    }
}
- (void)setSpoofAltitude:(CLLocationDistance)spoofAltitude {
    _info[@"spoofAltitude"] = [NSNumber numberWithDouble:spoofAltitude];
    [self save];
}

- (NSString*)spoofLocationName {
    NSString* locationName = _info[@"spoofLocationName"];
    if (locationName && [locationName isKindOfClass:[NSString class]]) {
        return locationName;
    } else {
        return @"";
    }
}

- (void)setSpoofLocationName:(NSString*)spoofLocationName {
    if (spoofLocationName && [spoofLocationName length] > 0) {
        _info[@"spoofLocationName"] = spoofLocationName;
    } else {
        _info[@"spoofLocationName"] = @"";
    }
    [self save];
}

// MARK: Camera Addon Section
- (bool)spoofCamera {
    if(_info[@"spoofCamera"] != nil) {
        return [_info[@"spoofCamera"] boolValue];
    } else {
        return NO;
    }
}
- (void)setSpoofCamera:(bool)spoofCamera {
    _info[@"spoofCamera"] = [NSNumber numberWithBool:spoofCamera];
    [self save];
}

- (NSString*)spoofCameraType {
    NSString* cameraType = _info[@"spoofCameraType"];
    if (cameraType && [cameraType isKindOfClass:[NSString class]]) {
        return cameraType;
    } else {
        return @"image";
    }
}
- (void)setSpoofCameraType:(NSString*)spoofCameraType {
    if (spoofCameraType && [spoofCameraType length] > 0) {
        _info[@"spoofCameraType"] = spoofCameraType;
    } else {
        _info[@"spoofCameraType"] = @"video";
    }
    [self save];
}

- (NSString*)spoofCameraImagePath {
    NSString* imagePath = _info[@"spoofCameraImagePath"];
    if (imagePath && [imagePath isKindOfClass:[NSString class]]) {
        return imagePath;
    } else {
        return @"";
    }
}
- (void)setSpoofCameraImagePath:(NSString*)spoofCameraImagePath {
    if (spoofCameraImagePath && [spoofCameraImagePath length] > 0) {
        _info[@"spoofCameraImagePath"] = spoofCameraImagePath;
    } else {
        _info[@"spoofCameraImagePath"] = @"";
    }
    [self save];
}

- (NSString*)spoofCameraVideoPath {
    NSString* videoPath = _info[@"spoofCameraVideoPath"];
    if (videoPath && [videoPath isKindOfClass:[NSString class]]) {
        return videoPath;
    } else {
        return @"";
    }
}
- (void)setSpoofCameraVideoPath:(NSString*)spoofCameraVideoPath {
    if (spoofCameraVideoPath && [spoofCameraVideoPath length] > 0) {
        _info[@"spoofCameraVideoPath"] = spoofCameraVideoPath;
    } else {
        _info[@"spoofCameraVideoPath"] = @"";
    }
    [self save];
}

- (bool)spoofCameraLoop {
    if(_info[@"spoofCameraLoop"] != nil) {
        return [_info[@"spoofCameraLoop"] boolValue];
    } else {
        return YES; // Default to looping
    }
}
- (void)setSpoofCameraLoop:(bool)spoofCameraLoop {
    _info[@"spoofCameraLoop"] = [NSNumber numberWithBool:spoofCameraLoop];
    [self save];
}

- (bool)spoofCameraUseVideoAudio {
    if (_info[@"spoofCameraUseVideoAudio"] != nil) {
        return [_info[@"spoofCameraUseVideoAudio"] boolValue];
    } else {
        return YES; // Default to replacing mic with spoofed video audio
    }
}

- (void)setSpoofCameraUseVideoAudio:(bool)spoofCameraUseVideoAudio {
    _info[@"spoofCameraUseVideoAudio"] = [NSNumber numberWithBool:spoofCameraUseVideoAudio];
    [self save];
}

// Mode 
- (NSString*)spoofCameraMode {
    NSString* cameraMode = _info[@"spoofCameraMode"];
    if (cameraMode && [cameraMode isKindOfClass:[NSString class]]) {
        return cameraMode;
    } else {
        return @"standard"; // Default mode
    }
}

- (void)setSpoofCameraMode:(NSString*)spoofCameraMode {
    _info[@"spoofCameraMode"] = spoofCameraMode ?: @"standard";
    [self save];
}

// MARK: Camera Transform Section

- (NSString*)spoofCameraTransformOrientation {
    NSString* orientation = _info[@"spoofCameraTransformOrientation"];
    if (orientation && [orientation isKindOfClass:[NSString class]]) {
        return orientation;
    } else {
        return @"none";
    }
}
- (void)setSpoofCameraTransformOrientation:(NSString*)spoofCameraTransformOrientation {
    _info[@"spoofCameraTransformOrientation"] = spoofCameraTransformOrientation ?: @"none";
    [self save];
}

- (NSString*)spoofCameraTransformScale {
    NSString* scale = _info[@"spoofCameraTransformScale"];
    if (scale && [scale isKindOfClass:[NSString class]]) {
        return scale;
    } else {
        return @"fit";
    }
}
- (void)setSpoofCameraTransformScale:(NSString*)spoofCameraTransformScale {
    _info[@"spoofCameraTransformScale"] = spoofCameraTransformScale ?: @"fit";
    [self save];
}

- (NSString*)spoofCameraTransformFlip {
    NSString* flip = _info[@"spoofCameraTransformFlip"];
    if (flip && [flip isKindOfClass:[NSString class]]) {
        return flip;
    } else {
        return @"none";
    }
}
- (void)setSpoofCameraTransformFlip:(NSString*)spoofCameraTransformFlip {
    _info[@"spoofCameraTransformFlip"] = spoofCameraTransformFlip ?: @"none";
    [self save];
}

// SSL Addon Section
- (bool)bypassSSLPinning {
    if(_info[@"bypassSSLPinning"] != nil) {
        return [_info[@"bypassSSLPinning"] boolValue];
    } else {
        return NO; // Default to disabled
    }
}

- (void)setBypassSSLPinning:(bool)bypassSSLPinning {
    _info[@"bypassSSLPinning"] = [NSNumber numberWithBool:bypassSSLPinning];
    [self save];
}

// MARK: UI Addon Section
- (NSDate*)lastLaunched {
    return _info[@"lastLaunched"];
}

- (void)setLastLaunched:(NSDate*)lastLaunched {
    _info[@"lastLaunched"] = lastLaunched;
    [self save];
}

- (NSDate*)installationDate {
    return _info[@"installationDate"];
}

- (void)setInstallationDate:(NSDate*)installationDate {
    _info[@"installationDate"] = installationDate;
    [self save];
}

// MARK: Device Addon Section
- (bool)deviceSpoofingEnabled {
    if(_info[@"deviceSpoofingEnabled"] != nil) {
        return [_info[@"deviceSpoofingEnabled"] boolValue];
    }
    return NO;
}

- (void)setDeviceSpoofingEnabled:(bool)enabled {
    _info[@"deviceSpoofingEnabled"] = [NSNumber numberWithBool:enabled];
    [self save];
}

- (NSString *)deviceSpoofProfile {
    return _info[@"deviceSpoofProfile"];
}

- (void)setDeviceSpoofProfile:(NSString *)profile {
    if (profile) {
        _info[@"deviceSpoofProfile"] = profile;
    } else {
        [_info removeObjectForKey:@"deviceSpoofProfile"];
    }
    [self save];
}

// MARK: - Device Spoofing Per-Feature Toggles (Ghost-style)

- (NSString *)deviceSpoofCustomVersion {
    return _info[@"deviceSpoofCustomVersion"];
}

- (void)setDeviceSpoofCustomVersion:(NSString *)version {
    if (version.length > 0) {
        _info[@"deviceSpoofCustomVersion"] = version;
    } else {
        [_info removeObjectForKey:@"deviceSpoofCustomVersion"];
    }
    [self save];
}

- (bool)deviceSpoofDeviceName {
    return [_info[@"deviceSpoofDeviceName"] boolValue];
}

- (void)setDeviceSpoofDeviceName:(bool)enabled {
    _info[@"deviceSpoofDeviceName"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofDeviceNameValue {
    return _info[@"deviceSpoofDeviceNameValue"] ?: @"iPhone";
}

- (void)setDeviceSpoofDeviceNameValue:(NSString *)name {
    if (name.length > 0) {
        _info[@"deviceSpoofDeviceNameValue"] = name;
    } else {
        [_info removeObjectForKey:@"deviceSpoofDeviceNameValue"];
    }
    [self save];
}

- (bool)deviceSpoofCarrier {
    return [_info[@"deviceSpoofCarrier"] boolValue];
}

- (void)setDeviceSpoofCarrier:(bool)enabled {
    _info[@"deviceSpoofCarrier"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofCarrierName {
    return _info[@"deviceSpoofCarrierName"] ?: @"Verizon";
}

- (void)setDeviceSpoofCarrierName:(NSString *)carrier {
    if (carrier.length > 0) {
        _info[@"deviceSpoofCarrierName"] = carrier;
    } else {
        [_info removeObjectForKey:@"deviceSpoofCarrierName"];
    }
    [self save];
}

- (NSString *)deviceSpoofMCC {
    return _info[@"deviceSpoofMCC"] ?: @"311";
}

- (void)setDeviceSpoofMCC:(NSString *)mcc {
    if (mcc.length > 0) {
        _info[@"deviceSpoofMCC"] = mcc;
    } else {
        [_info removeObjectForKey:@"deviceSpoofMCC"];
    }
    [self save];
}

- (NSString *)deviceSpoofMNC {
    return _info[@"deviceSpoofMNC"] ?: @"480";
}

- (void)setDeviceSpoofMNC:(NSString *)mnc {
    if (mnc.length > 0) {
        _info[@"deviceSpoofMNC"] = mnc;
    } else {
        [_info removeObjectForKey:@"deviceSpoofMNC"];
    }
    [self save];
}

- (NSString *)deviceSpoofCarrierCountry {
    return _info[@"deviceSpoofCarrierCountry"] ?: @"us";
}

- (void)setDeviceSpoofCarrierCountry:(NSString *)country {
    if (country.length > 0) {
        _info[@"deviceSpoofCarrierCountry"] = country;
    } else {
        [_info removeObjectForKey:@"deviceSpoofCarrierCountry"];
    }
    [self save];
}

- (bool)deviceSpoofIdentifiers {
    return [_info[@"deviceSpoofIdentifiers"] boolValue];
}

- (void)setDeviceSpoofIdentifiers:(bool)enabled {
    _info[@"deviceSpoofIdentifiers"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofVendorID {
    return _info[@"deviceSpoofVendorID"];
}

- (void)setDeviceSpoofVendorID:(NSString *)vendorID {
    if (vendorID.length > 0) {
        _info[@"deviceSpoofVendorID"] = vendorID;
    } else {
        [_info removeObjectForKey:@"deviceSpoofVendorID"];
    }
    [self save];
}

- (NSString *)deviceSpoofAdvertisingID {
    return _info[@"deviceSpoofAdvertisingID"];
}

- (void)setDeviceSpoofAdvertisingID:(NSString *)advertisingID {
    if (advertisingID.length > 0) {
        _info[@"deviceSpoofAdvertisingID"] = advertisingID;
    } else {
        [_info removeObjectForKey:@"deviceSpoofAdvertisingID"];
    }
    [self save];
}

- (NSString *)deviceSpoofAdTrackingMode {
    NSString *mode = _info[@"deviceSpoofAdTrackingMode"];
    if ([mode isKindOfClass:[NSString class]] && mode.length > 0) {
        return mode;
    }
    return @"auto";
}

- (void)setDeviceSpoofAdTrackingMode:(NSString *)mode {
    NSString *normalized = [mode isKindOfClass:[NSString class]] ? [(NSString *)mode lowercaseString] : @"";
    if (normalized.length == 0 || [normalized isEqualToString:@"auto"]) {
        [_info removeObjectForKey:@"deviceSpoofAdTrackingMode"];
    } else {
        _info[@"deviceSpoofAdTrackingMode"] = normalized;
    }
    [self save];
}

- (NSString *)deviceSpoofPersistentDeviceID {
    NSString *value = _info[@"deviceSpoofPersistentDeviceID"];
    if (value.length > 0) {
        return value;
    }
    value = _info[@"persistentDeviceID"];
    if (value.length > 0) {
        return value;
    }
    value = _info[@"deviceID"];
    return value.length > 0 ? value : @"";
}

- (void)setDeviceSpoofPersistentDeviceID:(NSString *)persistentDeviceID {
    if (persistentDeviceID.length > 0) {
        _info[@"deviceSpoofPersistentDeviceID"] = persistentDeviceID;
    } else {
        [_info removeObjectForKey:@"deviceSpoofPersistentDeviceID"];
    }
    [self save];
}

- (NSString *)deviceSpoofInstallationID {
    return _info[@"deviceSpoofInstallationID"] ?: @"";
}

- (void)setDeviceSpoofInstallationID:(NSString *)installationID {
    if (installationID.length > 0) {
        _info[@"deviceSpoofInstallationID"] = installationID;
    } else {
        [_info removeObjectForKey:@"deviceSpoofInstallationID"];
    }
    [self save];
}

- (bool)deviceSpoofSecurityEnabled {
    if (_info[@"deviceSpoofSecurityEnabled"] != nil) {
        return [_info[@"deviceSpoofSecurityEnabled"] boolValue];
    }
    return YES;
}

- (void)setDeviceSpoofSecurityEnabled:(bool)enabled {
    _info[@"deviceSpoofSecurityEnabled"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofCloudToken {
    if (_info[@"deviceSpoofCloudToken"] != nil) {
        return [_info[@"deviceSpoofCloudToken"] boolValue];
    }
    if (_info[@"enableSpoofCloudToken"] != nil) {
        return [_info[@"enableSpoofCloudToken"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setDeviceSpoofCloudToken:(bool)enabled {
    _info[@"deviceSpoofCloudToken"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofDeviceChecker {
    if (_info[@"deviceSpoofDeviceChecker"] != nil) {
        return [_info[@"deviceSpoofDeviceChecker"] boolValue];
    }
    if (_info[@"enableSpoofDeviceChecker"] != nil) {
        return [_info[@"enableSpoofDeviceChecker"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setDeviceSpoofDeviceChecker:(bool)enabled {
    _info[@"deviceSpoofDeviceChecker"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofAppAttest {
    if (_info[@"deviceSpoofAppAttest"] != nil) {
        return [_info[@"deviceSpoofAppAttest"] boolValue];
    }
    if (_info[@"enableSpoofAppAttest"] != nil) {
        return [_info[@"enableSpoofAppAttest"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setDeviceSpoofAppAttest:(bool)enabled {
    _info[@"deviceSpoofAppAttest"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofSiriPrivacyProtection {
    if (_info[@"deviceSpoofSiriPrivacyProtection"] != nil) {
        return [_info[@"deviceSpoofSiriPrivacyProtection"] boolValue];
    }
    return NO;
}

- (void)setDeviceSpoofSiriPrivacyProtection:(bool)enabled {
    _info[@"deviceSpoofSiriPrivacyProtection"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofTimezone {
    return [_info[@"deviceSpoofTimezone"] boolValue];
}

- (void)setDeviceSpoofTimezone:(bool)enabled {
    _info[@"deviceSpoofTimezone"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofTimezoneValue {
    return _info[@"deviceSpoofTimezoneValue"] ?: @"America/New_York";
}

- (void)setDeviceSpoofTimezoneValue:(NSString *)timezone {
    if (timezone.length > 0) {
        _info[@"deviceSpoofTimezoneValue"] = timezone;
    } else {
        [_info removeObjectForKey:@"deviceSpoofTimezoneValue"];
    }
    [self save];
}

- (bool)deviceSpoofLocale {
    return [_info[@"deviceSpoofLocale"] boolValue];
}

- (void)setDeviceSpoofLocale:(bool)enabled {
    _info[@"deviceSpoofLocale"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofLocaleValue {
    return _info[@"deviceSpoofLocaleValue"] ?: @"en_US";
}

- (void)setDeviceSpoofLocaleValue:(NSString *)locale {
    if (locale.length > 0) {
        _info[@"deviceSpoofLocaleValue"] = locale;
    } else {
        [_info removeObjectForKey:@"deviceSpoofLocaleValue"];
    }
    [self save];
}

- (NSString *)deviceSpoofLocaleCurrencyCode {
    NSString *value = _info[@"deviceSpoofLocaleCurrencyCode"];
    if (value.length > 0) {
        return value;
    }
    value = _info[@"localeCurrencyCode"];
    return value.length > 0 ? value : @"";
}

- (void)setDeviceSpoofLocaleCurrencyCode:(NSString *)currencyCode {
    if (currencyCode.length > 0) {
        _info[@"deviceSpoofLocaleCurrencyCode"] = currencyCode;
    } else {
        [_info removeObjectForKey:@"deviceSpoofLocaleCurrencyCode"];
    }
    [self save];
}

- (NSString *)deviceSpoofLocaleCurrencySymbol {
    NSString *value = _info[@"deviceSpoofLocaleCurrencySymbol"];
    if (value.length > 0) {
        return value;
    }
    value = _info[@"localeCurrencySymbol"];
    return value.length > 0 ? value : @"";
}

- (void)setDeviceSpoofLocaleCurrencySymbol:(NSString *)currencySymbol {
    if (currencySymbol.length > 0) {
        _info[@"deviceSpoofLocaleCurrencySymbol"] = currencySymbol;
    } else {
        [_info removeObjectForKey:@"deviceSpoofLocaleCurrencySymbol"];
    }
    [self save];
}

- (NSString *)deviceSpoofPreferredCountry {
    NSString *country = _info[@"deviceSpoofPreferredCountry"];
    if (country.length > 0) {
        return country;
    }
    country = _info[@"localeCountryCode"];
    if (country.length > 0) {
        return country;
    }
    return @"";
}

- (void)setDeviceSpoofPreferredCountry:(NSString *)country {
    if (country.length > 0) {
        _info[@"deviceSpoofPreferredCountry"] = country;
    } else {
        [_info removeObjectForKey:@"deviceSpoofPreferredCountry"];
    }
    [self save];
}

- (bool)deviceSpoofCellularTypeEnabled {
    if (_info[@"deviceSpoofCellularTypeEnabled"] != nil) {
        return [_info[@"deviceSpoofCellularTypeEnabled"] boolValue];
    }
    if (_info[@"enableSpoofCellularType"] != nil) {
        return [_info[@"enableSpoofCellularType"] boolValue];
    }
    if (_info[@"deviceSpoofCellularType"] != nil || _info[@"cellularType"] != nil) {
        return YES;
    }
    return NO;
}

- (void)setDeviceSpoofCellularTypeEnabled:(bool)enabled {
    _info[@"deviceSpoofCellularTypeEnabled"] = @(enabled);
    [self save];
}

- (int)deviceSpoofCellularType {
    if (_info[@"deviceSpoofCellularType"] != nil) {
        return [_info[@"deviceSpoofCellularType"] intValue];
    }
    if (_info[@"cellularType"] != nil) {
        return [_info[@"cellularType"] intValue];
    }
    return 0;
}

- (void)setDeviceSpoofCellularType:(int)type {
    _info[@"deviceSpoofCellularType"] = @(type);
    [self save];
}

- (bool)deviceSpoofNetworkInfo {
    if (_info[@"deviceSpoofNetworkInfo"] != nil) {
        return [_info[@"deviceSpoofNetworkInfo"] boolValue];
    }
    if (_info[@"enableSpoofNetworkInfo"] != nil) {
        return [_info[@"enableSpoofNetworkInfo"] boolValue];
    }
    return NO;
}

- (void)setDeviceSpoofNetworkInfo:(bool)enabled {
    _info[@"deviceSpoofNetworkInfo"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofWiFiAddressEnabled {
    if (_info[@"deviceSpoofWiFiAddressEnabled"] != nil) {
        return [_info[@"deviceSpoofWiFiAddressEnabled"] boolValue];
    }
    if (_info[@"enableSpoofWiFi"] != nil) {
        return [_info[@"enableSpoofWiFi"] boolValue];
    }
    return NO;
}

- (void)setDeviceSpoofWiFiAddressEnabled:(bool)enabled {
    _info[@"deviceSpoofWiFiAddressEnabled"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofCellularAddressEnabled {
    if (_info[@"deviceSpoofCellularAddressEnabled"] != nil) {
        return [_info[@"deviceSpoofCellularAddressEnabled"] boolValue];
    }
    if (_info[@"enableSpoofCellular"] != nil) {
        return [_info[@"enableSpoofCellular"] boolValue];
    }
    return NO;
}

- (void)setDeviceSpoofCellularAddressEnabled:(bool)enabled {
    _info[@"deviceSpoofCellularAddressEnabled"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofMACAddressEnabled {
    if (_info[@"deviceSpoofMACAddressEnabled"] != nil) {
        return [_info[@"deviceSpoofMACAddressEnabled"] boolValue];
    }
    NSString *mac = _info[@"deviceSpoofMACAddress"];
    if ([mac isKindOfClass:[NSString class]] && mac.length > 0) {
        return YES;
    }
    return NO;
}

- (void)setDeviceSpoofMACAddressEnabled:(bool)enabled {
    _info[@"deviceSpoofMACAddressEnabled"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofWiFiAddress {
    NSString *addr = _info[@"deviceSpoofWiFiAddress"];
    if (addr.length > 0) {
        return addr;
    }
    addr = _info[@"wifiAddress"];
    return addr.length > 0 ? addr : @"";
}

- (void)setDeviceSpoofWiFiAddress:(NSString *)address {
    if (address.length > 0) {
        _info[@"deviceSpoofWiFiAddress"] = address;
    } else {
        [_info removeObjectForKey:@"deviceSpoofWiFiAddress"];
    }
    [self save];
}

- (NSString *)deviceSpoofCellularAddress {
    NSString *addr = _info[@"deviceSpoofCellularAddress"];
    if (addr.length > 0) {
        return addr;
    }
    addr = _info[@"cellularAddress"];
    return addr.length > 0 ? addr : @"";
}

- (void)setDeviceSpoofCellularAddress:(NSString *)address {
    if (address.length > 0) {
        _info[@"deviceSpoofCellularAddress"] = address;
    } else {
        [_info removeObjectForKey:@"deviceSpoofCellularAddress"];
    }
    [self save];
}

- (NSString *)deviceSpoofWiFiSSID {
    NSString *ssid = _info[@"deviceSpoofWiFiSSID"];
    if (ssid.length > 0) {
        return ssid;
    }
    ssid = _info[@"wifiSSID"];
    return ssid.length > 0 ? ssid : @"Public Network";
}

- (void)setDeviceSpoofWiFiSSID:(NSString *)ssid {
    if (ssid.length > 0) {
        _info[@"deviceSpoofWiFiSSID"] = ssid;
    } else {
        [_info removeObjectForKey:@"deviceSpoofWiFiSSID"];
    }
    [self save];
}

- (NSString *)deviceSpoofWiFiBSSID {
    NSString *bssid = _info[@"deviceSpoofWiFiBSSID"];
    if (bssid.length > 0) {
        return bssid;
    }
    bssid = _info[@"wifiBSSID"];
    return bssid.length > 0 ? bssid : @"22:66:99:00";
}

- (void)setDeviceSpoofWiFiBSSID:(NSString *)bssid {
    if (bssid.length > 0) {
        _info[@"deviceSpoofWiFiBSSID"] = bssid;
    } else {
        [_info removeObjectForKey:@"deviceSpoofWiFiBSSID"];
    }
    [self save];
}

- (NSString *)deviceSpoofMACAddress {
    return _info[@"deviceSpoofMACAddress"] ?: @"";
}

- (void)setDeviceSpoofMACAddress:(NSString *)macAddress {
    if (macAddress.length > 0) {
        _info[@"deviceSpoofMACAddress"] = macAddress;
    } else {
        [_info removeObjectForKey:@"deviceSpoofMACAddress"];
    }
    [self save];
}

- (bool)deviceSpoofCanvasFingerprintProtection {
    if (_info[@"deviceSpoofCanvasFingerprintProtection"] != nil) {
        return [_info[@"deviceSpoofCanvasFingerprintProtection"] boolValue];
    }
    return YES;
}

- (void)setDeviceSpoofCanvasFingerprintProtection:(bool)enabled {
    _info[@"deviceSpoofCanvasFingerprintProtection"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofScreenCapture {
    if (_info[@"deviceSpoofScreenCapture"] != nil) {
        return [_info[@"deviceSpoofScreenCapture"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setDeviceSpoofScreenCapture:(bool)enabled {
    _info[@"deviceSpoofScreenCapture"] = @(enabled);
    [self save];
}

- (bool)enableSpoofMessage {
    if (_info[@"enableSpoofMessage"] != nil) {
        return [_info[@"enableSpoofMessage"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setEnableSpoofMessage:(bool)enabled {
    _info[@"enableSpoofMessage"] = @(enabled);
    [self save];
}

- (bool)enableSpoofMail {
    if (_info[@"enableSpoofMail"] != nil) {
        return [_info[@"enableSpoofMail"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setEnableSpoofMail:(bool)enabled {
    _info[@"enableSpoofMail"] = @(enabled);
    [self save];
}

- (bool)enableSpoofBugsnag {
    if (_info[@"enableSpoofBugsnag"] != nil) {
        return [_info[@"enableSpoofBugsnag"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setEnableSpoofBugsnag:(bool)enabled {
    _info[@"enableSpoofBugsnag"] = @(enabled);
    [self save];
}

- (bool)enableSpoofCrane {
    if (_info[@"enableSpoofCrane"] != nil) {
        return [_info[@"enableSpoofCrane"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setEnableSpoofCrane:(bool)enabled {
    _info[@"enableSpoofCrane"] = @(enabled);
    [self save];
}

- (bool)enableSpoofPasteboard {
    if (_info[@"enableSpoofPasteboard"] != nil) {
        return [_info[@"enableSpoofPasteboard"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setEnableSpoofPasteboard:(bool)enabled {
    _info[@"enableSpoofPasteboard"] = @(enabled);
    [self save];
}

- (bool)enableSpoofAlbum {
    if (_info[@"enableSpoofAlbum"] != nil) {
        return [_info[@"enableSpoofAlbum"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setEnableSpoofAlbum:(bool)enabled {
    _info[@"enableSpoofAlbum"] = @(enabled);
    [self save];
}

- (bool)enableSpoofAppium {
    if (_info[@"enableSpoofAppium"] != nil) {
        return [_info[@"enableSpoofAppium"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setEnableSpoofAppium:(bool)enabled {
    _info[@"enableSpoofAppium"] = @(enabled);
    [self save];
}

- (bool)enableSpoofKeyboard {
    if (_info[@"enableSpoofKeyboard"] != nil) {
        return [_info[@"enableSpoofKeyboard"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setEnableSpoofKeyboard:(bool)enabled {
    _info[@"enableSpoofKeyboard"] = @(enabled);
    [self save];
}

- (bool)enableSpoofUserDefaults {
    if (_info[@"enableSpoofUserDefaults"] != nil) {
        return [_info[@"enableSpoofUserDefaults"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setEnableSpoofUserDefaults:(bool)enabled {
    _info[@"enableSpoofUserDefaults"] = @(enabled);
    [self save];
}

- (bool)enableSpoofEntitlements {
    if (_info[@"enableSpoofEntitlements"] != nil) {
        return [_info[@"enableSpoofEntitlements"] boolValue];
    }
    if (_info[@"deviceSpoofEntitlements"] != nil) {
        return [_info[@"deviceSpoofEntitlements"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setEnableSpoofEntitlements:(bool)enabled {
    _info[@"enableSpoofEntitlements"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofFileTimestamps {
    if (_info[@"deviceSpoofFileTimestamps"] != nil) {
        return [_info[@"deviceSpoofFileTimestamps"] boolValue];
    }
    if (_info[@"enableSpoofFileTimestamps"] != nil) {
        return [_info[@"enableSpoofFileTimestamps"] boolValue];
    }
    return self.deviceSpoofSecurityEnabled;
}

- (void)setDeviceSpoofFileTimestamps:(bool)enabled {
    _info[@"deviceSpoofFileTimestamps"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofProximity {
    if (_info[@"deviceSpoofProximity"] != nil) {
        return [_info[@"deviceSpoofProximity"] boolValue];
    }
    if (_info[@"enableSpoofProximity"] != nil) {
        return [_info[@"enableSpoofProximity"] boolValue];
    }
    return NO;
}

- (void)setDeviceSpoofProximity:(bool)enabled {
    _info[@"deviceSpoofProximity"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofOrientation {
    if (_info[@"deviceSpoofOrientation"] != nil) {
        return [_info[@"deviceSpoofOrientation"] boolValue];
    }
    if (_info[@"enableSpoofOrientation"] != nil) {
        return [_info[@"enableSpoofOrientation"] boolValue];
    }
    return NO;
}

- (void)setDeviceSpoofOrientation:(bool)enabled {
    _info[@"deviceSpoofOrientation"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofGyroscope {
    if (_info[@"deviceSpoofGyroscope"] != nil) {
        return [_info[@"deviceSpoofGyroscope"] boolValue];
    }
    if (_info[@"enableSpoofGyroscope"] != nil) {
        return [_info[@"enableSpoofGyroscope"] boolValue];
    }
    return NO;
}

- (void)setDeviceSpoofGyroscope:(bool)enabled {
    _info[@"deviceSpoofGyroscope"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofProcessorEnabled {
    if (_info[@"deviceSpoofProcessorEnabled"] != nil) {
        return [_info[@"deviceSpoofProcessorEnabled"] boolValue];
    }
    if (_info[@"enableSpoofProcessor"] != nil) {
        return [_info[@"enableSpoofProcessor"] boolValue];
    }
    if (_info[@"deviceSpoofProcessorCount"] != nil || _info[@"processorCount"] != nil) {
        return YES;
    }
    return NO;
}

- (void)setDeviceSpoofProcessorEnabled:(bool)enabled {
    _info[@"deviceSpoofProcessorEnabled"] = @(enabled);
    [self save];
}

- (int)deviceSpoofProcessorCount {
    id value = _info[@"deviceSpoofProcessorCount"];
    if (value == nil) {
        value = _info[@"processorCount"];
    }
    if ([value respondsToSelector:@selector(intValue)]) {
        return [value intValue];
    }
    return 6;
}

- (void)setDeviceSpoofProcessorCount:(int)count {
    _info[@"deviceSpoofProcessorCount"] = @(count);
    [self save];
}

- (bool)deviceSpoofMemoryEnabled {
    if (_info[@"deviceSpoofMemoryEnabled"] != nil) {
        return [_info[@"deviceSpoofMemoryEnabled"] boolValue];
    }
    if (_info[@"enableSpoofMemory"] != nil) {
        return [_info[@"enableSpoofMemory"] boolValue];
    }
    if (_info[@"deviceSpoofMemoryCount"] != nil || _info[@"memoryCount"] != nil) {
        return YES;
    }
    return NO;
}

- (void)setDeviceSpoofMemoryEnabled:(bool)enabled {
    _info[@"deviceSpoofMemoryEnabled"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofMemoryCount {
    id value = _info[@"deviceSpoofMemoryCount"];
    if (value == nil) {
        value = _info[@"memoryCount"];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }
    return @"8";
}

- (void)setDeviceSpoofMemoryCount:(NSString *)count {
    if (count.length > 0) {
        _info[@"deviceSpoofMemoryCount"] = count;
    } else {
        [_info removeObjectForKey:@"deviceSpoofMemoryCount"];
    }
    [self save];
}

- (bool)deviceSpoofKernelVersionEnabled {
    if (_info[@"deviceSpoofKernelVersionEnabled"] != nil) {
        return [_info[@"deviceSpoofKernelVersionEnabled"] boolValue];
    }
    if (_info[@"enableSpoofKernelVersion"] != nil) {
        return [_info[@"enableSpoofKernelVersion"] boolValue];
    }
    if (_info[@"deviceSpoofKernelVersion"] != nil ||
        _info[@"kernelVersion"] != nil ||
        _info[@"selectedKernelVersion"] != nil ||
        _info[@"deviceSpoofKernelRelease"] != nil ||
        _info[@"kernelVersionDarwin"] != nil) {
        return YES;
    }
    return NO;
}

- (void)setDeviceSpoofKernelVersionEnabled:(bool)enabled {
    _info[@"deviceSpoofKernelVersionEnabled"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofKernelVersion {
    NSString *value = _info[@"deviceSpoofKernelVersion"];
    if (value.length > 0) {
        return value;
    }
    value = _info[@"kernelVersion"];
    if (value.length > 0) {
        return value;
    }
    value = _info[@"selectedKernelVersion"];
    return value.length > 0 ? value : @"";
}

- (void)setDeviceSpoofKernelVersion:(NSString *)kernelVersion {
    if (kernelVersion.length > 0) {
        _info[@"deviceSpoofKernelVersion"] = kernelVersion;
    } else {
        [_info removeObjectForKey:@"deviceSpoofKernelVersion"];
    }
    [self save];
}

- (NSString *)deviceSpoofKernelRelease {
    NSString *value = _info[@"deviceSpoofKernelRelease"];
    if (value.length > 0) {
        return value;
    }
    value = _info[@"kernelVersionDarwin"];
    return value.length > 0 ? value : @"";
}

- (void)setDeviceSpoofKernelRelease:(NSString *)kernelRelease {
    if (kernelRelease.length > 0) {
        _info[@"deviceSpoofKernelRelease"] = kernelRelease;
    } else {
        [_info removeObjectForKey:@"deviceSpoofKernelRelease"];
    }
    [self save];
}

- (NSString *)deviceSpoofBuildVersion {
    NSString *value = _info[@"deviceSpoofBuildVersion"];
    if (value.length > 0) {
        return value;
    }
    value = _info[@"iosVersionBuild"];
    return value.length > 0 ? value : @"";
}

- (void)setDeviceSpoofBuildVersion:(NSString *)buildVersion {
    if (buildVersion.length > 0) {
        _info[@"deviceSpoofBuildVersion"] = buildVersion;
    } else {
        [_info removeObjectForKey:@"deviceSpoofBuildVersion"];
    }
    [self save];
}

- (NSArray<NSString *> *)deviceSpoofAlbumBlacklist {
    id blacklist = _info[@"deviceSpoofAlbumBlacklist"];
    if ([blacklist isKindOfClass:[NSArray class]]) {
        return blacklist;
    }
    blacklist = _info[@"albumBlacklistArray"];
    if ([blacklist isKindOfClass:[NSArray class]]) {
        return blacklist;
    }
    return @[];
}

- (void)setDeviceSpoofAlbumBlacklist:(NSArray<NSString *> *)blacklist {
    if ([blacklist isKindOfClass:[NSArray class]] && blacklist.count > 0) {
        _info[@"deviceSpoofAlbumBlacklist"] = blacklist;
    } else {
        [_info removeObjectForKey:@"deviceSpoofAlbumBlacklist"];
    }
    [self save];
}

// MARK: - Extended Spoofing (Ghost + Project-X parity)

- (bool)deviceSpoofBootTime {
    return [_info[@"deviceSpoofBootTime"] boolValue];
}
- (void)setDeviceSpoofBootTime:(bool)enabled {
    _info[@"deviceSpoofBootTime"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofBootTimeRange {
    return _info[@"deviceSpoofBootTimeRange"] ?: @"medium";
}
- (void)setDeviceSpoofBootTimeRange:(NSString *)range {
    if (range.length > 0) {
        _info[@"deviceSpoofBootTimeRange"] = range;
    } else {
        [_info removeObjectForKey:@"deviceSpoofBootTimeRange"];
    }
    [self save];
}

- (bool)deviceSpoofBootTimeRandomize {
    if (_info[@"deviceSpoofBootTimeRandomize"] != nil) {
        return [_info[@"deviceSpoofBootTimeRandomize"] boolValue];
    }
    return YES;
}
- (void)setDeviceSpoofBootTimeRandomize:(bool)enabled {
    _info[@"deviceSpoofBootTimeRandomize"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofUserAgent {
    return [_info[@"deviceSpoofUserAgent"] boolValue];
}
- (void)setDeviceSpoofUserAgent:(bool)enabled {
    _info[@"deviceSpoofUserAgent"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofUserAgentValue {
    return _info[@"deviceSpoofUserAgentValue"];
}
- (void)setDeviceSpoofUserAgentValue:(NSString *)ua {
    if (ua.length > 0) {
        _info[@"deviceSpoofUserAgentValue"] = ua;
    } else {
        [_info removeObjectForKey:@"deviceSpoofUserAgentValue"];
    }
    [self save];
}

- (bool)deviceSpoofBattery {
    return [_info[@"deviceSpoofBattery"] boolValue];
}
- (void)setDeviceSpoofBattery:(bool)enabled {
    _info[@"deviceSpoofBattery"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofBatteryRandomize {
    if (_info[@"deviceSpoofBatteryRandomize"] != nil) {
        return [_info[@"deviceSpoofBatteryRandomize"] boolValue];
    }
    return YES;
}
- (void)setDeviceSpoofBatteryRandomize:(bool)enabled {
    _info[@"deviceSpoofBatteryRandomize"] = @(enabled);
    [self save];
}

- (float)deviceSpoofBatteryLevel {
    NSNumber *val = _info[@"deviceSpoofBatteryLevel"];
    return val ? [val floatValue] : 0.85f;
}
- (void)setDeviceSpoofBatteryLevel:(float)level {
    _info[@"deviceSpoofBatteryLevel"] = @(level);
    [self save];
}

- (int)deviceSpoofBatteryState {
    NSNumber *val = _info[@"deviceSpoofBatteryState"];
    return val ? [val intValue] : 1;
}
- (void)setDeviceSpoofBatteryState:(int)state {
    _info[@"deviceSpoofBatteryState"] = @(state);
    [self save];
}

- (bool)deviceSpoofStorage {
    return [_info[@"deviceSpoofStorage"] boolValue];
}
- (void)setDeviceSpoofStorage:(bool)enabled {
    _info[@"deviceSpoofStorage"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofStorageCapacity {
    return _info[@"deviceSpoofStorageCapacity"];
}
- (void)setDeviceSpoofStorageCapacity:(NSString *)cap {
    if (cap.length > 0) {
        _info[@"deviceSpoofStorageCapacity"] = cap;
    } else {
        [_info removeObjectForKey:@"deviceSpoofStorageCapacity"];
        [_info removeObjectForKey:@"deviceSpoofStorageCapacityManual"];
    }
    [self save];
}

- (bool)deviceSpoofStorageCapacityManual {
    id explicitValue = _info[@"deviceSpoofStorageCapacityManual"];
    if (explicitValue != nil) {
        return [explicitValue boolValue];
    }
    // Legacy fallback: a stored capacity before this flag existed is treated as a manual override.
    return _info[@"deviceSpoofStorageCapacity"] != nil;
}
- (void)setDeviceSpoofStorageCapacityManual:(bool)manual {
    _info[@"deviceSpoofStorageCapacityManual"] = @(manual);
    [self save];
}

- (bool)deviceSpoofStorageRandomFree {
    if (_info[@"deviceSpoofStorageRandomFree"] != nil) {
        return [_info[@"deviceSpoofStorageRandomFree"] boolValue];
    }
    return YES;
}
- (void)setDeviceSpoofStorageRandomFree:(bool)enabled {
    _info[@"deviceSpoofStorageRandomFree"] = @(enabled);
    [self save];
}

- (NSString *)deviceSpoofStorageFreeGB {
    return _info[@"deviceSpoofStorageFreeGB"] ?: @"";
}

- (void)setDeviceSpoofStorageFreeGB:(NSString *)freeGB {
    if (freeGB.length > 0) {
        _info[@"deviceSpoofStorageFreeGB"] = freeGB;
    } else {
        [_info removeObjectForKey:@"deviceSpoofStorageFreeGB"];
    }
    [self save];
}

- (bool)deviceSpoofBrightness {
    return [_info[@"deviceSpoofBrightness"] boolValue];
}
- (void)setDeviceSpoofBrightness:(bool)enabled {
    _info[@"deviceSpoofBrightness"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofBrightnessRandomize {
    if (_info[@"deviceSpoofBrightnessRandomize"] != nil) {
        return [_info[@"deviceSpoofBrightnessRandomize"] boolValue];
    }
    return NO;
}
- (void)setDeviceSpoofBrightnessRandomize:(bool)enabled {
    _info[@"deviceSpoofBrightnessRandomize"] = @(enabled);
    [self save];
}

- (float)deviceSpoofBrightnessValue {
    NSNumber *val = _info[@"deviceSpoofBrightnessValue"];
    return val ? [val floatValue] : 0.5f;
}
- (void)setDeviceSpoofBrightnessValue:(float)value {
    _info[@"deviceSpoofBrightnessValue"] = @(value);
    [self save];
}

- (bool)deviceSpoofThermal {
    return [_info[@"deviceSpoofThermal"] boolValue];
}
- (void)setDeviceSpoofThermal:(bool)enabled {
    _info[@"deviceSpoofThermal"] = @(enabled);
    [self save];
}

- (int)deviceSpoofThermalState {
    NSNumber *val = _info[@"deviceSpoofThermalState"];
    return val ? [val intValue] : 0;
}
- (void)setDeviceSpoofThermalState:(int)state {
    _info[@"deviceSpoofThermalState"] = @(state);
    [self save];
}

- (bool)deviceSpoofLowPowerMode {
    return [_info[@"deviceSpoofLowPowerMode"] boolValue];
}
- (void)setDeviceSpoofLowPowerMode:(bool)enabled {
    _info[@"deviceSpoofLowPowerMode"] = @(enabled);
    [self save];
}

- (bool)deviceSpoofLowPowerModeValue {
    return [_info[@"deviceSpoofLowPowerModeValue"] boolValue];
}
- (void)setDeviceSpoofLowPowerModeValue:(bool)value {
    _info[@"deviceSpoofLowPowerModeValue"] = @(value);
    [self save];
}

- (NSString*)remark {
    return _info[@"remark"];
}

- (void)setRemark:(NSString *)remark {
    if([remark isEqualToString: @""]) {
        _info[@"remark"] = nil;
    } else {
        _info[@"remark"] = remark;
    }
    [self save];
}

@end
