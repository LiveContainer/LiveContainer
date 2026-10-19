#import <Foundation/Foundation.h>
#import "../../TweakLoader/LCGuestJITURL.h"
#import "../../LiveContainer/Tweaks/LCGuestEnvironment.h"
#import "../../LiveContainer/LCGrantedFolder.h"

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
    NSDictionary *environment = @{@"LC_HOME_PATH": @"private", @"LP_HOME_PATH": @"private", @"HOME": @"guest", @"PATH": @"system"};
    NSDictionary *filtered = LCGuestEnvironment(environment, YES);
    NSCAssert(!filtered[@"LC_HOME_PATH"] && !filtered[@"LP_HOME_PATH"] && [filtered[@"HOME"] isEqual:@"guest"], @"Concealment filtering failed");
    NSCAssert(environment[@"LC_HOME_PATH"] && LCGuestEnvironment(environment, NO) == environment, @"Real host environment was modified");
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [fm.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSURL *home = [root URLByAppendingPathComponent:@"Guest"];
    NSURL *selected = [root URLByAppendingPathComponent:@"Selected"];
    [fm createDirectoryAtURL:home withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtURL:selected withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *bookmark = [selected bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
    NSURL *lease = nil;
    NSCAssert(bookmark && !LCPrepareGrantedFolder(home.path, bookmark, &lease), @"Folder bookmark did not mount");
    NSString *mount = [home.path stringByAppendingPathComponent:@"Documents/LiveContainer Access/Shared"];
    NSCAssert([[fm destinationOfSymbolicLinkAtPath:mount error:nil] isEqual:selected.path.stringByResolvingSymlinksInPath], @"Wrong folder target");
    [lease stopAccessingSecurityScopedResource];
    NSCAssert(!LCPrepareGrantedFolder(home.path, nil, nil) && ![fm fileExistsAtPath:mount], @"Revocation did not remove the managed alias");
    [fm createDirectoryAtPath:mount withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert(LCPrepareGrantedFolder(home.path, bookmark, nil) && [fm fileExistsAtPath:mount], @"Unmanaged data was overwritten");
    NSData *ancestor = [root bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
    NSCAssert(LCPrepareGrantedFolder(home.path, ancestor, nil), @"Recursive folder grant was accepted");
    [fm removeItemAtURL:root error:nil];
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
