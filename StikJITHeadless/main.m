//
//  main.m
//  LiveContainer
//
//  Created by Duy Tran on 30/8/26.
//
@import Foundation;
#import <CommonCrypto/CommonCrypto.h>
#import "../LiveContainer/utils.h"

@interface LiveProcessHandler : NSObject<NSExtensionRequestHandling>
+ (NSExtensionContext *)extensionContext;
+ (NSDictionary *)retrievedAppInfo;
@end

@interface StikJITWrapper : NSObject
+ (NSString *)enableJITWith:(int)pid pairingFile:(NSURL *)pairing ddiPath:(NSURL *)ddi scriptJs:(NSString *)script;
@end

static int StikJITExitWithError(NSString *error) {
    NSLog(@"Cancelling with error: %@", error);
    NSExtensionContext *context = [NSClassFromString(@"LiveProcessHandler") extensionContext];
    [context cancelRequestWithError:[NSError errorWithDomain:@"StikJIT" code:1 userInfo:@{NSLocalizedDescriptionKey: error}]];
    return 1;
}

int StikJITHeadlessMain(void) {
    NSError *e;
    NSDictionary *appInfo = [NSClassFromString(@"LiveProcessHandler") retrievedAppInfo];
    NSString *sandboxExtension = appInfo[@"sandboxExtension"];
    NSArray *sandboxExtensionSplit = [sandboxExtension componentsSeparatedByString:@";"];
    if (sandbox_extension_consume(sandboxExtension.UTF8String) < 1) {
        return StikJITExitWithError(@"Failed in sandbox_extension_issue_file");
    }
    
    NSString *path = sandboxExtensionSplit.lastObject;
    NSURL *sandboxURL = [NSURL fileURLWithPath:path];
    if (!sandboxURL) {
        return StikJITExitWithError(e.localizedDescription);
    }
    
    NSURL *pairingFile = [sandboxURL URLByAppendingPathComponent:@"ALTPairingFile.mobiledevicepairing"];
    NSURL *ddiPath = [sandboxURL URLByAppendingPathComponent:@"DMG"];
    if (![NSFileManager.defaultManager fileExistsAtPath:pairingFile.path]) {
        return StikJITExitWithError(@"Pairing file is not set.");
    }
    
    NSString *error = [StikJITWrapper enableJITWith:[appInfo[@"pid"] unsignedIntValue]
                                        pairingFile:pairingFile ddiPath:ddiPath scriptJs:appInfo[@"script"]];
    if (error.length < 1) return 0;
    return StikJITExitWithError(error);
}
