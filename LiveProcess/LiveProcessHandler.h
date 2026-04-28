//
//  LiveProcessHandler.h
//  LiveContainer
//
//  Created by Duy Tran on 29/4/26.
//

#import "../MultitaskSupport/LCMultitaskXPCService.h"

@interface LiveProcessHandler : NSObject<NSExtensionRequestHandling>
@property(nonatomic) NSXPCConnection* connection;
@property(nonatomic) id<LCMultitaskXPCServiceProtocol> server;

+ (LiveProcessHandler *)sharedInstance;
- (void)initializeMultitaskEndpoint:(NSXPCListenerEndpoint *)endpoint;
@end

@interface NSExtensionContext(Private)
- (LiveProcessHandler *)_principalObject;
@end
