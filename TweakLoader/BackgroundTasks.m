#import "../LiveContainer/utils.h"
#import <dlfcn.h>

static NSString *guestTaskPrefix;
static NSString *hostTaskPrefix;
static NSSet<NSString *> *guestTaskIdentifiers;
static NSArray<NSString *> *guestTaskFamilies;
static NSString *const continuedProcessingReason = @"com.apple.das.bgongoingprocessing";
static NSString *const continuedProcessingNamePrefix = @"bgContinuedProcessing-";

static BOOL isGuestTaskIdentifier(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0 || identifier.length > 128 ||
        ![identifier hasPrefix:guestTaskPrefix]) return NO;
    if ([guestTaskIdentifiers containsObject:identifier]) return YES;
    for (NSString *family in guestTaskFamilies) {
        if ([identifier hasPrefix:family] && identifier.length > family.length && ![identifier containsString:@"*"]) return YES;
    }
    return NO;
}

static NSString *hostTaskIdentifier(NSString *identifier) {
    if (!isGuestTaskIdentifier(identifier)) return identifier;
    return [hostTaskPrefix stringByAppendingString:[identifier substringFromIndex:guestTaskPrefix.length]];
}

static NSString *guestTaskIdentifier(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class] || ![identifier hasPrefix:hostTaskPrefix]) return identifier;
    NSString *guestIdentifier = [guestTaskPrefix stringByAppendingString:[identifier substringFromIndex:hostTaskPrefix.length]];
    return isGuestTaskIdentifier(guestIdentifier) ? guestIdentifier : identifier;
}

// NSProxy forwards every coder operation, including private XPC operations. Subclassing
// NSCoder would instead inherit implementations that do not reach the real XPC coder.
@interface LCBackgroundTaskCoder : NSProxy
@property (nonatomic, strong) NSCoder *coder;
@property (nonatomic, copy) NSString *sourceIdentifier;
@property (nonatomic, copy) NSString *destinationIdentifier;
@end

@implementation LCBackgroundTaskCoder
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [self.coder methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation invokeWithTarget:self.coder];
}

- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.coder respondsToSelector:selector];
}

- (id)translatedObject:(id)object forKey:(NSString *)key {
    if ([key isEqualToString:@"name"] && [object isKindOfClass:NSString.class]) {
        NSString *sourceName = [continuedProcessingNamePrefix stringByAppendingString:self.sourceIdentifier];
        if ([object isEqualToString:sourceName]) {
            return [continuedProcessingNamePrefix stringByAppendingString:self.destinationIdentifier];
        }
    } else if ([key isEqualToString:@"userInfo"] && [object isKindOfClass:NSDictionary.class] &&
               [object[@"clientID"] isEqual:self.sourceIdentifier]) {
        NSMutableDictionary *userInfo = [object mutableCopy];
        userInfo[@"clientID"] = self.destinationIdentifier;
        return userInfo;
    }
    return object;
}

- (void)encodeObject:(id)object forKey:(NSString *)key {
    [self.coder encodeObject:[self translatedObject:object forKey:key] forKey:key];
}

- (id)decodeObjectOfClass:(Class)class forKey:(NSString *)key {
    return [self translatedObject:[self.coder decodeObjectOfClass:class forKey:key] forKey:key];
}

- (id)decodeObjectOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key {
    return [self translatedObject:[self.coder decodeObjectOfClasses:classes forKey:key] forKey:key];
}
@end

@interface NSObject (LCBackgroundTasksPrivate)
- (NSString *)launchReason;
- (NSString *)clientProvidedIdentifier;
- (NSString *)name;
@end

static void (*originalEncodeActivity)(id, SEL, NSCoder *);
// init methods consume self and return an owned object, unlike ordinary C calls.
typedef id (*LCDecodeActivityIMP)(id __attribute__((ns_consumed)), SEL, NSCoder *) __attribute__((ns_returns_retained));
static LCDecodeActivityIMP originalDecodeActivity;
static void (*originalCancelTask)(id, SEL, NSString *);
static BOOL (*originalIsPermissibleIdentifier)(id, SEL, NSString *);

static BOOL isXPCCoder(NSCoder *coder, NSString *className) {
    Class class = NSClassFromString(className);
    return class && [coder isKindOfClass:class];
}

static LCBackgroundTaskCoder *taskCoder(NSCoder *coder, NSString *source, NSString *destination) {
    LCBackgroundTaskCoder *adapter = [LCBackgroundTaskCoder alloc];
    adapter.coder = coder;
    adapter.sourceIdentifier = source;
    adapter.destinationIdentifier = destination;
    return adapter;
}

static void hook_encodeActivity(id self, SEL selector, NSCoder *coder) {
    if (isXPCCoder(coder, @"NSXPCEncoder") && [[self launchReason] isEqualToString:continuedProcessingReason]) {
        NSString *source = [self clientProvidedIdentifier];
        NSString *destination = hostTaskIdentifier(source);
        if (destination != source && [[self name] isEqualToString:[continuedProcessingNamePrefix stringByAppendingString:source]]) {
            // Only the wire representation changes; never mutate an activity already in a set.
            originalEncodeActivity(self, selector, (id)taskCoder(coder, source, destination));
            return;
        }
    }
    originalEncodeActivity(self, selector, coder);
}

static id hook_decodeActivity(id self __attribute__((ns_consumed)), SEL selector, NSCoder *coder) __attribute__((ns_returns_retained));
static id hook_decodeActivity(id self __attribute__((ns_consumed)), SEL selector, NSCoder *coder) {
    if (isXPCCoder(coder, @"NSXPCDecoder")) {
        NSString *reason = [coder decodeObjectOfClass:NSString.class forKey:@"launchReason"];
        NSString *name = [coder decodeObjectOfClass:NSString.class forKey:@"name"];
        if ([reason isEqualToString:continuedProcessingReason] && [name hasPrefix:continuedProcessingNamePrefix]) {
            NSString *source = [name substringFromIndex:continuedProcessingNamePrefix.length];
            NSString *destination = guestTaskIdentifier(source);
            if (![destination isEqualToString:source]) {
                // Translate before initWithCoder: builds any cached identifier or hash.
                return originalDecodeActivity(self, selector, (id)taskCoder(coder, source, destination));
            }
        }
    }
    return originalDecodeActivity(self, selector, coder);
}

static void hook_cancelTask(id self, SEL selector, NSString *identifier) {
    // Cancellation carries no task type. Cancel both aliases so ordinary tasks
    // still work, including when cancelling before querying pending requests.
    originalCancelTask(self, selector, identifier);
    NSString *destination = hostTaskIdentifier(identifier);
    if (destination != identifier) originalCancelTask(self, selector, destination);
}

static BOOL hook_isPermissibleIdentifier(id self, SEL selector, NSString *identifier) {
    // Implement the declared rules explicitly, rather than changing the wildcard
    // validator (whose result is inverted for wildcard registration on iOS 26).
    if (isGuestTaskIdentifier(identifier)) return YES;
    return originalIsPermissibleIdentifier(self, selector, identifier);
}

__attribute__((constructor))
static void BackgroundTasksGuestHooksInit(void) {
    if (!NSUserDefaults.lcGuestAppId || ![NSUserDefaults.guestAppInfo[@"fixBackgroundTaskIdentifiers"] boolValue]) return;
    if (@available(iOS 26.0, *)) {
        NSString *guestBundleIdentifier = NSUserDefaults.lcGuestAppId;
        NSBundle *hostBundle = NSUserDefaults.lcMainBundle;
        if (NSUserDefaults.isLiveProcess) {
            // dasd uses the root application's identity, not LiveProcess.appex's ID.
            hostBundle = [NSBundle bundleWithPath:hostBundle.bundlePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent];
        }
        NSString *hostBundleIdentifier = hostBundle.bundleIdentifier;
        if (!guestBundleIdentifier.length || !hostBundleIdentifier.length ||
            [guestBundleIdentifier isEqualToString:hostBundleIdentifier]) return;
        guestTaskPrefix = [guestBundleIdentifier stringByAppendingString:@"."];
        hostTaskPrefix = [hostBundleIdentifier stringByAppendingString:@"."];

        NSMutableSet *identifiers = [NSMutableSet set];
        NSMutableArray *families = [NSMutableArray array];
        id declarations = NSBundle.mainBundle.infoDictionary[@"BGTaskSchedulerPermittedIdentifiers"];
        if (![declarations isKindOfClass:NSArray.class]) return;
        for (NSString *identifier in declarations) {
            if (![identifier isKindOfClass:NSString.class] || ![identifier hasPrefix:guestTaskPrefix] ||
                identifier.length == 0 || identifier.length > 128) continue;
            if ([identifier hasSuffix:@".*"] && [identifier componentsSeparatedByString:@"*"].count == 2) {
                [families addObject:[identifier substringToIndex:identifier.length - 1]];
            } else if (![identifier containsString:@"*"]) {
                [identifiers addObject:identifier];
            }
        }
        guestTaskIdentifiers = [identifiers copy];
        guestTaskFamilies = [families copy];
        if (!identifiers.count && !families.count) return;

        dlopen("/System/Library/Frameworks/BackgroundTasks.framework/BackgroundTasks", RTLD_LAZY);
        Class activityClass = NSClassFromString(@"_DASActivity");
        Class schedulerClass = NSClassFromString(@"_DASScheduler");
        Class registryClass = NSClassFromString(@"_BGTaskIdentifierRegistry");
        Method encode = class_getInstanceMethod(activityClass, @selector(encodeWithCoder:));
        Method decode = class_getInstanceMethod(activityClass, @selector(initWithCoder:));
        Method cancel = class_getInstanceMethod(schedulerClass, NSSelectorFromString(@"cancelTaskRequestWithIdentifier:"));
        Method permissible = class_getInstanceMethod(registryClass, NSSelectorFromString(@"isPermissibleFullyComposedIdentifier:"));
        // Install only when the complete round trip is available on this OS.
        if (!encode || !decode || !cancel || !permissible) return;
        originalEncodeActivity = (void *)method_setImplementation(encode, (IMP)hook_encodeActivity);
        originalDecodeActivity = (void *)method_setImplementation(decode, (IMP)hook_decodeActivity);
        originalCancelTask = (void *)method_setImplementation(cancel, (IMP)hook_cancelTask);
        originalIsPermissibleIdentifier = (void *)method_setImplementation(permissible, (IMP)hook_isPermissibleIdentifier);
    }
}
