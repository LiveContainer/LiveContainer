//
//  LCStatusBarManager.m
//  LiveContainer
//
//  Created by Duy Tran on 20/2/26.
//
#import "LCStatusBarManager.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "VirtualWindowsHostView.h"

@implementation LCStatusBarManager
- (void)handleTapAction:(UIAction *)action {
    if(self.nativeWindowViewController) {
        [self.nativeWindowViewController handleStatusBarTapAction:action];
        return;
    }
    BOOL handledByVirtualWindow = [MultitaskDockManager.shared.windowHostingView handleStatusBarTapAction:action];
    if(!handledByVirtualWindow) {
        [super handleTapAction:action];
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
