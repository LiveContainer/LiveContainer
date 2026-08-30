//
//  main.m
//  LiveContainer
//
//  Created by Duy Tran on 30/8/26.
//
@import Foundation;

//void StikJITEnableJIT(int pid, NSURL* pairingFile, NSURL* ddiPath, NSString *script, BOOL forceScript);
@interface LiveProcessHandler : NSObject<NSExtensionRequestHandling>
+ (NSExtensionContext *)extensionContext;
+ (NSDictionary *)retrievedAppInfo;
@end

@interface StikJITWrapper : NSObject
+ (NSString *)enableJITWith:(int)pid pairingFile:(NSURL *)pairing ddiPath:(NSURL *)ddi scriptString:(NSString*)script;// error:(NSError **)error;
@end

int StikJITHeadlessMain(void) {
    NSDictionary *appInfo = [NSClassFromString(@"LiveProcessHandler") retrievedAppInfo];
    NSURL *pairingFile = [NSURL URLByResolvingBookmarkData:appInfo[@"pairingBookmark"] options:0 relativeToURL:nil bookmarkDataIsStale:nil error:nil];
    NSURL *ddiPath = [NSURL URLByResolvingBookmarkData:appInfo[@"ddiBookmark"] options:0 relativeToURL:nil bookmarkDataIsStale:nil error:nil];
    NSData *scriptData = [[NSData alloc] initWithBase64EncodedString:appInfo[@"script"] options:0];
    NSString *script = [[NSString alloc] initWithData:scriptData encoding:NSUTF8StringEncoding];
    [pairingFile startAccessingSecurityScopedResource];
    [ddiPath startAccessingSecurityScopedResource];
    
    NSString *error = [StikJITWrapper enableJITWith:[appInfo[@"pid"] unsignedIntValue] pairingFile:pairingFile ddiPath:ddiPath scriptString:script];// error:&error];
    if (error.length > 0) {
        NSLog(@"Failed to enable JIT: %@", error);
        NSExtensionContext *context = [NSClassFromString(@"LiveProcessHandler") extensionContext];
        [context cancelRequestWithError:[NSError errorWithDomain:@"StikJIT" code:1 userInfo:@{NSLocalizedDescriptionKey: error}]];
    }
    return 0;
}
