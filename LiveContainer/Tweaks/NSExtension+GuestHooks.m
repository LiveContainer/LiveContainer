#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import "../FoundationPrivate.h"
#import "../utils.h"
#import "Tweaks.h"

static NSURL *guestExtensionsAppURL;
static NSURL *guestExtensionsContainerURL;
static id (*originalExtensionWithIdentifier)(id, SEL, NSString *, NSError **);
static id (*originalExtensionWithIdentifierExcludingDisabled)(id, SEL, NSString *, BOOL, NSError **);
typedef id (*LCExtensionInitializer)(id __attribute__((ns_consumed)), SEL, id) __attribute__((ns_returns_retained));
static LCExtensionInitializer originalInitWithPKPlugin;
static NSMutableSet *activeGuestExtensions;

static NSError *LCGuestExtensionError(NSString *message) {
    return [NSError errorWithDomain:@"LCGuestExtension" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

// Subclass the app's declared context rather than replacing it: vendor methods
// and protocol interfaces remain available, including isKindOfClass checks.
@protocol LCGuestExtensionHostHandshake
- (void)lcConnectWithEndpoint:(NSXPCListenerEndpoint *)endpoint completion:(void (^)(void))completion;
@end

@interface LCGuestExtensionContextState : NSObject <NSXPCListenerDelegate, LCGuestExtensionHostHandshake>
@property(nonatomic, copy) NSArray *inputItems;
@property(nonatomic, strong) NSExtensionContext *context;
@property(nonatomic, strong) NSExtensionContext *systemContext;
@property(nonatomic, strong) NSXPCListener *listener;
@property(nonatomic, strong) NSXPCConnection *connection;
@property(nonatomic, strong) NSXPCConnection *controlConnection;
@property(nonatomic) BOOL usesHandshake;
@property(nonatomic) BOOL vendorListener;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL cancelled;
- (void)invalidate;
@end

static char guestContextStateKey;
static LCGuestExtensionContextState *LCContextState(id context) {
    return objc_getAssociatedObject(context, &guestContextStateKey);
}

@interface LCGuestExtensionContext : NSExtensionContext
@end

@implementation LCGuestExtensionContext
- (NSArray *)inputItems {
    return LCContextState(self).inputItems ?: @[];
}
- (NSXPCConnection *)_auxiliaryConnection {
    return LCContextState(self).connection;
}
- (void)completeRequestReturningItems:(NSArray *)items completionHandler:(void (^)(BOOL))completionHandler {
    [LCContextState(self).systemContext completeRequestReturningItems:items completionHandler:completionHandler];
}
- (void)cancelRequestWithError:(NSError *)error {
    [LCContextState(self).systemContext cancelRequestWithError:error];
}
@end

static NSExtensionContext *LCCreateGuestContext(Class base, LCGuestExtensionContextState *state) {
    if (![base isSubclassOfClass:NSExtensionContext.class]) return nil;
    @synchronized (NSExtensionContext.class) {
        NSString *name = [@"LCGuest_" stringByAppendingString:NSStringFromClass(base)];
        Class subclass = NSClassFromString(name);
        if (!subclass) {
            subclass = objc_allocateClassPair(base, name.UTF8String, 0);
            if (!subclass) return nil;
            for (NSString *selector in @[@"inputItems", @"_auxiliaryConnection", @"completeRequestReturningItems:completionHandler:", @"cancelRequestWithError:"]) {
                Method method = class_getInstanceMethod(LCGuestExtensionContext.class, NSSelectorFromString(selector));
                class_addMethod(subclass, method_getName(method), method_getImplementation(method), method_getTypeEncoding(method));
            }
            objc_registerClassPair(subclass);
        }
        NSExtensionContext *context = [subclass new];
        objc_setAssociatedObject(context, &guestContextStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state.context = context;
        return context;
    }
}

static NSXPCInterface *LCAuxiliaryInterface(Class contextClass, BOOL host) {
    SEL selector = host ? @selector(_extensionAuxiliaryHostProtocol) : @selector(_extensionAuxiliaryVendorProtocol);
    return [contextClass respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(contextClass, selector) : nil;
}

static void LCConnectGuestContext(LCGuestExtensionContextState *state, Class contextClass, NSDictionary *request) {
    NSXPCListenerEndpoint *endpoint = request[@"auxiliaryEndpoint"];
    if (!endpoint) return;
    state.usesHandshake = [request[@"auxiliaryHandshake"] boolValue];
    if (state.usesHandshake) {
        // NSXPC connects lazily. Publish a vendor listener over a separate LC
        // control channel so the host can initiate calls even for a silent
        // donor. Keep the app's interfaces (and their class/proxy rules) intact.
        state.vendorListener = YES;
        state.listener = NSXPCListener.anonymousListener;
        state.listener.delegate = state;
        [state.listener resume];
        state.controlConnection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
        state.controlConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(LCGuestExtensionHostHandshake)];
        [state.controlConnection resume];
        [(id<LCGuestExtensionHostHandshake>)state.controlConnection.remoteObjectProxy lcConnectWithEndpoint:state.listener.endpoint completion:^{}];
        return;
    }
    state.connection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
    state.connection.remoteObjectInterface = LCAuxiliaryInterface(contextClass, YES);
    state.connection.exportedInterface = LCAuxiliaryInterface(contextClass, NO);
    state.connection.exportedObject = state.context;
    [state.connection resume];
}

@implementation LCGuestExtensionContextState
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    @synchronized (self) {
        if (self.listener != listener) return NO;
        if (self.vendorListener) {
            if (self.connection) return NO;
            connection.exportedInterface = LCAuxiliaryInterface(self.context.class, NO);
            connection.remoteObjectInterface = LCAuxiliaryInterface(self.context.class, YES);
            connection.exportedObject = self.context;
            self.connection = connection;
        } else {
            if (self.controlConnection) return NO;
            connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(LCGuestExtensionHostHandshake)];
            connection.exportedObject = self;
            self.controlConnection = connection;
        }
        [connection resume];
        return YES;
    }
}
- (void)lcConnectWithEndpoint:(NSXPCListenerEndpoint *)endpoint completion:(void (^)(void))completion {
    @synchronized (self) {
        if (self.listener && !self.vendorListener && !self.connection) {
            self.connection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
            self.connection.exportedInterface = LCAuxiliaryInterface(self.context.class, YES);
            self.connection.remoteObjectInterface = LCAuxiliaryInterface(self.context.class, NO);
            self.connection.exportedObject = self.context;
            [self.connection resume];
        }
    }
    completion();
}
- (void)invalidate {
    @synchronized (self) {
        [self.listener invalidate];
        [self.connection invalidate];
        [self.controlConnection invalidate];
        self.listener = nil;
        self.connection = nil;
        self.controlConnection = nil;
        self.context = nil;
    }
}
@end

// Only our _initWithPKPlugin: hook consumes this token. It keeps independent
// donor instances tied to the guest bundle instead of the system LiveProcess.
@interface LCGuestExtensionPlugin : NSObject
@property(nonatomic, strong) NSBundle *bundle;
@end
@implementation LCGuestExtensionPlugin
@end

// Only the selectors used by the JIT helper and RAM donor are implemented.
// Each proxy owns a real NSExtension, preserving system request IDs and PIDs.
@interface LCGuestExtension : NSObject
@property(nonatomic, strong) NSExtension *extension;
@property(nonatomic, strong) NSBundle *bundle;
@property(nonatomic, copy) NSArray *preferredLanguages;
@property(nonatomic, copy) void (^completionBlock)(NSUUID *, NSArray *);
@property(nonatomic, copy) void (^cancellationBlock)(NSUUID *, NSError *);
@property(nonatomic, copy) void (^interruptionBlock)(NSUUID *);
@property(nonatomic, strong) NSMutableSet<NSUUID *> *requests;
@property(nonatomic, strong) NSMutableSet<NSUUID *> *finishedRequests;
@property(nonatomic) NSUInteger pendingRequests;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, strong) NSMutableDictionary<NSUUID *, LCGuestExtensionContextState *> *contexts;
@end

@implementation LCGuestExtension

- (void)finishRequest:(NSUUID *)identifier {
    @synchronized (activeGuestExtensions) {
        if (identifier) {
            if (![self.requests containsObject:identifier] && self.pendingRequests) [self.finishedRequests addObject:identifier];
            [self.requests removeObject:identifier];
            [self.contexts[identifier] invalidate];
            [self.contexts removeObjectForKey:identifier];
        }
        if (self.pendingRequests == 0 && self.requests.count == 0) {
            [activeGuestExtensions removeObject:self];
        }
    }
}

- (void)setRequestCompletionBlock:(void (^)(NSUUID *, NSArray *))block {
    self.completionBlock = block;
}

- (void)setRequestCancellationBlock:(void (^)(NSUUID *, NSError *))block {
    self.cancellationBlock = block;
}

- (void)setRequestInterruptionBlock:(void (^)(NSUUID *))block {
    self.interruptionBlock = block;
}

- (NSExtensionItem *)prepareRequest:(NSArray *)items listenerEndpoint:(NSXPCListenerEndpoint *)endpoint contextState:(LCGuestExtensionContextState **)stateOut error:(NSError **)errorOut {
    NSError *error = nil;
    // Bundle identifiers are metadata from an imported app. Encode them as one
    // path component so a malformed identifier cannot escape the subcontainer.
    NSString *component = [self.bundle.bundleIdentifier stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
    if (component.length == 0) {
        if (errorOut) *errorOut = LCGuestExtensionError(@"The extension has no bundle identifier");
        return nil;
    }
    NSURL *containerURL = [[guestExtensionsContainerURL URLByAppendingPathComponent:@"Extensions" isDirectory:YES] URLByAppendingPathComponent:component isDirectory:YES];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *directory in @[@"Documents", @"Library/Caches", @"Library/Preferences", @"tmp"]) {
        if (![fm createDirectoryAtURL:[containerURL URLByAppendingPathComponent:directory] withIntermediateDirectories:YES attributes:nil error:&error]) break;
    }
    NSMutableArray *bookmarks = [NSMutableArray array];
    NSString *appGroupPath;
    if ([NSUserDefaults.guestContainerInfo[@"isolateAppGroup"] boolValue]) {
        appGroupPath = [guestExtensionsContainerURL.path stringByAppendingPathComponent:@"LCAppGroup"];
    } else if (NSUserDefaults.lcAppGroupPath.length) {
        appGroupPath = [NSUserDefaults.lcAppGroupPath stringByAppendingPathComponent:@"LiveContainer/Data/AppGroup"];
    } else {
        appGroupPath = [@(getenv("LC_HOME_PATH")) stringByAppendingPathComponent:@"Documents/Data/AppGroup"];
    }
    if (!error) [fm createDirectoryAtPath:appGroupPath withIntermediateDirectories:YES attributes:nil error:&error];
    if (!error) {
        for (NSURL *url in @[guestExtensionsAppURL, containerURL, [NSURL fileURLWithPath:appGroupPath isDirectory:YES]]) {
            NSData *bookmark = [url bookmarkDataWithOptions:(1 << 11) includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
            if (!bookmark) break;
            [bookmarks addObject:bookmark];
        }
    }
    if (error || bookmarks.count != 3) {
        if (errorOut) *errorOut = error ?: LCGuestExtensionError(@"Unable to share the extension container");
        return nil;
    }

    LCGuestExtensionContextState *state = [LCGuestExtensionContextState new];
    if (!endpoint && [self.bundle.infoDictionary[@"NSExtension"][@"NSExtensionContextClass"] length]) {
        NSString *hostName = self.bundle.infoDictionary[@"NSExtension"][@"NSExtensionContextHostClass"];
        Class hostClass = hostName.length ? NSClassFromString(hostName) : NSExtensionContext.class;
        if (!LCCreateGuestContext(hostClass, state)) {
            if (errorOut) *errorOut = LCGuestExtensionError(@"The extension's host context class is unavailable");
            return nil;
        }
        state.listener = NSXPCListener.anonymousListener;
        state.usesHandshake = YES;
        state.listener.delegate = state;
        [state.listener resume];
        endpoint = state.listener.endpoint;
    }
    NSExtensionItem *envelope = [NSExtensionItem new];
    envelope.userInfo = @{
        @"LCGuestExtension": @{
            @"bundlePath": self.bundle.bundlePath,
            @"appBundlePath": guestExtensionsAppURL.path,
            @"containerPath": containerURL.path,
            @"bookmarks": bookmarks,
            @"inputItems": items ?: @[],
            @"guestAppInfo": NSUserDefaults.guestAppInfo ?: @{},
            @"guestContainerInfo": NSUserDefaults.guestContainerInfo ?: @{},
            @"appGroupPath": NSUserDefaults.lcAppGroupPath ?: @"",
            @"parentContainerPath": guestExtensionsContainerURL.path,
            @"lcHomePath": @(getenv("LC_HOME_PATH")),
        }
    };
    if (endpoint) {
        NSMutableDictionary *payload = [envelope.userInfo[@"LCGuestExtension"] mutableCopy];
        payload[@"auxiliaryEndpoint"] = endpoint;
        payload[@"auxiliaryHandshake"] = @(state.usesHandshake);
        envelope.userInfo = @{@"LCGuestExtension": payload};
    }
    *stateOut = state;
    self.extension.preferredLanguages = self.preferredLanguages ?: @[];
    __weak typeof(self) weakSelf = self;
    [self.extension setRequestCompletionBlock:^(NSUUID *uuid, NSArray *returnedItems) {
        LCGuestExtension *proxy = weakSelf;
        if (proxy.completionBlock) proxy.completionBlock(uuid, returnedItems);
        [proxy finishRequest:uuid];
    }];
    [self.extension setRequestCancellationBlock:^(NSUUID *uuid, NSError *requestError) {
        LCGuestExtension *proxy = weakSelf;
        if (proxy.cancellationBlock) proxy.cancellationBlock(uuid, requestError);
        [proxy finishRequest:uuid];
    }];
    [self.extension setRequestInterruptionBlock:^(NSUUID *uuid) {
        LCGuestExtension *proxy = weakSelf;
        if (proxy.interruptionBlock) proxy.interruptionBlock(uuid);
        [proxy finishRequest:uuid];
    }];
    @synchronized (activeGuestExtensions) {
        state.generation = self.generation;
        self.pendingRequests++;
        [activeGuestExtensions addObject:self];
    }
    return envelope;
}

- (void)registerRequest:(NSUUID *)uuid contextState:(LCGuestExtensionContextState *)state {
    @synchronized (activeGuestExtensions) {
        self.pendingRequests--;
        state.cancelled = state.generation != self.generation;
        if (uuid && !state.cancelled && ![self.finishedRequests containsObject:uuid]) {
            [self.requests addObject:uuid];
            self.contexts[uuid] = state;
        } else {
            [state invalidate];
        }
        if (uuid) [self.finishedRequests removeObject:uuid];
    }
    if (uuid && state.cancelled) [self.extension cancelExtensionRequestWithIdentifier:uuid];
}

- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *))callback {
    [self beginExtensionRequestWithInputItems:items listenerEndpoint:nil completion:callback];
}

- (void)beginExtensionRequestWithInputItems:(NSArray *)items listenerEndpoint:(NSXPCListenerEndpoint *)endpoint completion:(void (^)(NSUUID *))callback {
    NSError *error = nil;
    LCGuestExtensionContextState *state;
    NSExtensionItem *envelope = [self prepareRequest:items listenerEndpoint:endpoint contextState:&state error:&error];
    if (!envelope) {
        if (self.cancellationBlock) self.cancellationBlock(nil, error);
        if (callback) callback(nil);
        return;
    }
    // Keep the proxy alive until the system has returned its request UUID.
    [self.extension beginExtensionRequestWithInputItems:@[envelope] completion:^(NSUUID *uuid) {
        LCGuestExtension *proxy = self;
        [proxy registerRequest:uuid contextState:state];
        // Do not dispatch to the main queue: RAM donors synchronously wait for
        // this callback, including when started from the guest's main thread.
        if (callback) callback(state.cancelled ? nil : uuid);
        [proxy finishRequest:nil];
    }];
}

- (NSUUID *)beginExtensionRequestWithInputItems:(NSArray *)items error:(NSError **)errorOut {
    NSError *error = nil;
    LCGuestExtensionContextState *state;
    NSExtensionItem *envelope = [self prepareRequest:items listenerEndpoint:nil contextState:&state error:&error];
    NSUUID *uuid = nil;
    if (envelope) {
        // Use the system's synchronous implementation. Waiting on our async
        // wrapper can deadlock when the caller is on the main thread.
        if ([self.extension respondsToSelector:_cmd]) {
            uuid = [self.extension beginExtensionRequestWithInputItems:@[envelope] error:&error];
        } else {
            error = LCGuestExtensionError(@"Synchronous extension requests are unavailable on this iOS version");
        }
        [self registerRequest:uuid contextState:state];
        if (state.cancelled) {
            uuid = nil;
            error = LCGuestExtensionError(@"The extension was terminated while starting the request");
        }
        [self finishRequest:nil];
    }
    if (!uuid && !error) error = LCGuestExtensionError(@"The extension request could not be started");
    if (errorOut) *errorOut = error;
    return uuid;
}

- (NSUUID *)beginRequestWithInputItems:(NSArray *)items {
    return [self beginExtensionRequestWithInputItems:items error:nil];
}

- (NSExtensionContext *)_extensionContextForUUID:(NSUUID *)identifier {
    @synchronized (activeGuestExtensions) {
        LCGuestExtensionContextState *state = self.contexts[identifier];
        @synchronized (state) {
            if (state.connection) return state.context;
        }
    }
    return nil;
}

- (void)cancelExtensionRequestWithIdentifier:(NSUUID *)identifier {
    [self.extension cancelExtensionRequestWithIdentifier:identifier];
    [self finishRequest:identifier];
}

- (id)_plugIn {
    LCGuestExtensionPlugin *plugin = [LCGuestExtensionPlugin new];
    plugin.bundle = self.bundle;
    return plugin;
}

- (int)pidForRequestIdentifier:(NSUUID *)identifier {
    return [self.extension pidForRequestIdentifier:identifier];
}

- (void)_kill:(int)signal {
    @synchronized (activeGuestExtensions) {
        self.generation++;
        for (LCGuestExtensionContextState *state in self.contexts.allValues) [state invalidate];
        [self.contexts removeAllObjects];
        [self.requests removeAllObjects];
        [activeGuestExtensions removeObject:self];
    }
    [self.extension _kill:signal];
}
@end

static NSBundle *LCFindGuestExtension(NSString *identifier) {
    NSURL *pluginsURL = [guestExtensionsAppURL URLByAppendingPathComponent:@"PlugIns" isDirectory:YES];
    NSArray<NSURL *> *plugins = [NSFileManager.defaultManager contentsOfDirectoryAtURL:pluginsURL includingPropertiesForKeys:nil options:0 error:nil];
    for (NSURL *url in plugins) {
        if (![url.pathExtension isEqualToString:@"appex"]) continue;
        NSBundle *bundle = [NSBundle bundleWithURL:url];
        if ([bundle.bundleIdentifier isEqualToString:identifier]) return bundle;
    }
    return nil;
}

static LCGuestExtension *LCCreateGuestExtensionWithObject(NSBundle *bundle, id allocated __attribute__((ns_consumed)), NSError **error) {
    NSBundle *liveProcess = [NSBundle bundleWithURL:[NSUserDefaults.lcMainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"LiveProcess.appex"]];
    if (!liveProcess.bundleIdentifier) {
        if (error) *error = LCGuestExtensionError(@"LiveProcess is missing. Reinstall LiveContainer and keep its extensions.");
        return nil;
    }
    Class cls = NSClassFromString(@"NSExtension");
    NSExtension *extension = originalExtensionWithIdentifier(cls, @selector(extensionWithIdentifier:error:), liveProcess.bundleIdentifier, error);
    if (!extension) return nil;
    // Foundation can cache discovery objects. Each proxy needs its own native
    // request callbacks and process lifetime, even for the same guest bundle.
    if (originalInitWithPKPlugin) {
        extension = originalInitWithPKPlugin(allocated ?: [cls alloc], NSSelectorFromString(@"_initWithPKPlugin:"), [extension _plugIn]);
        if (!extension) {
            if (error) *error = LCGuestExtensionError(@"Unable to create an independent LiveProcess extension");
            return nil;
        }
    }
    LCGuestExtension *proxy = [LCGuestExtension new];
    proxy.extension = extension;
    proxy.bundle = bundle;
    proxy.requests = [NSMutableSet set];
    proxy.finishedRequests = [NSMutableSet set];
    proxy.contexts = [NSMutableDictionary dictionary];
    if (error) *error = nil;
    return proxy;
}

static LCGuestExtension *LCCreateGuestExtension(NSBundle *bundle, NSError **error) {
    return LCCreateGuestExtensionWithObject(bundle, nil, error);
}

static id hook_extensionWithIdentifier(id cls, SEL selector, NSString *identifier, NSError **error) {
    NSBundle *bundle = LCFindGuestExtension(identifier);
    if (bundle) return LCCreateGuestExtension(bundle, error);
    return originalExtensionWithIdentifier(cls, selector, identifier, error);
}

static id hook_extensionWithIdentifierExcludingDisabled(id cls, SEL selector, NSString *identifier, BOOL exclude, NSError **error) {
    NSBundle *bundle = LCFindGuestExtension(identifier);
    if (bundle) return LCCreateGuestExtension(bundle, error);
    return originalExtensionWithIdentifierExcludingDisabled(cls, selector, identifier, exclude, error);
}

static id hook_initWithPKPlugin(id object __attribute__((ns_consumed)), SEL selector, id plugin) __attribute__((ns_returns_retained));
static id hook_initWithPKPlugin(id object __attribute__((ns_consumed)), SEL selector, id plugin) {
    if ([plugin isKindOfClass:LCGuestExtensionPlugin.class]) {
        return LCCreateGuestExtensionWithObject(((LCGuestExtensionPlugin *)plugin).bundle, object, nil);
    }
    return originalInitWithPKPlugin(object, selector, plugin);
}

void NSExtensionGuestHooksInit(NSURL *appURL, NSURL *containerURL) {
    if (NSUserDefaults.isLiveProcess) return;
    dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_LAZY | RTLD_GLOBAL);
    Method factory = class_getClassMethod(NSClassFromString(@"NSExtension"), @selector(extensionWithIdentifier:error:));
    if (!factory) return;
    guestExtensionsAppURL = appURL;
    guestExtensionsContainerURL = containerURL;
    activeGuestExtensions = [NSMutableSet set];
    Method initializer = class_getInstanceMethod(NSClassFromString(@"NSExtension"), NSSelectorFromString(@"_initWithPKPlugin:"));
    if (initializer) originalInitWithPKPlugin = (LCExtensionInitializer)method_setImplementation(initializer, (IMP)hook_initWithPKPlugin);
    originalExtensionWithIdentifier = (void *)method_setImplementation(factory, (IMP)hook_extensionWithIdentifier);
    Method excludingFactory = class_getClassMethod(NSClassFromString(@"NSExtension"), @selector(extensionWithIdentifier:excludingDisabledExtensions:error:));
    if (excludingFactory) originalExtensionWithIdentifierExcludingDisabled = (void *)method_setImplementation(excludingFactory, (IMP)hook_extensionWithIdentifierExcludingDisabled);
}

int LCRunGuestExtension(NSDictionary *request, NSExtensionContext *context) {
    NSString *error = LCPrepareGuestExtension(request);
    if (error) {
        [context cancelRequestWithError:LCGuestExtensionError(error)];
        CFRunLoopRun();
        return 1;
    }
    NSString *principalName = NSBundle.mainBundle.infoDictionary[@"NSExtension"][@"NSExtensionPrincipalClass"];
    Class principal = principalName.length ? NSClassFromString(principalName) : Nil;
    if (![principal instancesRespondToSelector:@selector(beginRequestWithExtensionContext:)]) {
        [context cancelRequestWithError:LCGuestExtensionError(@"The guest extension has no request handler")];
        CFRunLoopRun();
        return 1;
    }
    // Retain both for the lifetime of the process, including asynchronous work
    // and donors which intentionally never complete the extension request.
    static id<NSExtensionRequestHandling> handler;
    static LCGuestExtensionContextState *state;
    handler = [principal new];
    state = [LCGuestExtensionContextState new];
    state.systemContext = context;
    state.inputItems = request[@"inputItems"] ?: @[];
    NSString *contextName = NSBundle.mainBundle.infoDictionary[@"NSExtension"][@"NSExtensionContextClass"];
    Class contextClass = contextName.length ? NSClassFromString(contextName) : NSExtensionContext.class;
    NSExtensionContext *guestContext = LCCreateGuestContext(contextClass, state);
    if (!guestContext) {
        [context cancelRequestWithError:LCGuestExtensionError(@"The extension's vendor context class is unavailable")];
        CFRunLoopRun();
        return 1;
    }
    LCConnectGuestContext(state, contextClass, request);
    [handler beginRequestWithExtensionContext:guestContext];
    CFRunLoopRun();
    return 0;
}
