#import <Foundation/Foundation.h>
#import "LCBackupPolicyManager.h"

typedef BOOL (^LCBackupPolicyItemHandler)(NSURL *url, BOOL excluded, NSString *label);

@interface LCBackupPolicyManager (Testing)
+ (BOOL)applyPolicy:(LCBackupPolicy)policy
          toHomeURL:(NSURL *)homeURL
        appGroupURL:(nullable NSURL *)appGroupURL
        itemHandler:(LCBackupPolicyItemHandler)itemHandler;
@end

static NSUInteger failureCount = 0;

static void LCAssert(BOOL condition, NSString *message) {
    if(!condition) {
        failureCount += 1;
        NSLog(@"FAIL: %@", message);
    }
}

static void CreateDirectory(NSURL *url) {
    NSError *error = nil;
    BOOL success = [NSFileManager.defaultManager createDirectoryAtURL:url
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&error];
    LCAssert(success, @"Unable to create test fixture directory");
}

static void TestPolicyDecoding(void) {
    NSString *suiteName = [@"LCBackupPolicyManagerTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
    LCAssert([LCBackupPolicyManager policyFromUserDefaults:defaults] == LCBackupPolicyFull,
             @"Missing policy must resolve to Full");

    [defaults setObject:@"2" forKey:LCBackupPolicyDefaultsKey];
    LCAssert([LCBackupPolicyManager policyFromUserDefaults:defaults] == LCBackupPolicyFull,
             @"Non-numeric policy must resolve to Full");

    [defaults setInteger:99 forKey:LCBackupPolicyDefaultsKey];
    LCAssert([LCBackupPolicyManager policyFromUserDefaults:defaults] == LCBackupPolicyFull,
             @"Unknown policy must resolve to Full");

    [defaults setInteger:LCBackupPolicyGuestDataOnly forKey:LCBackupPolicyDefaultsKey];
    LCAssert([LCBackupPolicyManager policyFromUserDefaults:defaults] == LCBackupPolicyFull,
             @"Guest data only must remain disabled in phase 1");

    [LCBackupPolicyManager setPolicy:LCBackupPolicyNoLiveContainerData inUserDefaults:defaults];
    LCAssert([LCBackupPolicyManager policyFromUserDefaults:defaults] == LCBackupPolicyNoLiveContainerData,
             @"No-data policy must round-trip");

    [LCBackupPolicyManager setPolicy:LCBackupPolicyGuestDataOnly inUserDefaults:defaults];
    LCAssert([defaults integerForKey:LCBackupPolicyDefaultsKey] == LCBackupPolicyFull,
             @"Persisting disabled Guest data only must store Full");
    [defaults removePersistentDomainForName:suiteName];
}

static void TestTransitionsAndProtectedPaths(NSURL *rootURL) {
    NSURL *homeURL = [rootURL URLByAppendingPathComponent:@"Home" isDirectory:YES];
    NSURL *documentsURL = [homeURL URLByAppendingPathComponent:@"Documents" isDirectory:YES];
    NSURL *applicationsURL = [documentsURL URLByAppendingPathComponent:@"Applications" isDirectory:YES];
    NSURL *dataURL = [documentsURL URLByAppendingPathComponent:@"Data" isDirectory:YES];
    NSURL *tweaksURL = [documentsURL URLByAppendingPathComponent:@"Tweaks" isDirectory:YES];
    NSURL *libraryURL = [homeURL URLByAppendingPathComponent:@"Library" isDirectory:YES];
    NSURL *sideStorePrivateURL = [documentsURL URLByAppendingPathComponent:@"SideStore" isDirectory:YES];

    NSURL *appGroupURL = [rootURL URLByAppendingPathComponent:@"AppGroup" isDirectory:YES];
    NSURL *liveContainerURL = [appGroupURL URLByAppendingPathComponent:@"LiveContainer" isDirectory:YES];
    NSURL *sharedApplicationsURL = [liveContainerURL URLByAppendingPathComponent:@"Applications" isDirectory:YES];
    NSURL *sharedTweaksURL = [liveContainerURL URLByAppendingPathComponent:@"Tweaks" isDirectory:YES];
    NSURL *sideStoreAppsURL = [appGroupURL URLByAppendingPathComponent:@"Apps" isDirectory:YES];
    NSURL *sideStoreDatabaseURL = [appGroupURL URLByAppendingPathComponent:@"Database" isDirectory:YES];
    NSURL *sideStoreLibraryURL = [appGroupURL URLByAppendingPathComponent:@"Library" isDirectory:YES];

    for(NSURL *url in @[applicationsURL, dataURL, tweaksURL, libraryURL, sideStorePrivateURL,
                         sharedApplicationsURL, sharedTweaksURL,
                         sideStoreAppsURL, sideStoreDatabaseURL, sideStoreLibraryURL]) {
        CreateDirectory(url);
    }

    NSMutableDictionary<NSString *, NSNumber *> *appliedValues = [NSMutableDictionary dictionary];
    LCBackupPolicyItemHandler recorder = ^BOOL(NSURL *url, BOOL excluded, NSString *label) {
        appliedValues[url.standardizedURL.path] = @(excluded);
        return YES;
    };

    LCAssert([LCBackupPolicyManager applyPolicy:LCBackupPolicyNoLiveContainerData
                                      toHomeURL:homeURL
                                    appGroupURL:appGroupURL
                                    itemHandler:recorder],
             @"No-data policy must apply successfully");
    LCAssert(appliedValues.count == 5, @"Only the five managed roots may be passed to the flag writer");
    for(NSURL *url in @[applicationsURL, dataURL, tweaksURL, libraryURL, liveContainerURL]) {
        LCAssert([appliedValues[url.standardizedURL.path] boolValue],
                 @"Every managed target must be excluded by No data");
    }
    for(NSURL *url in @[sharedApplicationsURL, sharedTweaksURL]) {
        LCAssert(appliedValues[url.standardizedURL.path] == nil,
                 @"No data must set only the five broad targets");
    }
    for(NSURL *url in @[documentsURL, sideStorePrivateURL, appGroupURL,
                         sideStoreAppsURL, sideStoreDatabaseURL, sideStoreLibraryURL]) {
        LCAssert(appliedValues[url.standardizedURL.path] == nil,
                 @"Protected SideStore/Documents path must never be passed to the flag writer");
    }

    [appliedValues removeAllObjects];
    LCAssert([LCBackupPolicyManager applyPolicy:LCBackupPolicyFull
                                      toHomeURL:homeURL
                                    appGroupURL:appGroupURL
                                    itemHandler:recorder],
             @"Full policy must apply successfully");
    LCAssert(appliedValues.count == 7, @"Full must send all seven managed targets to the flag writer");
    for(NSURL *url in @[applicationsURL, dataURL, tweaksURL, libraryURL, liveContainerURL,
                         sharedApplicationsURL, sharedTweaksURL]) {
        NSNumber *value = appliedValues[url.standardizedURL.path];
        LCAssert(value != nil && !value.boolValue,
                 @"Full must clear every flag the manager can set");
    }
    for(NSURL *url in @[documentsURL, sideStorePrivateURL, appGroupURL,
                         sideStoreAppsURL, sideStoreDatabaseURL, sideStoreLibraryURL]) {
        LCAssert(appliedValues[url.standardizedURL.path] == nil,
                 @"Full must not pass protected SideStore/Documents paths to the flag writer");
    }
}

static void TestMissingRootsAreNotCreated(NSURL *rootURL) {
    NSURL *homeURL = [rootURL URLByAppendingPathComponent:@"EmptyHome" isDirectory:YES];
    NSURL *documentsURL = [homeURL URLByAppendingPathComponent:@"Documents" isDirectory:YES];
    NSURL *appGroupURL = [rootURL URLByAppendingPathComponent:@"EmptyAppGroup" isDirectory:YES];
    NSURL *liveContainerURL = [appGroupURL URLByAppendingPathComponent:@"LiveContainer" isDirectory:YES];
    NSURL *sharedApplicationsURL = [liveContainerURL URLByAppendingPathComponent:@"Applications" isDirectory:YES];
    NSURL *sharedTweaksURL = [liveContainerURL URLByAppendingPathComponent:@"Tweaks" isDirectory:YES];
    CreateDirectory(documentsURL);
    CreateDirectory(appGroupURL);

    __block NSUInteger appliedItemCount = 0;
    LCAssert([LCBackupPolicyManager applyPolicy:LCBackupPolicyNoLiveContainerData
                                      toHomeURL:homeURL
                                    appGroupURL:appGroupURL
                                    itemHandler:^BOOL(NSURL *url, BOOL excluded, NSString *label) {
        appliedItemCount += 1;
        return YES;
    }],
             @"Missing roots should be skipped without error");
    LCAssert(appliedItemCount == 0, @"Missing roots must not be passed to the flag writer");

    NSArray<NSURL *> *missingURLs = @[
        [documentsURL URLByAppendingPathComponent:@"Applications" isDirectory:YES],
        [documentsURL URLByAppendingPathComponent:@"Data" isDirectory:YES],
        [documentsURL URLByAppendingPathComponent:@"Tweaks" isDirectory:YES],
        [homeURL URLByAppendingPathComponent:@"Library" isDirectory:YES],
        liveContainerURL,
        sharedApplicationsURL,
        sharedTweaksURL,
    ];
    for(NSURL *url in missingURLs) {
        LCAssert(![NSFileManager.defaultManager fileExistsAtPath:url.path],
                 @"Applying policy must not create managed roots");
    }

    CreateDirectory(liveContainerURL);
    appliedItemCount = 0;
    LCAssert([LCBackupPolicyManager applyPolicy:LCBackupPolicyFull
                                      toHomeURL:homeURL
                                    appGroupURL:appGroupURL
                                    itemHandler:^BOOL(NSURL *url, BOOL excluded, NSString *label) {
        appliedItemCount += 1;
        return YES;
    }], @"Full should skip missing future child roots without error");
    LCAssert(appliedItemCount == 1, @"Only the existing shared broad root should be cleared");
    LCAssert(![NSFileManager.defaultManager fileExistsAtPath:sharedApplicationsURL.path] &&
             ![NSFileManager.defaultManager fileExistsAtPath:sharedTweaksURL.path],
             @"Full must not create missing future child roots");
}

int main(void) {
    @autoreleasepool {
        TestPolicyDecoding();

        NSURL *rootURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
            stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        CreateDirectory(rootURL);
        TestTransitionsAndProtectedPaths(rootURL);
        TestMissingRootsAreNotCreated(rootURL);
        [NSFileManager.defaultManager removeItemAtURL:rootURL error:nil];

        if(failureCount == 0) {
            NSLog(@"LCBackupPolicyManager tests passed");
            return 0;
        }
        NSLog(@"LCBackupPolicyManager tests failed: %lu", (unsigned long)failureCount);
        return 1;
    }
}
