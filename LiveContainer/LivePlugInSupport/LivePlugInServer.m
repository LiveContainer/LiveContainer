//
//  LivePlugInServer.m
//  LiveContainer
//

#import "LivePlugInServer.h"
#import "PlugInKitPrivate.h"
#import "PrivateXPC.h"
#import "LCSharedUtils.h"
#import "utils.h"
#import <dlfcn.h>
#import <signal.h>

@interface LCLivePlugIn ()

@property(nonatomic) NSUUID *identifier;
@property(nonatomic) NSData *configurationData;
@property(nonatomic) xpc_connection_t connection;
@property(nonatomic) xpc_object_t configurationRequest;
@property(nonatomic) BOOL finished;
@end

static NSMutableDictionary<NSUUID *, LCLivePlugIn *> *launches;
static NSMutableDictionary<NSNumber *, xpc_connection_t> *pendingConnections;
static NSMutableDictionary<NSNumber *, xpc_object_t> *pendingRequests;
static xpc_connection_t listener;
static dispatch_source_t bootstrapSource;
static NSError *listenerError;

static NSError *LCProcessError(NSString *description) {
    return [NSError errorWithDomain:@"LivePlugIn" code:2 userInfo:@{NSLocalizedDescriptionKey: description}];
}


@implementation LCLivePlugIn

+ (LCLivePlugIn *)processWithPID:(pid_t)pid {
    if (pid <= 0) return nil;
    for (LCLivePlugIn *process in launches.allValues) {
        if (process.pid == pid) return process;
    }
    return nil;
}

+ (void)resolvePendingRequests {
    BOOL isSpawning = NO;
    for (LCLivePlugIn *process in launches.allValues) {
        if (!process.pid) isSpawning = YES;
    }
    for (NSNumber *pid in pendingRequests.allKeys) {
        LCLivePlugIn *process = [self processWithPID:pid.intValue];
        xpc_connection_t peer = pendingConnections[pid];
        xpc_object_t request = pendingRequests[pid];
        if (process && !process.connection) {
            process.connection = peer;
            process.configurationRequest = request;
            [process deliverConfiguration];
        } else {
            // readyPlugIns can return the PID after the child's first request.
            continue;
        }
        [pendingConnections removeObjectForKey:pid];
        [pendingRequests removeObjectForKey:pid];
    }
}

+ (void)startServer {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        launches = [NSMutableDictionary new];
        pendingConnections = [NSMutableDictionary new];
        pendingRequests = [NSMutableDictionary new];
        NSString *appGroup = LCSharedUtils.appGroupID;
        if (!appGroup.length) {
            listenerError = LCProcessError(@"Missing app group for LivePlugIn communication");
            return;
        }

        // LC1 and LC2 can both host processes in the same app group.
        NSString *serviceName = LCLivePlugInServiceName(appGroup, getpid());
        mach_port_t service = MACH_PORT_NULL;
        kern_return_t status = bootstrap_check_in(bootstrap_port, serviceName.UTF8String, &service);

        if (status != KERN_SUCCESS || !MACH_PORT_VALID(service)) {
            listenerError = LCProcessError([NSString stringWithFormat:@"Unable to register the LivePlugIn service (bootstrap_check_in: %d)", status]);
            return;
        }
        dispatch_queue_t xpcQueue = dispatch_queue_create("com.godbot100.echolauncher.LivePlugIn.xpc.handling", DISPATCH_QUEUE_SERIAL);
        listener = xpc_connection_create(NULL, xpcQueue);
        if (!listener) {
            mach_port_mod_refs(mach_task_self(), service, MACH_PORT_RIGHT_RECEIVE, -1);
            listenerError = LCProcessError(@"Unable to create the LivePlugIn XPC listener");
            return;
        }
        xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
            if (xpc_get_type(peer) != XPC_TYPE_CONNECTION) {
                listenerError = LCProcessError(@"The LivePlugIn XPC listener was invalidated");
                if (bootstrapSource) dispatch_source_cancel(bootstrapSource);
                for (xpc_connection_t connection in pendingConnections.allValues) xpc_connection_cancel(connection);
                [pendingConnections removeAllObjects];
                [pendingRequests removeAllObjects];
                for (LCLivePlugIn *process in launches.allValues) {
                    [process failWithError:listenerError];
                }
                return;
            }

            xpc_connection_set_target_queue(peer, xpcQueue);
            __weak xpc_connection_t weakPeer = peer;
            xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
                xpc_connection_t peer = weakPeer;
                if (!peer) return;
                NSNumber *pid = @(LCXPCConnectionGetPID(peer));
                LCLivePlugIn *process = [LCLivePlugIn processWithPID:pid.intValue];
                if (xpc_get_type(event) == XPC_TYPE_ERROR) {
                    if (pendingConnections[pid] == peer) {
                        [pendingConnections removeObjectForKey:pid];
                        [pendingRequests removeObjectForKey:pid];
                    }

                    return;
                }
                if (xpc_get_type(event) != XPC_TYPE_DICTIONARY) return;
                int64_t command = xpc_dictionary_get_int64(event, "cmd");
                if (command == LCLivePlugInCommandLaunchConfiguration) {
                    if (pid.intValue <= 0 || process.connection || pendingConnections[pid]) {
                        xpc_connection_cancel(peer);
                        return;
                    }
                    pendingConnections[pid] = peer;
                    pendingRequests[pid] = event;
                    [LCLivePlugIn resolvePendingRequests];
                } else if (command == LCLivePlugInCommandError && process.connection == peer) {
                    const char *message = xpc_dictionary_get_string(event, "error");
                    xpc_object_t reply = xpc_dictionary_create_reply(event);
                    if (reply) xpc_connection_send_message(peer, reply);
                    [process failWithError:LCProcessError(message ? @(message) : @"LivePlugIn failed to launch")];
                } else {
                    xpc_connection_cancel(peer);
                }
            });
            xpc_connection_resume(peer);
            // Do not retain unauthenticated connections indefinitely.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, LCLivePlugInLaunchTimeout * NSEC_PER_SEC), xpcQueue, ^{
                NSNumber *pid = @(LCXPCConnectionGetPID(peer));
                if ([LCLivePlugIn processWithPID:pid.intValue].connection != peer) xpc_connection_cancel(peer);
            });
        });
        xpc_connection_resume(listener);

        // bootstrap_check_in supplies the receive right. libxpc's named listener
        // registration is unavailable here, so hand out an anonymous endpoint over a pipe.
        xpc_endpoint_t endpoint = xpc_endpoint_create(listener);
        dispatch_queue_t queue = dispatch_queue_create("com.godbot100.echolauncher.LivePlugIn.bootstrap", DISPATCH_QUEUE_SERIAL);
        bootstrapSource = endpoint ? dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, service, 0, queue) : nil;
        if (!bootstrapSource) {
            xpc_connection_cancel(listener);
            listener = nil;
            mach_port_mod_refs(mach_task_self(), service, MACH_PORT_RIGHT_RECEIVE, -1);
            listenerError = LCProcessError(@"Unable to create the LivePlugIn bootstrap receiver");
            return;
        }
        dispatch_source_set_event_handler(bootstrapSource, ^{ @autoreleasepool {
            xpc_object_t request = nil;
            int error = xpc_pipe_receive(service, &request, 0);
            if (error || !request || xpc_get_type(request) != XPC_TYPE_DICTIONARY) return;
            xpc_object_t reply = xpc_dictionary_create_reply(request);
            if (!reply) return;
            audit_token_t audit = {{0}};
            xpc_dictionary_get_audit_token(request, &audit);
            if (audit.val[5] && xpc_dictionary_get_int64(request, "cmd") == LCLivePlugInCommandConnect) {
                xpc_dictionary_set_value(reply, "listener", endpoint);
            } else {
                xpc_dictionary_set_string(reply, "error", "Invalid LivePlugIn connection request");
            }
            xpc_pipe_routine_reply(reply);
        } });
        dispatch_source_set_cancel_handler(bootstrapSource, ^{
            mach_port_mod_refs(mach_task_self(), service, MACH_PORT_RIGHT_RECEIVE, -1);
        });
        dispatch_resume(bootstrapSource);
    });
}

- (instancetype)initWithUUID:(NSUUID*)identifier configuration:(NSDictionary *)configuration {
    _identifier = identifier;
    NSError* error;
    _configurationData = [NSKeyedArchiver archivedDataWithRootObject:configuration requiringSecureCoding:NO error:&error];
    _finished = NO;
    
    launches[self.identifier] = self;

    return self;
}

- (void)deliverConfiguration {
    if (!self.pid || !self.configurationRequest || self.finished) return;
    if (LCXPCConnectionGetPID(self.connection) != self.pid) {
        // The kernel-supplied peer PID must match PluginKit's launched instance.
        xpc_connection_cancel(self.connection);
        self.connection = nil;
        self.configurationRequest = nil;
        return;
    }
    xpc_object_t reply = xpc_dictionary_create_reply(self.configurationRequest);
    if (!reply) {
        [self failWithError:LCProcessError(@"Invalid LivePlugIn launch request")];
        return;
    }
    xpc_dictionary_set_data(reply, "payload", self.configurationData.bytes, self.configurationData.length);
    xpc_connection_send_message(self.connection, reply);
    self.configurationRequest = nil;
    self.configurationData = nil;

}

- (void)failWithError:(NSError *)error {
    [NSUserDefaults.lcUserDefaults setObject:[NSString stringWithFormat:@"LivePlugIn encountered an error: %@", error.localizedDescription] forKey:@"error"];
}

@end
