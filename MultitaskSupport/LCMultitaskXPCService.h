//
//  LCMultitaskXPCService.h
//  LiveContainer
//
//  Created by Duy Tran on 29/4/26.
//

#import <Foundation/Foundation.h>
#import "UIKitPrivate+MultitaskSupport.h"

@protocol LCMultitaskXPCServiceProtocol <NSObject>
- (void)createEndpointInjectorWithSelfToken:(NSString *)selfEnv sourceToken:(NSString *)sourceEnv;
- (void)destroyEndpointInjector;
@end

@interface LCMultitaskXPCServiceHandler : NSObject<LCMultitaskXPCServiceProtocol>
@property(nonatomic) NSXPCConnection *connection;
@property(nonatomic) BSServiceConnectionEndpointInjector *injector;
- (instancetype)initWithConnection:(NSXPCConnection *)connection;
@end

@interface LCMultitaskXPCService : NSObject<NSXPCListenerDelegate>
@property(nonatomic) NSXPCListener *listener;
+ (instancetype)sharedInstance;
@end
