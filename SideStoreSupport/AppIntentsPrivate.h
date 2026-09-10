//
//  AppIntents.h
//  LiveContainer
//
//  Created by s s on 2026/8/5.
//
@import Foundation;
@import AppIntents;

@interface LNAction
- (instancetype)initWithIdentifier:(NSString *)identifier
                    mangledTypeName:(NSString *)mangledTypeName
                      openAppWhenRun:(BOOL)openAppWhenRun
                         parameters:(NSArray *)parameters;
@end

@interface LNActionExecutorOptions
- (instancetype)init;
@property(nonatomic, copy) NSString *clientLabel;
@property(nonatomic) NSInteger kind;
@property(nonatomic) BOOL donateToTranscript;
@end

@interface LNAppContext
- (instancetype)init;
- (void)performAction:(id)action
               options:(id)options
     reportingProgress:(NSProgress *)progress
              delegate:(nullable id)delegate
            auditToken:(audit_token_t *)auditToken
     completionHandler:(PrivateIntentCompletion)completion;
@end
