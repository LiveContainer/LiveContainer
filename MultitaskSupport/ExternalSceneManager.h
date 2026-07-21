//
//  ExternalSceneManager.h
//  LiveContainer
//
//  Created by Duy Tran on 26/6/26.
//
@import UIKit;

API_AVAILABLE(ios(16.0))
@interface ExternalSceneManager : NSObject
+ (BOOL)available;
+ (BOOL)isHostingApp:(DecoratedAppSceneViewController *)vc;
+ (UIWindow *)keyWindow;
@end

API_AVAILABLE(ios(16.0))
@interface ExternalSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
