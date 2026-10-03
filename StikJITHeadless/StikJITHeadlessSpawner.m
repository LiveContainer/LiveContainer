//
//  spawner.m
//  LiveContainer
//
//  Created by Duy Tran on 3/10/26.
//
#import "../LiveContainer/FoundationPrivate.h"
#import "../LiveContainer/LCSharedUtils.h"
#import "../LiveContainer/utils.h"

extern BOOL checkJITEnabled(void);

@implementation NSExtension(StikJITHeadlessPayload)
+ (NSString *)spawnStikJITWithHostURLScheme:(NSString *)lcAppUrlScheme docPath:(NSString *)docPath
                                     script:(NSString *)script {
    Class LCSharedUtils = PrivClass(LCSharedUtils);
    __block NSError *error;
    NSExtension *ext = [NSExtension extensionWithIdentifier:[LCSharedUtils liveProcessBundleIdentifier] error:&error];
    if (!ext) {
        return [@"StikJIT was required, but LiveProcess is missing.\n" stringByAppendingString:error.localizedDescription];
    }
    
    // FIXME:
    // 1. can't move these items to app group as it's part of SideStore and I don't like duplicating...
    // 2. can't use file bookmark here as fileproviderd keeps rejecting for some reason
    NSString *key = @"LCStikJITSandboxExtension";
    NSString *sandboxExtension = [NSUserDefaults.lcSharedDefaults stringForKey:key];
    if (!sandboxExtension || sandbox_extension_consume(sandboxExtension.UTF8String) < 1 ||
        ![NSFileManager.defaultManager fileExistsAtPath:[sandboxExtension componentsSeparatedByString:@";"].lastObject]) {
        if ([lcAppUrlScheme isEqualToString:@"livecontainer"]) {
            NSURL *sandboxURL = [NSURL fileURLWithPath:[docPath stringByAppendingPathComponent:@"SideStore/Documents"]];
            NSURL *ddiPath = [sandboxURL URLByAppendingPathComponent:@"DMG"];
            if (![NSFileManager.defaultManager createDirectoryAtURL:ddiPath withIntermediateDirectories:YES attributes:nil error:nil]) {
                return @"Failed to create SideStore/Documents/DMG folder?";
            }
            char *sandboxExtStr = sandbox_extension_issue_file(APP_SANDBOX_READ_WRITE, sandboxURL.fileSystemRepresentation, 0);
            if (!sandboxExtStr) {
                return @"Failed in sandbox_extension_issue_file";
            }
            sandboxExtension = @(sandboxExtStr);
            [NSUserDefaults.lcSharedDefaults setValue:sandboxExtension forKey:key];
        } else {
            return @"Failed to resolve pairing file/DDI sandbox token? Please launch using primary LiveContainer first and try again.";
        }
    }
    
    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{
        @"customPayloadDylib": @"@rpath/StikJITHeadless.framework/StikJITHeadless",
        @"customPayloadEntry": @"StikJITHeadlessMain",
        //@"callbackScheme": lcAppUrlScheme,
        @"sandboxExtension": sandboxExtension,
        @"script": script,
        @"pid": @(getpid())
    };
    ext.requestCancellationBlock = ^(NSUUID *uuid, NSError *jitError) {
        error = jitError;
    };
    ext.requestInterruptionBlock = ^(NSUUID *uuid) {
        error = [NSError errorWithDomain:@"StikJIT" code:1 userInfo:@{NSLocalizedDescriptionKey: @"LiveProcess hosting StikJIT has crashed"}];
    };
    [ext beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *uuid) {
        CFRunLoopStop(CFRunLoopGetMain());
    }];
    CFRunLoopRun();
    while (!error && !checkJITEnabled()) {
        usleep(1000*100);
    }
    return error ? [@"Built-in StikJIT failed: " stringByAppendingString:error.localizedDescription] : nil;
}
@end
