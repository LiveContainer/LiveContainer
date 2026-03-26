#include <Foundation/Foundation.h>
#import "Intents/Intents.h"
#import "CloudKit/CloudKit.h"

@interface NSBundle(private)
- (id)_cfBundle;
@end

@interface NSUserDefaults(private)
+ (void)setStandardUserDefaults:(id)defaults;
- (instancetype)_initWithSuiteName:(NSString*)suiteName container:(NSURL*)container;
- (void)_setIdentifier:(NSString*)identifier;
- (NSString*)_identifier;
- (NSString*)_container;
- (void)_setContainer:(NSURL*)identifier;
@end

@interface NSExtension : NSObject
@property (nonatomic, strong, readwrite) NSArray *preferredLanguages;
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void(^)(NSUUID *))callback;
- (int)pidForRequestIdentifier:(NSUUID *)identifier;
- (void)_kill:(int)arg1;
- (void)setRequestCancellationBlock:(void(^)(NSUUID *uuid, NSError *error))callback;
- (void)setRequestInterruptionBlock:(void(^)(NSUUID *))callback;
- (void)_hostDidEnterBackgroundNote:(NSNotification *)note;
- (void)_hostWillResignActiveNote:(NSNotification *)note;
@end

void* SecTaskCreateFromSelf(CFAllocatorRef allocator);
NSString *SecTaskCopyTeamIdentifier(void *task, NSError **error);
CFTypeRef SecTaskCopyValueForEntitlement(void *task, CFStringRef key, CFErrorRef *error);


@interface _CFXPreferences2 : NSObject
+(instancetype)copyDefaultPreferences;
-(CFPropertyListRef)hook_copyAppValueForKey:(CFStringRef)key identifier:(CFStringRef)identifier container:(CFStringRef)container configurationURL:(CFURLRef)configurationURL;
-(CFPropertyListRef)hook_copyValueForKey:(CFStringRef)key identifier:(CFStringRef)identifier user:(CFStringRef)user host:(CFStringRef)host container:(CFStringRef)container;
-(void)hook_setValue:(CFPropertyListRef)value forKey:(CFStringRef)key appIdentifier:(CFStringRef)appIdentifier container:(CFStringRef)container configurationURL:(CFURLRef)configurationURL;
@end

@interface CFPrefsPlistSource2 : NSObject
-(id)hook_initWithDomain:(CFStringRef)arg1 user:(CFStringRef)arg2 byHost:(bool)arg3 containerPath:(CFStringRef)arg4 containingPreferences:(id)arg5 ;
@end

