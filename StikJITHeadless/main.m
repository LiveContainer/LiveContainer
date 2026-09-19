//
//  main.m
//  LiveContainer
//
//  Created by Duy Tran on 30/8/26.
//
@import Foundation;
#import "../LiveContainer/utils.h"

//void StikJITEnableJIT(int pid, NSURL* pairingFile, NSURL* ddiPath, NSString *script, BOOL forceScript);
@interface LiveProcessHandler : NSObject<NSExtensionRequestHandling>
+ (NSExtensionContext *)extensionContext;
+ (NSDictionary *)retrievedAppInfo;
@end

@interface StikJITWrapper : NSObject
+ (NSString *)enableJITWith:(int)pid pairingFile:(NSURL *)pairing ddiPath:(NSURL *)ddi scriptPath:(NSURL *)script;// error:(NSError **)error;
@end

static int StikJITExitWithError(NSString *error) {
    NSLog(@"Cancelling with error: %@", error);
    NSExtensionContext *context = [NSClassFromString(@"LiveProcessHandler") extensionContext];
    [context cancelRequestWithError:[NSError errorWithDomain:@"StikJIT" code:1 userInfo:@{NSLocalizedDescriptionKey: error}]];
    return 1;
}

static NSURL *StikJITWriteTmpFile(NSString *name, NSString *content) {
    NSURL *output = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:name];
    [content writeToURL:output atomically:YES encoding:kCFStringEncodingUTF8 error:nil];
    return output;
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
    
    NSData *scriptData = [[NSData alloc] initWithBase64EncodedString:appInfo[@"script"] options:0];
    NSString *script = [[NSString alloc] initWithData:scriptData encoding:NSUTF8StringEncoding];
    
    NSURL *scriptPath = script.length > 0 ? StikJITWriteTmpFile(@"script.js", script) : 0;
    NSString *error = [StikJITWrapper enableJITWith:[appInfo[@"pid"] unsignedIntValue] pairingFile:pairingFile ddiPath:ddiPath scriptPath:scriptPath];// error:&error];
    if (error.length > 0) {
        return StikJITExitWithError(error);
    }
    return 0;
}
