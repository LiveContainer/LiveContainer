//
//  LCStatusBarManager.h
//  LiveContainer
//
//  Created by Duy Tran on 20/2/26.
//
@import UIKit;
#import "AppSceneViewController.h"

@interface UIStatusBarManager(Private)
- (void)handleTapAction:(UIAction *)action;
@end

API_AVAILABLE(ios(16.0))
@interface LCStatusBarManager : UIStatusBarManager
@property(nonatomic) AppSceneViewController *nativeWindowViewController;
@end
