#pragma once

#import <Foundation/Foundation.h>
#include <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

// iOS 26 PlugInKit's launch-only path, before PKHostPlugIn creates the child NSXPC Hub connection.
@interface PKProcessAssertionProxy : NSObject
@property (nonatomic, copy, nullable) void (^invalidationHandler)(void);
- (BOOL)acquire;
- (void)invalidate;
@end

@interface PKRunningBoardProvider : NSObject
- (nullable PKProcessAssertionProxy *)processAssertionWithPID:(pid_t)pid flags:(uint32_t)flags reason:(uint32_t)reason name:(NSString *)name;
@end

@interface PKExternalProviders : NSObject
@property (nonatomic, readonly) PKRunningBoardProvider *runningboard;
@end

@class PKHostPlugIn;
@interface PKHost : NSObject
+ (instancetype)defaultHost;
- (void)discoverPlugInsForAttributes:(NSDictionary *)attributes flags:(NSUInteger)flags
                             found:(void (^)(NSSet<PKHostPlugIn *> * _Nullable plugins, NSError * _Nullable error))found;
- (void)readyPlugIns:(NSArray<PKHostPlugIn *> *)plugins synchronously:(BOOL)synchronously environment:(nullable NSDictionary *)environment
          languages:(NSArray<NSString *> *)languages persona:(nullable id)persona sandbox:(nullable NSString *)sandbox
              ready:(void (^)(NSError * _Nullable error, NSArray<NSNumber *> * _Nullable pids, NSArray<NSUUID *> * _Nullable uuids))ready;
@end

@interface PKHostPlugIn : NSObject
@property (nonatomic, readonly) PKHost *host;
@property (nonatomic, readonly) PKExternalProviders *external;
@property (nonatomic, readonly) NSUUID *uuid;
@property (nonatomic, readonly) NSXPCConnection *pluginConnection;
@property (nonatomic, readonly, nullable) NSString *sandboxProfile;
- (nullable PKHostPlugIn *)createInstanceWithUUID:(NSUUID *)uuid;
- (void)beginUsingRequest:(id)request withSubsystemOptions:(id)options completion:(void (^)(NSError *))completion;
@end

NS_ASSUME_NONNULL_END
