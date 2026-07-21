#import <UIKit/UIKit.h>

@interface UIImage(private)
- (UIImage *)_imageWithSize:(CGSize)size;
@end

@interface UIAlertAction(private)
@property(nonatomic, copy) id shouldDismissHandler;
@end

@interface UIActivityContinuationManager : UIResponder
- (NSDictionary*)handleActivityContinuation:(NSDictionary*)activityDict isSuspended:(id)isSuspended;
@end

@interface UIApplication(private)
- (void)suspend;
- (UIActivityContinuationManager*)_getActivityContinuationManager;
@end

@interface UIBarButtonItemGroup(private)
- (UIMenu *)_representativeItemMenu;
@end

@interface UIContextMenuInteraction(private)
- (void)_presentMenuAtLocation:(CGPoint)location;
@end

@interface _UIContextMenuStyle : NSObject <NSCopying>
@property(nonatomic) NSInteger preferredLayout;
+ (instancetype)defaultStyle;
@end

@interface UIOpenURLAction : NSObject
- (NSURL *)url;
- (instancetype)initWithURL:(NSURL *)arg1;
@end

@interface FBSSceneTransitionContext : NSObject
@property (nonatomic,copy) NSSet * actions;
@end

@interface UIApplicationSceneTransitionContext : FBSSceneTransitionContext
@property (nonatomic,retain) NSDictionary * payload;
@end

@interface UITableViewHeaderFooterView(private)
- (void)setText:(NSString *)text;
- (NSString *)text;
@end

@interface UIApplicationSceneSettings : NSObject
@end

@interface UIApplicationSceneClientSettings : NSObject
@end

@interface UIMutableApplicationSceneSettings : UIApplicationSceneSettings
@property (assign,nonatomic) UIDeviceOrientation deviceOrientation;
- (void)setInterfaceOrientation:(UIInterfaceOrientation)o;
@end



@interface UIMutableApplicationSceneClientSettings : UIApplicationSceneClientSettings
@property (assign,nonatomic) UIDeviceOrientation deviceOrientation;
@property(nonatomic, assign) NSInteger interfaceOrientation;
@property(nonatomic, assign) NSInteger statusBarStyle;
@end


@interface FBSSceneParameters : NSObject
@property(nonatomic, copy) UIApplicationSceneSettings *settings;
@property(nonatomic, copy) UIApplicationSceneClientSettings *clientSettings;
- (instancetype)initWithXPCDictionary:(NSDictionary*)dict;
@end

@interface FBSMutableSceneParameters : FBSSceneParameters
@property(nonatomic, copy) UIMutableApplicationSceneSettings *settings;
@end

@interface UIWindow (private)
- (void)setAutorotates:(BOOL)autorotates forceUpdateInterfaceOrientation:(BOOL)force;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)arg1 ;
- (BOOL)openURL:(id)url;
- (BOOL)isApplicationAvailableToOpenURL:(id)arg1 error:(id*)arg2;
@end

@interface UICustomViewMenuElement : UIMenuElement
+ (instancetype)elementWithViewProvider:(UIView *(^)(UICustomViewMenuElement *element))provider;

@end

@interface UINavigationBar(private)
- (UIFont *)_defaultTitleFont;
@end

@interface _UIPrototypingMenuSlider : UISlider
@property(nonatomic, assign, readwrite) CGFloat stepSize;
@end

@interface UISceneActivationRequestOptions(private)
-(void)_setRequestFullscreen:(BOOL)arg1;
@end

@interface _UIButtonBarStackView : UIView
- (void)setSpacing:(CGFloat)spacing;
@end

@interface UIView(private)
- (UIViewController *)_viewDelegate;
- (void)setSafeAreaInsets:(UIEdgeInsets)safeAreaInsets;
@end


@interface DOCConfiguration : NSObject
- (void)setHostIdentifier:(NSString *)ignored;
@end
