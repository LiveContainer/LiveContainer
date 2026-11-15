#import "LCBackupPolicyManager.h"

NSString * const LCBackupPolicyDefaultsKey = @"LCBackupPolicy";

typedef BOOL (^LCBackupPolicyItemHandler)(NSURL *url, BOOL excluded, NSString *label);

@implementation LCBackupPolicyManager

+ (LCBackupPolicy)normalizedPolicy:(LCBackupPolicy)policy {
    switch(policy) {
        case LCBackupPolicyFull:
        case LCBackupPolicyNoLiveContainerData:
            return policy;
        case LCBackupPolicyGuestDataOnly:
        default:
            // Guest-data restore is not available until its metadata path is implemented.
            return LCBackupPolicyFull;
    }
}

+ (LCBackupPolicy)policyFromUserDefaults:(NSUserDefaults *)userDefaults {
    id storedValue = [userDefaults objectForKey:LCBackupPolicyDefaultsKey];
    if(![storedValue isKindOfClass:NSNumber.class]) {
        return LCBackupPolicyFull;
    }
    return [self normalizedPolicy:(LCBackupPolicy)[storedValue integerValue]];
}

+ (void)setPolicy:(LCBackupPolicy)policy inUserDefaults:(NSUserDefaults *)userDefaults {
    LCBackupPolicy normalizedPolicy = [self normalizedPolicy:policy];
    [userDefaults setInteger:normalizedPolicy forKey:LCBackupPolicyDefaultsKey];
}

+ (BOOL)setExcludedFromBackup:(BOOL)excluded forURL:(NSURL *)url label:(NSString *)label {
    NSFileManager *fm = NSFileManager.defaultManager;
    if(![fm fileExistsAtPath:url.path]) {
        return YES;
    }

    NSError *error = nil;
    if(![url setResourceValue:@(excluded) forKey:NSURLIsExcludedFromBackupKey error:&error]) {
        NSLog(@"[LCBackupPolicy] Unable to update %@ (error %@/%ld)", label, error.domain, (long)error.code);
        return NO;
    }

    NSNumber *isExcluded = nil;
    error = nil;
    if(![url getResourceValue:&isExcluded forKey:NSURLIsExcludedFromBackupKey error:&error] ||
       isExcluded.boolValue != excluded) {
        NSLog(@"[LCBackupPolicy] Unable to verify %@ (error %@/%ld)", label, error.domain, (long)error.code);
        return NO;
    }
    return YES;
}

+ (BOOL)applyPolicy:(LCBackupPolicy)policy
          toHomeURL:(NSURL *)homeURL
        appGroupURL:(NSURL *)appGroupURL {
    return [self applyPolicy:policy
                   toHomeURL:homeURL
                 appGroupURL:appGroupURL
                 itemHandler:^BOOL(NSURL *url, BOOL excluded, NSString *label) {
        return [self setExcludedFromBackup:excluded forURL:url label:label];
    }];
}

+ (BOOL)applyPolicy:(LCBackupPolicy)policy
          toHomeURL:(NSURL *)homeURL
        appGroupURL:(NSURL *)appGroupURL
        itemHandler:(LCBackupPolicyItemHandler)itemHandler {
    LCBackupPolicy normalizedPolicy = [self normalizedPolicy:policy];
    BOOL excluded = normalizedPolicy == LCBackupPolicyNoLiveContainerData;
    NSURL *documentsURL = [homeURL URLByAppendingPathComponent:@"Documents" isDirectory:YES];

    NSMutableArray<NSDictionary<NSString *, id> *> *noDataBroadTargets = [@[
        @{@"url": [documentsURL URLByAppendingPathComponent:@"Applications" isDirectory:YES],
          @"label": @"private Applications"},
        @{@"url": [documentsURL URLByAppendingPathComponent:@"Data" isDirectory:YES],
          @"label": @"private Data"},
        @{@"url": [documentsURL URLByAppendingPathComponent:@"Tweaks" isDirectory:YES],
          @"label": @"private Tweaks"},
        @{@"url": [homeURL URLByAppendingPathComponent:@"Library" isDirectory:YES],
          @"label": @"private Library"},
    ] mutableCopy];

    NSMutableArray<NSDictionary<NSString *, id> *> *allManagedFlagTargets = noDataBroadTargets.mutableCopy;
    if(appGroupURL) {
        NSURL *liveContainerURL = [appGroupURL URLByAppendingPathComponent:@"LiveContainer" isDirectory:YES];
        NSDictionary<NSString *, id> *liveContainerTarget =
            @{@"url": liveContainerURL, @"label": @"shared LiveContainer"};
        [noDataBroadTargets addObject:liveContainerTarget];
        [allManagedFlagTargets addObjectsFromArray:@[
            liveContainerTarget,
            @{@"url": [liveContainerURL URLByAppendingPathComponent:@"Applications" isDirectory:YES],
              @"label": @"shared Applications"},
            @{@"url": [liveContainerURL URLByAppendingPathComponent:@"Tweaks" isDirectory:YES],
              @"label": @"shared Tweaks"},
        ]];
    }

    NSArray<NSDictionary<NSString *, id> *> *targets =
        normalizedPolicy == LCBackupPolicyNoLiveContainerData ? noDataBroadTargets : allManagedFlagTargets;

    BOOL success = YES;
    for(NSDictionary<NSString *, id> *item in targets) {
        NSURL *url = item[@"url"];
        if([NSFileManager.defaultManager fileExistsAtPath:url.path] &&
           !itemHandler(url, excluded, item[@"label"])) {
            success = NO;
        }
    }
    return success;
}

@end
