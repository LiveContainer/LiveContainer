//
//  LCMultitaskXPCService.m
//  LiveContainer
//
//  Created by Duy Tran on 29/4/26
//

#import <Foundation/Foundation.h>
#import "LCMultitaskXPCService.h"

@implementation LCMultitaskXPCServiceHandler
- (instancetype)initWithConnection:(NSXPCConnection *)connection {
    self = [super init];
    self.connection = connection;
    return self;
}

// LCMultitaskXPCServiceProtocol
- (void)createEndpointInjectorWithSelfToken:(NSString *)selfEnv sourceToken:(NSString *)sourceEnv {
    if (self.injector) return;
    self.injector = [PrivClass(BSServiceConnectionEndpointInjector) injectorWithConfigurator:^(id<BSServiceConnectionEndpointInjectorConfiguring> config) {
        [config setTarget:[RBSTarget targetWithPid:self.connection.processIdentifier environmentIdentifier:selfEnv]];
        [config setInheritingEnvironment:sourceEnv];
        [config setAdditionalAttributes:@[
            [PrivClass(RBSHereditaryGrant) grantWithNamespace:@"com.apple.frontboard.visibility" sourceEnvironment:sourceEnv attributes:nil]
        ]];
    }];
}

- (void)destroyEndpointInjector {
    [self.injector invalidate];
    self.injector = nil;
}

- (void)dealloc {
    [self destroyEndpointInjector];
}
@end

@implementation LCMultitaskXPCService
+ (instancetype)sharedInstance {
    static LCMultitaskXPCService* instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [LCMultitaskXPCService new];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    self.listener = [NSXPCListener anonymousListener];
    self.listener.delegate = self;
    [self.listener resume];
    return self;
}

// NSXPCListenerDelegate
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(LCMultitaskXPCServiceProtocol)];
    newConnection.exportedObject = [[LCMultitaskXPCServiceHandler alloc] initWithConnection:newConnection];
    [newConnection resume];
    return YES;
}
@end
