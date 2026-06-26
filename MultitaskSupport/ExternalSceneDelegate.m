//
//  ExternalSceneDelegate.m
//  LiveContainer
//
//  Created by Duy Tran on 26/6/26.
//
#import "DecoratedAppSceneViewController.h"
#import "ExternalSceneDelegate.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "VirtualWindowsHostView.h"

@implementation ExternalSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view = [[VirtualWindowsHostView alloc] initWithFrame:windowScene.coordinateSpace.bounds];
    
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.backgroundColor = UIColor.systemBackgroundColor;
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    VirtualWindowsHostView *windowHostingView = (VirtualWindowsHostView *)self.window.rootViewController.view;
    for(DecoratedAppSceneViewController *vc in windowHostingView.subviews) {
        if(![vc isKindOfClass:DecoratedAppSceneViewController.class]) continue;
        [vc moveWindowToMainDisplay];
    }
}

+ (BOOL)available {
    return self.keyWindow != nil;
}

+ (UIWindow *)keyWindow {
    static UIWindow *window = nil;
    if (!window || !window.isKeyWindow) {
        window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene.delegate isKindOfClass:[ExternalSceneDelegate class]]) {
                window = ((ExternalSceneDelegate *)scene.delegate).window;
                break;
            }
        }
    }
    return window;
}

@end
