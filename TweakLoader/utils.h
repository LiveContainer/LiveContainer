@import Foundation;
@import ObjectiveC;

void swizzle(Class class, SEL originalAction, SEL swizzledAction);
void swizzleClassMethod(Class class, SEL originalAction, SEL swizzledAction);

// Exported from the main executable
@interface NSUserDefaults(LiveContainer)
+ (instancetype)lcUserDefaults;
+ (instancetype)lcSharedDefaults;
+ (NSString *)lcAppGroupPath;
+ (NSString *)lcAppUrlScheme;
+ (NSBundle *)lcMainBundle;
+ (NSDictionary *)guestAppInfo;
+ (NSDictionary *)guestContainerInfo;
+ (bool)isLiveProcess;
+ (bool)isSharedApp;
+ (NSString*)lcGuestAppId;
+ (bool)isSideStore;
+ (bool)sideStoreExist;
+ (NSString*)lcLaunchURL;
@end
