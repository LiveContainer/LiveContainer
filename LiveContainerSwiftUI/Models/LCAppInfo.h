#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LCUtils.h"

typedef NS_ENUM(NSInteger, LCOrientationLock){
    Disabled = 0,
    Landscape = 1,
    Portrait = 2
};

typedef NS_ENUM(NSInteger, MultitaskSpecified){
    MultitaskSpecifiedDefault = 0,
    MultitaskSpecifiedNo = 1,
    MultitaskSpecifiedYes = 2
};


@interface LCAppInfo : NSObject {
    NSMutableDictionary* _info;
    NSMutableDictionary* _infoPlist;
    NSString* _bundlePath;
}

@property (nonatomic, assign) MultitaskSpecified realIPhoneModeSpecified;
@property NSString* relativeBundlePath;
@property bool isShared;
@property bool isJITNeeded;
@property bool isLocked;
@property bool isHidden;
@property bool doSymlinkInbox;
@property bool hideLiveContainer;
@property bool dontLoadTweakLoader;
@property bool dontInjectTweakLoader;
@property LCOrientationLock orientationLock;
@property MultitaskSpecified multitaskSpecified;
@property bool fixFilePickerNew;
@property bool fixLocalNotification;
@property bool doUseLCBundleId;
@property NSString* selectedLanguage;
@property NSString* dataUUID;
@property NSString* tweakFolder;
@property NSArray<NSDictionary*>* containerInfo;
@property bool autoSaveDisabled;
@property bool dontSign;
@property bool spoofSDKVersion;
@property (nonatomic, strong) NSString* jitLaunchScriptJs;
@property NSDate* lastLaunched;
@property NSDate* installationDate;
@property NSString* remark;
#if is32BitSupported
@property bool is32bit;
#endif
@property UIColor* cachedColor;
@property UIColor* cachedColorDark;
@property UIImage* cachedIcon;
@property UIImage* cachedIconDark;

- (void)setBundlePath:(NSString*)newBundlePath;
- (NSMutableDictionary*)info;
- (UIImage*)iconIsDarkIcon:(BOOL)isDarkIcon;
- (void)clearIconCache;
- (NSString*)displayName;
- (NSString*)bundlePath;
- (NSString*)bundleIdentifier;
- (NSString*)version;
- (NSMutableArray<NSString *>*)urlSchemes;
- (instancetype)initWithBundlePath:(NSString*)bundlePath;
- (UIImage *)generateLiveContainerWrappedIconWithStyle:(GeneratedIconStyle)style;
- (NSDictionary *)generateWebClipConfigWithContainerId:(NSString*)containerId iconStyle:(GeneratedIconStyle)style;
- (void)save;
- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(bool success, NSString* errorInfo))completetionHandler progressHandler:(void(^)(NSProgress* progress))progressHandler  forceSign:(BOOL)forceSign;
@end
