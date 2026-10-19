#import <Foundation/Foundation.h>
#import "../../TweakLoader/LCGuestJITURL.h"

// Test host only: exercises the same Objective-C class method used by SideStore.
@interface LCSharedUtils : NSObject
+ (NSURL *)appGroupPath;
@end

@interface LCOSSigningInjectionPresenter : NSObject
+ (void)configureBundleIdentifier:(NSString *)identifier appName:(NSString *)name presenter:(NSObject *)presenter completion:(void (^)(BOOL))completion;
@end
@implementation LCOSSigningInjectionPresenter
+ (void)configureBundleIdentifier:(NSString *)identifier appName:(NSString *)name presenter:(NSObject *)presenter completion:(void (^)(BOOL))completion {
    NSCAssert([name isEqualToString:@"Controlled probe"], @"Bridge lost application name");
    completion(![identifier hasSuffix:@".cancel"]);
}
@end

void LCOSTestGuestJITRouting(void) {
    NSURL *input = [NSURL URLWithString:@"stikjit://enable-jit?bundle-id=com.husk.app&script-data=a%2Bb%2Fc%3D&custom=preserved"];
    NSURL *output = LCGuestJITURL(input, @"com.husk.app", @"com.example.host", 1234);
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:output resolvingAgainstBaseURL:NO].queryItems) items[item.name] = item.value;
    NSCAssert([items[@"bundle-id"] isEqualToString:@"com.example.host"] && [items[@"pid"] isEqualToString:@"1234"], @"Wrong host target");
    NSCAssert([items[@"script-data"] isEqualToString:@"a+b/c="] && [items[@"custom"] isEqualToString:@"preserved"], @"Script query was corrupted");
    NSCAssert([LCGuestJITURL(input, @"com.other.app", @"com.example.host", 1234) isEqual:input], @"Changed unrelated target");
    NSURL *otherPID = [NSURL URLWithString:@"stikjit://enable-jit?bundle-id=com.husk.app&pid=4321"];
    NSCAssert([LCGuestJITURL(otherPID, @"com.husk.app", @"com.example.host", 1234) isEqual:otherPID], @"Changed explicit unrelated process");
}
@implementation LCSharedUtils
+ (NSURL *)appGroupPath {
    return [NSURL fileURLWithPath:NSProcessInfo.processInfo.environment[@"LCOS_TEST_GROUP"]];
}
@end
