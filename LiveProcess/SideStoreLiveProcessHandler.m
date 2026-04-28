//
//  SideStoreLiveProcessHandler.m
//  LiveContainer
//
//  Created by s s on 2025/7/20.
//

#include "../SideStore/XPCServer.h"

static LiveProcessSideStoreHandler* sharedHandler = nil;

@implementation LiveProcessSideStoreHandler

+ (void)initializeWithEndpoint:(NSXPCListenerEndpoint *)endpoint {
    NSXPCConnection* connection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(RefreshServer)];
    connection.interruptionHandler = ^{
        NSLog(@"interrupted!!!");
    };
    [connection activate];
    self.shared.server = connection.remoteObjectProxy;
    self.shared.connection = connection;
}

+ (LiveProcessSideStoreHandler*)shared {
    if(!sharedHandler) {
        sharedHandler = [LiveProcessSideStoreHandler new];
    }
    return sharedHandler;
}


@end
