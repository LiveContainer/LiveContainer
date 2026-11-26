#pragma once

#import <Foundation/Foundation.h>

typedef NS_ENUM(int64_t, LCLivePlugInCommand) {
    LCLivePlugInCommandLaunchConfiguration = 1,
    LCLivePlugInCommandError = 2,
    LCLivePlugInCommandConnect = 3,
};

static const NSTimeInterval LCLivePlugInLaunchTimeout = 30;

static inline NSString *LCLivePlugInServiceName(NSString *appGroup, pid_t hostPID) {
    return [NSString stringWithFormat:@"%@.LiveContainer.LivePlugIn-%d", appGroup, hostPID];
}

@interface LCLivePlugIn : NSObject
@property(nonatomic) pid_t pid;
+ (void)startServer;
+ (void)resolvePendingRequests;
- (instancetype)initWithUUID:(NSUUID*)identifier configuration:(NSDictionary *)configuration;
@end
