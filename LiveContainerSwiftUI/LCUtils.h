#import <Foundation/Foundation.h>
#import "LCMachOUtils.h"
#import "utils.h"
@import UIKit;

typedef NS_ENUM(NSInteger, Store){
    SideStore = 0,
    AltStore = 1,
    ADP = 2,
    Unknown = -1
};

void refreshFile(NSString* execPath);
int dyld_get_program_sdk_version(void);

@interface PKZipArchiver : NSObject

- (NSData *)zippedDataForURL:(NSURL *)url;

@end

@interface UIDevice(private)
@property(readonly) NSString* buildVersion;
@end

@interface LCUtils : NSObject

+ (void)validateJITLessSetupWithCompletionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
+ (NSURL *)archiveIPAWithBundleName:(NSString*)newBundleName excludingInfoPlistKeys:(NSArray *)keysToExclude error:(NSError **)error;
+ (NSData *)certificateData;
+ (NSString *)certificatePassword;

+ (BOOL)launchToGuestApp;
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url;
+ (void)launchMultitaskGuestApp:(NSString *)displayName completionHandler:(void (^)(NSError *error))completionHandler API_AVAILABLE(ios(16.0));
+ (void)launchMultitaskGuestAppWithPIDCallback:(NSString *)displayName pidCompletionHandler:(void (^)(NSNumber *pid, NSError *error))completionHandler API_AVAILABLE(ios(16.0));
+ (NSString*)getContainerUsingLCSchemeWithFolderName:(NSString*)folderName;

+ (NSProgress *)signAppBundleWithURL:(NSURL *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
+ (int)validateCertificateWithCompletionHandler:(void(^)(int status, NSDate *expirationDate, NSString *organizationalUnitName, NSString *error))completionHandler;

+ (BOOL)isAppGroupAltStoreLike;
+ (Store)store;
+ (NSString *)teamIdentifier;
+ (NSString *)appGroupID;
+ (NSString *)appUrlScheme;
+ (NSURL *)appGroupPath;
+ (NSString *)storeInstallURLScheme;
+ (NSString *)getVersionInfo;
+ (NSString *)liveProcessBundleIdentifier;
+ (NSData*)bookmarkForURL:(NSURL*) url;
@end

@interface NSUserDefaults(LiveContainer)
+ (bool)sideStoreExist;
@end

@interface UIImage(LiveContainer)
+ (instancetype)iconForBundleURL:(NSURL*)url isDarkIcon:(BOOL)isDarkIcon;
@end
