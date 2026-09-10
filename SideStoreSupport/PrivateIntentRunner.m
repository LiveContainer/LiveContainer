#import "PrivateIntentRunner.h"
#import "AppIntentsPrivate.h"

#import <bsm/audit.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach/task_info.h>

static NSString *const PrivateIntentErrorDomain = @"PrivateIntentRunner";



static NSError *PrivateIntentError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:PrivateIntentErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

@implementation PrivateIntentRunner

+ (NSProgress *)runWithIdentifier:(NSString *)identifier
                  mangledTypeName:(NSString *)mangledTypeName
                       completion:(PrivateIntentCompletion)completion {
    NSError *error = nil;
    audit_token_t auditToken = {};

    Class actionClass = NSClassFromString(@"LNAction");
    Class optionsClass = NSClassFromString(@"LNActionExecutorOptions");
    Class contextClass = NSClassFromString(@"LNAppContext");
    if (actionClass == Nil || optionsClass == Nil || contextClass == Nil) {
        completion(nil, PrivateIntentError(3, @"Required private class is unavailable"));
        return nil;
    }

    LNAction* action = [[actionClass alloc] initWithIdentifier:identifier
                                                    mangledTypeName:mangledTypeName
                                                      openAppWhenRun:NO
                                                         parameters:@[]];
    LNActionExecutorOptions* options = [[optionsClass alloc] init];
    options.clientLabel = @"PrivateProgressDemo";
    options.kind = 2; // LNActionExecutorOptions kind: App Shortcut
    options.donateToTranscript = NO;

    LNAppContext* context = [[contextClass alloc] init];
    NSProgress *reportingProgress = [NSProgress progressWithTotalUnitCount:1];
    [context performAction:action
                   options:options
         reportingProgress:reportingProgress
                  delegate:nil
                auditToken:&auditToken
         completionHandler:completion];
    return reportingProgress;
}

@end
