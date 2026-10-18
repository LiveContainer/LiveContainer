// Controlled in-process method hook; no jailbreak services or third-party hooking runtime.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static void replacement(id object, SEL selector, id sender) {
    UILabel *result = [object valueForKey:@"result"];
    result.text = @"TWEAK HOOK ACTIVE";
}

__attribute__((constructor)) static void installProbe(void) {
    // Guest classes have been loaded before the user can press the probe button.
    dispatch_async(dispatch_get_main_queue(), ^{
        Class controller = NSClassFromString(@"LCOSProbeController");
        Method method = class_getInstanceMethod(controller, NSSelectorFromString(@"probeTapped:"));
        if (method) method_setImplementation(method, (IMP)replacement);
    });
}
