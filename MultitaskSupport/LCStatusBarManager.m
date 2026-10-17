//
//  LCStatusBarManager.m
//  LiveContainer
//
//  Extended: double-tap status bar to close current guest app / return to LC
//

#import "LCStatusBarManager.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "VirtualWindowsHostView.h"
#import "DecoratedAppSceneViewController.h"
#import <UIKit/UIKit.h>

// Double-tap detection
static NSTimeInterval LCLastStatusBarTapTime = 0;
static const NSTimeInterval LCDoubleTapInterval = 0.35;

@implementation LCStatusBarManager

- (void)handleTapAction:(UIAction *)action {
    // Check user preference (default ON)
    BOOL enabled = YES;
    NSString *appGroupId = nil;
    Class sharedUtilsClass = NSClassFromString(@"LCSharedUtils");
    if ([sharedUtilsClass respondsToSelector:@selector(appGroupID)]) {
        appGroupId = [sharedUtilsClass appGroupID];
    }
    NSUserDefaults *defaults = appGroupId ? [[NSUserDefaults alloc] initWithSuiteName:appGroupId] : nil;
    if (defaults) {
        if ([defaults objectForKey:@"LCDoubleTapStatusBarToExit"] != nil) {
            enabled = [defaults boolForKey:@"LCDoubleTapStatusBarToExit"];
        }
    } else if ([NSUserDefaults.standardUserDefaults objectForKey:@"LCDoubleTapStatusBarToExit"] != nil) {
        enabled = [NSUserDefaults.standardUserDefaults boolForKey:@"LCDoubleTapStatusBarToExit"];
    }
    
    if (enabled) {
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        if (LCLastStatusBarTapTime > 0 && (now - LCLastStatusBarTapTime) <= LCDoubleTapInterval) {
            // Double-tap detected
            LCLastStatusBarTapTime = 0;
            [self lc_handleDoubleTapExit];
            return; // consume the event
        }
        LCLastStatusBarTapTime = now;
    }
    
    // Single tap — original behavior
    if (self.nativeWindowViewController) {
        [self.nativeWindowViewController handleStatusBarTapAction:action];
        return;
    }
    BOOL handledByVirtualWindow = [MultitaskDockManager.shared.windowHostingView handleStatusBarTapAction:action];
    if (!handledByVirtualWindow) {
        [super handleTapAction:action];
    }
}

- (void)lc_handleDoubleTapExit {
    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
    }
    
    // Prefer closing frontmost multitask window
    if (self.nativeWindowViewController) {
        if ([self.nativeWindowViewController respondsToSelector:@selector(terminate)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self.nativeWindowViewController performSelector:@selector(terminate)];
#pragma clang diagnostic pop
        }
        return;
    }
    
    // Virtual window mode — find frontmost DecoratedAppSceneViewController and close it
    VirtualWindowsHostView *host = MultitaskDockManager.shared.windowHostingView;
    if (host) {
        UIView *frontmostView = host.subviews.lastObject;
        if (frontmostView && !frontmostView.hidden) {
            id decorated = frontmostView._viewDelegate;
            if ([decorated respondsToSelector:@selector(closeWindow)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [decorated performSelector:@selector(closeWindow)];
#pragma clang diagnostic pop
                return;
            }
        }
    }
    
    // Fallback
    Class sharedUtils = NSClassFromString(@"LCSharedUtils");
    if ([sharedUtils respondsToSelector:@selector(launchToGuestAppWithClassicMode:)]) {
        [sharedUtils launchToGuestAppWithClassicMode:0];
    }
}

@end

@implementation UIApplication(LiveContainer)
+ (Class)_statusBarManagerClass {
    if (@available(iOS 16.0, *)) {
        return LCStatusBarManager.class;
    } else {
        return UIStatusBarManager.class;
    }
}
@end
