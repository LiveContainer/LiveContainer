#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import "../FoundationPrivate.h"
#import "PlugInKitPrivate.h"
#import "LivePlugInServer.h"
#import "../utils.h"
#import "../LCSharedUtils.h"
#import "Tweaks.h"

static NSURL *guestExtensionsAppURL;
static NSURL *guestExtensionsContainerURL;

static NSError *LCGuestExtensionError(NSString *message) {
    return [NSError errorWithDomain:@"LCGuestExtension" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSDictionary* prepareGuestPlugInConfig(NSBundle* guestBundle, NSError** errorOut) {
    NSError *error = nil;
    // Bundle identifiers are metadata from an imported app. Encode them as one
    // path component so a malformed identifier cannot escape the subcontainer.
    NSString *component = [guestBundle.bundleIdentifier stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
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


    NSDictionary *envelope = @{
            @"bundlePath": guestBundle.bundlePath,
            @"appBundlePath": guestExtensionsAppURL.path,
            @"containerPath": containerURL.path,
            @"bookmarks": bookmarks,
            @"guestAppInfo": NSUserDefaults.guestAppInfo ?: @{},
            @"guestContainerInfo": NSUserDefaults.guestContainerInfo ?: @{},
            @"appGroupPath": NSUserDefaults.lcAppGroupPath ?: @"",
            @"parentContainerPath": guestExtensionsContainerURL.path,
            @"lcHomePath": @(getenv("LC_HOME_PATH")),
    };

    return envelope;
}

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

@interface PKHostPluginProxy : NSProxy
@property (nonatomic, weak, readonly) PKHostPlugIn* target;
@property NSBundle* guestBundle;
- (instancetype)initWithTarget:(id)target guestBundle:(NSBundle*)guestBundle;
@end
void* guestBundleKey = &guestBundleKey;

void (*orig_discoverPlugInsForAttributes)(id self, SEL _cmd, NSDictionary* attributes, uint64_t flags, void (^found)(NSSet*, NSError *));
void hook_discoverPlugInsForAttributes(id self, SEL _cmd, NSDictionary* attributes, uint64_t flags, void (^found)(NSSet*, NSError *)) {
    NSString* identifier = attributes[@"NSExtensionIdentifier"];
    NSBundle *bundle = LCFindGuestExtension(identifier);
    
    if(!bundle) {
        orig_discoverPlugInsForAttributes(self, _cmd, attributes, flags, found);
        return;
    }
    
    NSString *liveProcessBundleId;
    if(NSUserDefaults.isLiveProcess) {
        liveProcessBundleId = [NSBundle bundleWithURL:[NSUserDefaults.lcMainBundle.bundleURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"LiveProcess.appex"]].bundleIdentifier;
    } else {
        liveProcessBundleId = [NSBundle bundleWithURL:[NSUserDefaults.lcMainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"LiveProcess.appex"]].bundleIdentifier;
    }
    if (!liveProcessBundleId) {
        // can't find liveprocess, we might be in LC2, or liveprocess is not installed, attempt to guess LC1's LiveProcess extension
        liveProcessBundleId = [[@"com.kdt.livecontainer" stringByAppendingPathExtension:LCSharedUtils.teamIdentifier]
                              stringByAppendingPathExtension:@"LiveProcess"];
    }
    NSDictionary* newAttributes = @{@"NSExtensionIdentifier":liveProcessBundleId};
    orig_discoverPlugInsForAttributes(self, _cmd, newAttributes, flags, ^(NSSet* result, NSError* err) {
        if([result count] == 1) {
            NSMutableSet* result2 = [result mutableCopy];
            id old = [result2 anyObject];
            [result2 removeObject:old];
            [result2 addObject:[[PKHostPluginProxy alloc] initWithTarget:old guestBundle:bundle]];
            found(result2, err);
        } else {
            found(result, err);
        }
    });
}

void (*orig_readyPlugIns)(id self, SEL _cmd, NSArray<PKHostPlugIn*>* plugins, bool synchronously, id environment, id languages, id persona, id sandbox, void (^ready)(NSError *error,NSArray<NSNumber *> *pids,NSArray<NSUUID *> *uuids) );
void hook_readyPlugIns(id self, SEL _cmd, NSArray<PKHostPlugIn*>* plugins, bool synchronously, id environment, id languages, id persona, id sandbox, void (^ready)(NSError *error,NSArray<NSNumber *> *pids,NSArray<NSUUID *> *uuids) ){
    PKHostPlugIn* plugin = plugins.firstObject;
    NSBundle* guestBundle = plugin ? objc_getAssociatedObject(plugin, guestBundleKey) : nil;
    if([plugins count] != 1 || !plugin || !guestBundle) {
        orig_readyPlugIns(self, _cmd, plugins, synchronously, environment, languages, persona, sandbox, ready);
        return;
    }

    [LCLivePlugIn startServer];
    LCLivePlugIn* lp = [[LCLivePlugIn alloc] initWithUUID:[plugin uuid] configuration:prepareGuestPlugInConfig(guestBundle, nil)];
    
    orig_readyPlugIns(self, _cmd, plugins, synchronously, environment, languages, persona, sandbox, ^(NSError *error, NSArray<NSNumber *> *pids,NSArray<NSUUID *> *uuids) {
        do {
            if(error) break;
            NSNumber* pid = pids.firstObject;
            if(!pid) break;
            
            lp.pid = [pid unsignedIntValue];
            [LCLivePlugIn resolvePendingRequests];
        } while(0);
        ready(error, pids, uuids);
    });
}

@implementation PKHostPluginProxy : NSProxy

- (instancetype)initWithTarget:(PKHostPlugIn*)target guestBundle:(NSBundle*)guestBundle {
    _target = target;
    _guestBundle = guestBundle;
    return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    return [self.target methodSignatureForSelector:sel];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation invokeWithTarget:self.target];
    if(strcmp(sel_getName(invocation.selector), "createInstanceWithUUID:") == 0) {
        __unsafe_unretained id tempReturnValue = nil;
        [invocation getReturnValue:&tempReturnValue];
        PKHostPlugIn* newPlugIn = tempReturnValue;
        objc_setAssociatedObject(newPlugIn, guestBundleKey, _guestBundle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

@end

void NSExtensionGuestHooksInit(NSURL *appURL, NSURL *containerURL) {
//    if (NSUserDefaults.isLiveProcess) return;
    dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_LAZY | RTLD_GLOBAL);

    guestExtensionsAppURL = appURL;
    guestExtensionsContainerURL = containerURL;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincompatible-function-pointer-types"
    Class PKHostClass = NSClassFromString(@"PKHost");
    
    Method m1 = class_getInstanceMethod(PKHostClass, @selector(discoverPlugInsForAttributes:flags:found:));
    orig_discoverPlugInsForAttributes = method_getImplementation(m1);
    method_setImplementation(m1, hook_discoverPlugInsForAttributes);
    
    Method m2 = class_getInstanceMethod(PKHostClass, @selector(readyPlugIns:synchronously:environment:languages:persona:sandbox:ready:));
    orig_readyPlugIns = method_getImplementation(m2);
    method_setImplementation(m2, hook_readyPlugIns);

#pragma clang diagnostic pop
    
}

@implementation NSXPCListener(hook)

- (instancetype)hook_initWithMachServiceName:(NSString*)serviceName {
    NSString* newServiceName = serviceName;
    NSString* guestBundleId = NSBundle.mainBundle.bundleIdentifier;
    if([serviceName hasPrefix:guestBundleId]) {
        NSString *remaining = [serviceName substringFromIndex:guestBundleId.length];
        newServiceName = [NSUserDefaults.lcMainBundle.bundleIdentifier stringByAppendingString:remaining];
    }
    return [self hook_initWithMachServiceName:newServiceName];
}

@end

// when running as a guest extension
void GuestExtensionHooksInit(void) {
    swizzle(NSXPCListener.class, @selector(initWithMachServiceName:), @selector(hook_initWithMachServiceName:));
}
