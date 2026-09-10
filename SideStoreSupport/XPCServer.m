//
//  XPCServer.m
//  LiveContainer
//
//  Created by s s on 2025/7/20.
//

#import <Foundation/Foundation.h>
#import "XPCServer.h"

@interface ServerDelegate : NSObject <NSXPCListenerDelegate>
@property NSObject<RefreshServer>* reporter;
@end

@implementation ServerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(RefreshServer)];
    newConnection.exportedObject = self.reporter;
    [self.reporter onConnection:newConnection];
    [newConnection resume];
    return YES;
}

@end

ServerDelegate* staticDelegate = nil;

NSXPCListener* startAnonymousListener(NSObject<RefreshServer>* reporter) {
    ServerDelegate *delegate = [ServerDelegate new];
    staticDelegate = delegate;
    delegate.reporter = reporter;
    NSXPCListener *listener = [NSXPCListener anonymousListener];
    listener.delegate = delegate;
    [listener resume];
    return listener;
}

NSData* bookmarkForURL(NSURL* url) {
    return [url bookmarkDataWithOptions:(1<<11) includingResourceValuesForKeys:0 relativeToURL:0 error:0];
}
