#import <Foundation/Foundation.h>

// Test host only: exercises the same Objective-C class method used by SideStore.
@interface LCSharedUtils : NSObject
+ (NSURL *)appGroupPath;
@end
@implementation LCSharedUtils
+ (NSURL *)appGroupPath {
    return [NSURL fileURLWithPath:NSProcessInfo.processInfo.environment[@"LCOS_TEST_GROUP"]];
}
@end
