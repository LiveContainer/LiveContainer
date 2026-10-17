#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LCBackupPolicy) {
    LCBackupPolicyFull = 0,
    LCBackupPolicyGuestDataOnly = 1,
    LCBackupPolicyNoLiveContainerData = 2,
};

FOUNDATION_EXPORT NSString * const LCBackupPolicyDefaultsKey;

@interface LCBackupPolicyManager : NSObject

+ (LCBackupPolicy)policyFromUserDefaults:(NSUserDefaults *)userDefaults
    NS_SWIFT_NAME(policy(from:));
+ (void)setPolicy:(LCBackupPolicy)policy inUserDefaults:(NSUserDefaults *)userDefaults
    NS_SWIFT_NAME(setPolicy(_:in:));
+ (BOOL)applyPolicy:(LCBackupPolicy)policy
          toHomeURL:(NSURL *)homeURL
        appGroupURL:(nullable NSURL *)appGroupURL
    NS_SWIFT_NAME(applyPolicy(_:homeURL:appGroupURL:));

@end

NS_ASSUME_NONNULL_END
