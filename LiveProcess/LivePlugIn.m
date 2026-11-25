//
//  LivePlugIn.m
//  LiveProcess
//
//  Created by Duy Tran on 3/5/25.
//

#import <dlfcn.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import "../LiveContainer/utils.h"
#import "../LiveContainer/Tweaks/Tweaks.h"
#import "../SideStoreSupport/XPCServer.h"
#import "../LiveContainer/LivePlugInSupport/PrivateXPC.h"
#import "../LiveContainer/LivePlugInSupport/LivePlugInServer.h"
#import "../LiveContainer/LCSharedUtils.h"

@interface LivePlugInHandler : NSObject

@end

@implementation LivePlugInHandler
static NSDictionary *retrievedAppInfo;
static xpc_connection_t hostConnection;

+ (NSDictionary *)retrievedAppInfo {
    return retrievedAppInfo;
}

+ (void)reportLivePlugInError:(NSString *)error {
    if (!hostConnection) {
        return;
    }
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_int64(message, "cmd", LCLivePlugInCommandError);
    xpc_dictionary_set_string(message, "error", error.UTF8String);
    dispatch_semaphore_t delivered = dispatch_semaphore_create(0);
    xpc_connection_send_message_with_reply(hostConnection, message, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(xpc_object_t reply) {
        dispatch_semaphore_signal(delivered);
    });
    dispatch_semaphore_wait(delivered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
}

+ (NSString*)retrieveLaunchConfiguration {
    xpc_object_t properties = launch_copy_extension_properties_for_pid(getpid());
    pid_t expectedHostPID = (pid_t)xpc_dictionary_get_int64(properties, "XPCExtensionHostPID");

    NSString *appGroup = LCSharedUtils.appGroupID;

    NSString *service = LCLivePlugInServiceName(appGroup, expectedHostPID);
    mach_port_t port = MACH_PORT_NULL;
    kern_return_t status = bootstrap_look_up(bootstrap_port, service.UTF8String, &port);
    if (status != KERN_SUCCESS || !MACH_PORT_VALID(port)) {
        if (MACH_PORT_VALID(port)) mach_port_deallocate(mach_task_self(), port);
        return @"bootstrap_look_up failed";
    }
    xpc_object_t pipe = xpc_pipe_create_from_port(port, 0);
    // The pipe retains its own send reference.
    mach_port_deallocate(mach_task_self(), port);

    dispatch_queue_t queue = dispatch_queue_create("com.godbot100.echolauncher.liveprocess.launch", DISPATCH_QUEUE_SERIAL);
//    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, LCLiveProcessLaunchTimeout * NSEC_PER_SEC);
    dispatch_time_t deadline = DISPATCH_TIME_FOREVER;
    dispatch_semaphore_t connected = dispatch_semaphore_create(0);
    __block xpc_endpoint_t listenerEndpoint;
    // A pipe routine has no timeout. Bound startup's wait and keep a late reply
    // local to this block, so it cannot revive an abandoned connection.
    dispatch_async(queue, ^{ @autoreleasepool {
        xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
        xpc_dictionary_set_int64(request, "cmd", LCLivePlugInCommandConnect);
        xpc_object_t reply = nil;
        int error = xpc_pipe_routine(pipe, request, &reply);
        if (!error && reply && xpc_get_type(reply) == XPC_TYPE_DICTIONARY) {
            audit_token_t audit = {{0}};
            xpc_dictionary_get_audit_token(reply, &audit);
            xpc_object_t endpoint = xpc_dictionary_get_value(reply, "listener");
            if ((pid_t)audit.val[5] == expectedHostPID && endpoint && xpc_get_type(endpoint) == XPC_TYPE_ENDPOINT) {
                listenerEndpoint = endpoint;
            }
        }
        dispatch_semaphore_signal(connected);
    } });
    if (dispatch_semaphore_wait(connected, deadline) != 0 || !listenerEndpoint) {
        return @"Unable to connect to the LiveProcess bootstrap service";
    }
    xpc_connection_t connection = xpc_connection_create_from_endpoint(listenerEndpoint);

    hostConnection = connection;
    xpc_connection_set_target_queue(connection, queue);
    __block BOOL configured = NO;
    __block BOOL acceptingConfiguration = YES;
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        if (xpc_get_type(event) == XPC_TYPE_ERROR) {
            
            return;
        }
        
    });
    xpc_connection_resume(connection);
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_int64(message, "cmd", LCLivePlugInCommandLaunchConfiguration);
    dispatch_semaphore_t received = dispatch_semaphore_create(0);
    __block NSDictionary *configuration;
    xpc_connection_send_message_with_reply(connection, message, queue, ^(xpc_object_t reply) {
        if (!acceptingConfiguration) return;
        if (LCXPCConnectionGetPID(connection) == expectedHostPID && xpc_get_type(reply) == XPC_TYPE_DICTIONARY) {
            size_t length = 0;
            const void *bytes = xpc_dictionary_get_data(reply, "payload", &length);
            if (bytes && length) {
                NSData *data = [NSData dataWithBytes:bytes length:length];
                NSError* err;
                
                NSSet *allowedClasses = [NSSet setWithArray:@[
                    [NSDictionary class],
                    [NSArray class],
                    [NSString class],
                    [NSNumber class],
                    [NSDate class],
                    [NSData class]
                ]];
                
                NSDictionary *payload = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowedClasses
                                                                            fromData:data
                                                                               error:&err];
                
                if ([payload isKindOfClass:NSDictionary.class]) {
                    configuration = payload;
                }
            }
        }
        configured = configuration != nil;
        dispatch_semaphore_signal(received);
    });
    
    if (dispatch_semaphore_wait(received, deadline) != 0) {
        dispatch_sync(queue, ^{
            acceptingConfiguration = NO;
            configured = NO;
            xpc_connection_cancel(connection);
        });
        hostConnection = nil;
        return @"Timed out retrieving LiveProcess launch parameters";
    }
    if (!configuration) {
        xpc_connection_cancel(connection);
        hostConnection = nil;
        return @"LivePlugIn configuration failed";
    }

    retrievedAppInfo = configuration;
    return nil;
}

@end

extern NSString *LCRunGuestExtension(NSDictionary *request, int argc, char *argv[], char *envp[], char *apple[]);

int LivePlugInMain(int argc, char *argv[], char *envp[], char *apple[]) {
    NSString* configError = [LivePlugInHandler retrieveLaunchConfiguration];
    if (configError) {
        [LivePlugInHandler reportLivePlugInError:configError];
        return 1;
    }

    NSDictionary *appInfo = LivePlugInHandler.retrievedAppInfo;

    configError = LCRunGuestExtension(appInfo, argc, argv, envp, apple);
    
    if(configError) {
        [LivePlugInHandler reportLivePlugInError:configError];
    }
    return 1;
}
