//
//  AppSceneView.h
//  LiveContainer
//
//  Created by s s on 2025/5/17.
//
@class UIKitPrivate+MultitaskSupport
@class FoundationPrivate
@import UIKit;
@import Foundation;


@class AppSceneViewController;

API_AVAILABLE(ios(16.0))
@protocol AppSceneViewControllerDelegate <NSObject>
- (void)appSceneVCAppDidExit:(AppSceneViewController*)vc;
- (void)appSceneVC:(AppSceneViewController*)vc didInitializeWithError:(NSError*)error;
@optional
- (void)appSceneVC:(AppSceneViewController*)vc didUpdateFromSettings:(UIMutableApplicationSceneSettings *)settings transitionContext:(id)context;
@end

API_AVAILABLE(ios(16.0))
@interface AppSceneViewController : UIViewController<_UISceneSettingsDiffAction>
@property(nonatomic) void(^nextUpdateSettingsBlock)(UIMutableApplicationSceneSettings *settings);
@property(nonatomic) NSString* bundleId;
@property(nonatomic) NSString* dataUUID;
@property(nonatomic) int pid;
@property(nonatomic) id<AppSceneViewControllerDelegate> delegate;
@property(nonatomic) BOOL isAppRunning;
@property(nonatomic) CGFloat scaleRatio;
@property(nonatomic) UIView* contentView;
@property(nonatomic) _UIScenePresenter *presenter;
@property(nonatomic) UIMutableApplicationSceneSettings *settings;
- (instancetype)initWithBundleId:(NSString*)bundleId dataUUID:(NSString*)dataUUID delegate:(id<AppSceneViewControllerDelegate>)delegate;
- (void)setBackgroundNotificationEnabled:(bool)enabled;
- (void)updateFrameWithSettingsBlock:(void (^)(UIMutableApplicationSceneSettings *settings))block;
- (void)appTerminationCleanUp;
- (void)terminate;
- (void)openURLScheme:(NSString *)urlString;
- (void)handleStatusBarTapAction:(UIAction *)action;
@end

