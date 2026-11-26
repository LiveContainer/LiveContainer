#pragma once

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <xpc/xpc.h>

NS_ASSUME_NONNULL_BEGIN
// The registered Mach port is a pipe rendezvous for an anonymous XPC listener.
extern mach_port_t bootstrap_port;
extern kern_return_t bootstrap_check_in(mach_port_t bootstrap, const char *name, mach_port_t *port);
extern kern_return_t bootstrap_look_up(mach_port_t bootstrap, const char *name, mach_port_t *port);
extern xpc_object_t _Nullable xpc_pipe_create_from_port(mach_port_t port, uint32_t flags) XPC_RETURNS_RETAINED;
// Pipe outputs transfer owned objects; use strong out-pointers for ARC.
extern int xpc_pipe_routine(xpc_object_t pipe, xpc_object_t message, xpc_object_t _Nullable __strong * _Nonnull reply);
extern int xpc_pipe_receive(mach_port_t port, xpc_object_t _Nullable __strong * _Nonnull message, uint64_t flags);
extern int xpc_pipe_routine_reply(xpc_object_t reply);
extern void xpc_dictionary_get_audit_token(xpc_object_t dictionary, audit_token_t *token);
// The SDK marks this libxpc entry point unavailable on iOS.
extern pid_t LCXPCConnectionGetPID(xpc_connection_t connection) __asm("_xpc_connection_get_pid");
extern void xpc_connection_kill(xpc_connection_t connection, int signal);

extern void xpc_init_services(void);
extern xpc_object_t _Nullable launch_copy_extension_properties_for_pid(pid_t pid) XPC_RETURNS_RETAINED;

@interface NSXPCListenerEndpoint (LCLiveProcessEndpoint)
- (xpc_endpoint_t)_endpoint;
- (void)_setEndpoint:(xpc_endpoint_t)endpoint;
@end

NS_ASSUME_NONNULL_END

extern void launch_extension_check_in_live_4UIKit(void);
