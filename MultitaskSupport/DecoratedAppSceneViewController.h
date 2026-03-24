#import <UIKit/UIKit.h> 
#import "FoundationPrivate.h"



@interface _UIPrototypingMenuSlider : UISlider
@property (nonatomic, assign) CGFloat stepSize;
@end


@class AppSceneViewController;
@class ResizeHandleView;

@protocol AppSceneViewControllerDelegate; 
@interface DecoratedAppSceneViewController : UIViewController <AppSceneViewControllerDelegate>

API_AVAILABLE(ios(16.0))
@interface DecoratedAppSceneViewController : UIViewController <AppSceneViewControllerDelegate>

@property (nonatomic, strong) AppSceneViewController *appSceneVC;
@property (nonatomic, strong) UIStackView *mainStackView;
@property (nonatomic, strong) UINavigationBar *navigationBar;
@property (nonatomic, strong) UINavigationItem *navigationItem;
@property (nonatomic, strong) ResizeHandleView *resizeHandle;
@property (nonatomic, strong) ResizeHandleView *moveHandle;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, assign) BOOL isMaximized;  
@property (nonatomic, assign) CGFloat scaleRatio;

- (instancetype)initWindowName:(NSString*)windowName bundleId:(NSString*)bundleId dataUUID:(NSString*)dataUUID rootVC:(UIViewController*)rootVC;
- (void)closeWindow;
- (void)maximizeWindow;
- (void)minimizeWindow;
- (void)minimizeWindowPiP;
- (void)unminimizeWindowPiP;
- (void)updateVerticalConstraints;

@property (nonatomic, copy) void (^pidAvailableHandler)(NSNumber *pid, NSError *error);

@end
