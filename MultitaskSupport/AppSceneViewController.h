//
//  AppSceneView.h
//  LiveContainer
//
//  Created by s s on 2025/5/17.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@class UIMutableApplicationSceneSettings;
@class _UIScenePresenter;
@class AppSceneViewController;
@protocol _UISceneSettingsDiffAction; 

API_AVAILABLE(ios(16.0))
@protocol AppSceneViewControllerDelegate <NSObject>
- (void)appSceneVCAppDidExit:(AppSceneViewController*)vc;
- (void)appSceneVC:(AppSceneViewController*)vc didInitializeWithError:(NSError*)error;
@optional
- (void)appSceneVC:(AppSceneViewController*)vc didUpdateFromSettings:(UIMutableApplicationSceneSettings *)settings transitionContext:(id)context;
@end

API_AVAILABLE(ios(16.0))
@interface AppSceneViewController : UIViewController <_UISceneSettingsDiffAction>

@property(nonatomic, copy) void(^nextUpdateSettingsBlock)(UIMutableApplicationSceneSettings *settings);
@property(nonatomic, copy) NSString* bundleId;
@property(nonatomic, copy) NSString* dataUUID;
@property(nonatomic, assign) int pid;
@property(nonatomic, weak) id<AppSceneViewControllerDelegate> delegate;
@property(nonatomic, assign, readonly) BOOL isAppRunning;
@property(nonatomic, assign) CGFloat scaleRatio;
@property(nonatomic, strong) UIView* contentView;
@property(nonatomic, strong) _UIScenePresenter *presenter;
@property(nonatomic, strong) UIMutableApplicationSceneSettings *settings;

- (instancetype)initWithBundleId:(NSString*)bundleId dataUUID:(NSString*)dataUUID delegate:(id<AppSceneViewControllerDelegate>)delegate;
- (void)setBackgroundNotificationEnabled:(bool)enabled;
- (void)updateFrameWithSettingsBlock:(void (^)(UIMutableApplicationSceneSettings *settings))block;
- (void)appTerminationCleanUp;
- (void)terminate;
- (void)openURLScheme:(NSString *)urlString;
- (void)handleStatusBarTapAction:(UIAction *)action;

@end


