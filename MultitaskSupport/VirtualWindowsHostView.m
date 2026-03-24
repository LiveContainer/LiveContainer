//
//  VirtualWindowsHostView.m
//  LiveContainer
//
//  Created by Duy Tran on 22/2/26.
//

#import "VirtualWindowsHostView.h"
#import "AppSceneViewController.h"


@interface UIView (PrivateDelegate)
- (id)_viewDelegate;
@end


#import "LiveContainerSwiftUI-Swift.h"

@implementation VirtualWindowsHostView

- (instancetype)init {
    
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
            window = ((UIWindowScene *)scene).keyWindow;
            break;
        }
    }
    
    CGRect frame = window ? window.bounds : [UIScreen mainScreen].bounds;
    self = [super initWithFrame:frame];
    if (self) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.shouldForwardTapAction = YES;
    }
    return self;
}

- (BOOL)handleStatusBarTapAction:(UIAction *)action {
    if(!self.shouldForwardTapAction) return NO;
    

    UIView *frontmostView = self.subviews.lastObject;
    if(frontmostView && !frontmostView.hidden) {
        
        
        if ([frontmostView respondsToSelector:@selector(_viewDelegate)]) {
            id decoratedVC = [frontmostView _viewDelegate];
            
            
            SEL appSceneSel = NSSelectorFromString(@"appSceneVC");
            if ([decoratedVC respondsToSelector:appSceneSel]) {
                
                id appSceneVC = [decoratedVC valueForKey:@"appSceneVC"];
                
                
                if ([appSceneVC respondsToSelector:@selector(handleStatusBarTapAction:)]) {
                    [appSceneVC performSelector:@selector(handleStatusBarTapAction:) withObject:action];
                    return YES;
                }
            }
        }
    }
    return !frontmostView.hidden;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView* hitView = [super hitTest:point withEvent:event];
    if(hitView == self) {
        self.shouldForwardTapAction = NO;
        return nil;
    } else {
        self.shouldForwardTapAction = YES;
        return hitView;
    }
}
@end
