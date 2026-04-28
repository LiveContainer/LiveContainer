//
//  UIKitPrivate+MultitaskSupport.h
//  LiveContainer
//
//  Created by Duy Tran on 6/5/25.
//

#import <UIKit/UIKit.h>
#import "UIKitPrivate.h"

#define PrivClass(NAME) NSClassFromString(@#NAME)

@interface LSResourceProxy : NSObject
	@property (setter=_setLocalizedName:,nonatomic,copy) NSString *localizedName;
@end

@interface LSBundleProxy : LSResourceProxy
@end

@interface LSApplicationProxy : LSBundleProxy
	@property(nonatomic, assign, readonly) NSString *bundleIdentifier;
	@property(nonatomic, assign, readonly) NSString *localizedShortName;
	@property(nonatomic, assign, readonly) NSString *primaryIconName;

	@property (nonatomic,readonly) NSString * applicationIdentifier;
	@property (nonatomic,readonly) NSString * applicationType;
	@property (nonatomic,readonly) NSArray * appTags;
	@property (getter=isLaunchProhibited,nonatomic,readonly) BOOL launchProhibited;
	@property (getter=isPlaceholder,nonatomic,readonly) BOOL placeholder;
	@property (getter=isRemovedSystemApp,nonatomic,readonly) BOOL removedSystemApp;
@end

@interface BSCornerRadiusConfiguration : NSObject
- (id)initWithTopLeft:(CGFloat)tl bottomLeft:(CGFloat)bl bottomRight:(CGFloat)br topRight:(CGFloat)tr;
@end

// BoardServices
@interface BSSettings : NSObject
@end

@interface BSTransaction : NSObject
- (void)addChildTransaction:(id)transaction;
- (void)begin;
- (void)setCompletionBlock:(dispatch_block_t)block;
@end

// FrontBoard

@class RBSProcessIdentity, FBProcessExecutableSlice, UIMutableApplicationSceneClientSettings, UIMutableScenePresentationContext, UIScenePresentationManager, _UIScenePresenter, _UIScenePresenterOwner;

@interface FBApplicationProcessLaunchTransaction : BSTransaction
- (instancetype) initWithProcessIdentity:(RBSProcessIdentity *)identity executionContextProvider:(id)providerBlock;
- (void)_begin;
@end

@interface FBProcessExecutionContext : NSObject
@end

@interface FBMutableProcessExecutionContext : FBProcessExecutionContext

@property (nonatomic,copy) RBSProcessIdentity * identity; 
@property (nonatomic,copy) NSArray * arguments; 
@property (nonatomic,copy) NSDictionary * environment; 
@property (nonatomic,retain) NSURL * standardOutputURL; 
@property (nonatomic,retain) NSURL * standardErrorURL; 
@property (assign,nonatomic) BOOL waitForDebugger; 
@property (assign,nonatomic) BOOL disableASLR; 
@property (assign,nonatomic) BOOL checkForLeaks; 
@property (assign,nonatomic) long long launchIntent; 
//@property (nonatomic,retain) id<FBProcessWatchdogProviding> watchdogProvider; 
@property (nonatomic,copy) NSString * overrideExecutablePath; 
//@property (nonatomic,retain) FBProcessExecutableSlice * overrideExecutableSlice; 
@property (nonatomic,copy) id completion; 
-(id)copyWithZone:(NSZone*)arg1 ;
@end

@interface FBSSceneIdentityToken : NSObject
- (NSString *)stringRepresentation;
@end

@interface FBSScene : NSObject
- (FBSSceneIdentityToken *)identityToken;
@end

@interface FBProcess : NSObject
- (id)name;
@end

@interface FBScene : NSObject
- (NSString *)identifier;
- (FBSSceneIdentityToken *)identityToken;
- (FBProcess *)clientProcess;
- (UIScenePresentationManager *)uiPresentationManager;
- (void)updateSettings:(UIMutableApplicationSceneSettings *)settings withTransitionContext:(id)context completion:(id)completion;
- (void)updateSettingsWithBlock:(void(^)(UIMutableApplicationSceneSettings *settings))arg1;
- (void)updateSettingsWithTransitionBlock:(UIApplicationSceneTransitionContext *(^)(/* FBSMutableSceneSettings * */ id settings))transitionBlock;
@end

@interface FBDisplayManager : NSObject
+ (instancetype)sharedInstance;
- (id)mainConfiguration;
@end

@interface FBSSceneClientIdentity : NSObject
+ (instancetype)identityForBundleID:(NSString *)bundleID;
+ (instancetype)identityForProcessIdentity:(RBSProcessIdentity *)identity;
+ (instancetype)localIdentity;
@end

@interface FBProcessManager : NSObject
+ (instancetype)sharedInstance;
- (FBProcessExecutionContext *)launchProcessWithContext:(FBMutableProcessExecutionContext *)context;
- (void)registerProcessForAuditToken:(audit_token_t)token;
@end

@interface FBSSceneSpecification : NSObject
+ (instancetype)specification;
@end

// RunningBoardServices
@interface RBSProcessIdentity : NSObject
+ (instancetype)identityForEmbeddedApplicationIdentifier:(NSString *)identifier;
+ (instancetype)identityForXPCServiceIdentifier:(NSString *)identifier;
@end

@interface RBSProcessPredicate
+ (instancetype)predicateMatchingIdentifier:(NSNumber *)pid;
@end

@interface RBSProcessHandle
@property(nonatomic, copy, readonly) RBSProcessIdentity *identity;
+ (instancetype)handleForPredicate:(RBSProcessPredicate *)predicate error:(NSError **)error;
- (audit_token_t)auditToken;
@end

@interface RBSTarget : NSObject
+ (instancetype)targetWithPid:(pid_t)pid environmentIdentifier:(NSString *)identifier;
@end

@interface UIApplicationSceneSpecification : FBSSceneSpecification
@end

@interface FBSSceneIdentity : NSObject
+ (instancetype)identityForIdentifier:(NSString *)id;
@end

// FBSSceneSettings
@interface UIApplicationSceneSettings(Multitask)
- (bool)isForeground;
- (CGRect)frame;
- (UIInterfaceOrientation)interfaceOrientation;
- (UIMutableApplicationSceneSettings *)mutableCopy;
@end

@interface FBScene (a)
- (UIApplicationSceneSettings*)settings;
@end

@interface UIMutableApplicationSceneSettings(Multitask)
@property(nonatomic, assign, readwrite) BOOL canShowAlerts;
@property(nonatomic, assign) BOOL deviceOrientationEventsEnabled;
@property(nonatomic, assign, readwrite) NSInteger interruptionPolicy;
@property(nonatomic, strong, readwrite) NSString *persistenceIdentifier;
@property (nonatomic, assign, readwrite) UIEdgeInsets peripheryInsets;
@property (nonatomic, assign, readwrite) UIEdgeInsets safeAreaInsetsPortrait, safeAreaInsetsPortraitUpsideDown, safeAreaInsetsLandscapeLeft, safeAreaInsetsLandscapeRight;
@property(assign, nonatomic, readwrite) UIUserInterfaceStyle userInterfaceStyle;
@property(assign, nonatomic, readwrite) UIDeviceOrientation deviceOrientation;
@property (nonatomic, strong, readwrite) BSCornerRadiusConfiguration *cornerRadiusConfiguration;
@property (assign,nonatomic) CGRect statusBarAvoidanceFrame;
@property (assign,nonatomic) double statusBarHeight;
@property (assign,nonatomic, getter=isForeground) bool foreground;
- (id)displayConfiguration;
- (CGRect)frame;
- (NSMutableSet *)ignoreOcclusionReasons;
- (void)setDisplayConfiguration:(id)c;
- (void)setForeground:(BOOL)f;
- (void)setFrame:(CGRect)frame;
- (void)setLevel:(NSInteger)level;
- (void)setStatusBarDisabled:(BOOL)disabled;
- (void)setInterfaceOrientation:(NSInteger)o;
- (BSSettings *)otherSettings;
@end

@interface FBSSceneParameters(Multitask)
+ (instancetype)parametersForSpecification:(FBSSceneSpecification *)spec;
//- (void)updateSettingsWithBlock:(id)block;
@end

@interface FBSMutableSceneDefinition : NSObject
@property(nonatomic, copy) FBSSceneClientIdentity *clientIdentity;
@property(nonatomic, copy) FBSSceneIdentity *identity;
@property(nonatomic, copy) FBSSceneSpecification *specification;
+ (instancetype)definition;
@end

@interface FBSceneManager : NSObject
+ (instancetype)sharedInstance;
- (FBScene *)createSceneWithDefinition:(id)def initialParameters:(id)params;
-(void)destroyScene:(id)arg1 withTransitionContext:(id)arg2 ;
- (FBScene *)sceneFromIdentityTokenStringRepresentation:(NSString *)token;
@end

@interface FBSSceneSettingsDiff : NSObject
- (UIMutableApplicationSceneSettings *)settingsByApplyingToMutableCopyOfSettings:(UIApplicationSceneSettings *)settings ;
@end

// UIKit
@protocol _UISceneSettingsDiffAction<NSObject>
@required
- (void)_performActionsForUIScene:(UIScene *)scene withUpdatedFBSScene:(id)fbsScene settingsDiff:(FBSSceneSettingsDiff *)diff fromSettings:(id)settings transitionContext:(id)context lifecycleActionType:(uint32_t)actionType;
@end

@interface UIImage(internal)
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(NSInteger)format scale:(CGFloat)scale;
@end

@interface UIWindow (Private)
- (instancetype)_initWithFrame:(CGRect)frame attached:(BOOL)attached;
- (void)orderFront:(id)arg1;
@end

@interface _UIRootWindow : UIWindow
@end

@interface UIScreen (Private)
- (CGRect)_referenceBounds;
- (id)displayConfiguration;
@end

@interface UIScenePresentationBinder : NSObject
- (void)addScene:(id)scene;
@end

@interface UIScenePresentationManager : NSObject {
    id _keyboardProxyLayerManager;
    id _scene;
    _UIScenePresenterOwner *_scenePresenterOwner;
};
- (instancetype)_initWithScene:(FBScene *)scene;
- (_UIScenePresenter *)createPresenterWithIdentifier:(NSString *)identifier;
- (_UIScenePresenter *)_presenterWithIdentifier:(NSString *)identifier;
@end

@interface _UIScenePresenterOwner : NSObject
- (instancetype)initWithScenePresentationManager:(UIScenePresentationManager *)manager context:(FBScene *)scene;
- (_UIScenePresenter *)activePrioritizedPresenter;
@end

@interface _UIScenePresentationView : UIView
//- (instancetype)initWithPresenter:(_UIScenePresenter *)presenter;
@end

@interface _UIScenePresenter : NSObject
@property (nonatomic, assign, readonly) _UIScenePresentationView *presentationView;
@property(nonatomic, assign, readonly) FBScene *scene;
- (instancetype)initWithOwner:(_UIScenePresenterOwner *)manager identifier:(NSString *)scene sortContext:(NSNumber *)context;
- (void)modifyPresentationContext:(void(^)(UIMutableScenePresentationContext *context))block;
- (void)activate;
- (void)deactivate;
- (void)invalidate;
@end

@interface UIRootWindowScenePresentationBinder : UIScenePresentationBinder
- (instancetype)initWithPriority:(int)pro displayConfiguration:(id)c;
@end

@interface UIScenePresentationContext : NSObject
- (UIScenePresentationContext *)_initWithDefaultValues;
@end

@interface _UISceneLayerHostContainerView : UIView
- (instancetype)initWithScene:(FBScene *)scene debugDescription:(NSString *)desc;
- (void)_setPresentationContext:(UIScenePresentationContext *)context;
@end

@interface UIScene(Private)
- (void)_registerSettingsDiffActionArray:(NSArray<id<_UISceneSettingsDiffAction>> *)array forKey:(NSString *)key;
- (void)_unregisterSettingsDiffActionArrayForKey:(NSString *)key;
@end

@interface UIApplication()
- (void)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end

@interface UIMutableScenePresentationContext : UIScenePresentationContext
@property(nonatomic, assign) NSUInteger appearanceStyle;
@end
@interface UIMutableScenePresentationContext(LiveContainerHooks)
- (void)_setVisibilityPropagationEnabled:(BOOL)enabled;
@end

@interface UIViewController(Private)
- (void)viewDidMoveToWindow:(UIWindow *)window shouldAppearOrDisappear:(BOOL)appear;
@end

@protocol BSServiceConnectionEndpointInjectorConfiguring
@required
- (void)setAdditionalAttributes:(NSArray *)arg1;
- (void)setDomain:(NSString *)arg1;
- (void)setInheritingEnvironment:(NSString *)arg1;
- (void)setInstance:(NSString *)arg1;
- (void)setService:(NSString *)arg1;
- (void)setTarget:(id)arg1;
@end

@interface BSServiceConnectionEndpointInjector : NSObject
+ (instancetype)injectorWithConfigurator:(void (^)(id<BSServiceConnectionEndpointInjectorConfiguring>))configurator;
- (void)invalidate;
@end

@interface RBSEndowmentGrant : NSObject
+ (instancetype)grantWithNamespace:(NSString *)ns endowment:(id)endowment;
@end
@interface RBSHereditaryGrant : NSObject
+ (instancetype)grantWithNamespace:(NSString *)ns sourceEnvironment:(NSString *)source attributes:(id)attrs;
@end

@interface UIKBArbiterClientFocusContext : NSObject
- (FBSSceneIdentityToken *)sceneIdentity;
@end

@protocol UIKeyboardArbitration <NSObject>
- (void)focusApplicationWithProcessIdentifier:(int)pid context:(UIKBArbiterClientFocusContext *)context stealingKeyboard:(BOOL)steal onCompletion:(void (^)(BOOL success))completion;
@end

@interface _UIRemoteKeyboards : NSObject
+ (instancetype)sharedRemoteKeyboards;
- (id<UIKeyboardArbitration>)proxy;
- (void)startConnection;
@end

@interface UIScene(Private2)
- (FBSScene *)_FBSScene;
@end

@interface _UIVisibilityPropagationInteraction : NSObject
+ (instancetype)interactionWithPID:(pid_t)pid environmentIdentifier:(id)identifier;
- (void)_setVisibilityPropagationEnabled:(uint64_t)enabled;
@end

@interface _UIKeyboardChangedInformation : NSObject
- (NSString *)sourceSceneIdentityString;
@end

@interface _UISceneRelationshipManagementHostComponent : NSObject {
    @public _UIScenePresenter *_prioritizedPresenter;
};
@end
