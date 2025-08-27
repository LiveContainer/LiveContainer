#import "DecoratedAppSceneViewController.h"
#import "ResizeHandleView.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "AppSceneViewController.h"
#import "UIKitPrivate+MultitaskSupport.h"
#import "PiPManager.h"
#import "../LiveContainer/Localization.h"
#import "utils.h"

@implementation RBSTarget(hook)
+ (instancetype)hook_targetWithPid:(pid_t)pid environmentIdentifier:(NSString *)environmentIdentifier {
    if([environmentIdentifier containsString:@"LiveProcess"]) {
        environmentIdentifier = [NSString stringWithFormat:@"LiveProcess:%d", pid];
    }
    return [self hook_targetWithPid:pid environmentIdentifier:environmentIdentifier];
}
@end
static int hook_return_2(void) {
    return 2;
}
__attribute__((constructor))
void UIKitFixesInit(void) {
    // Fix _UIPrototypingMenuSlider not continually updating its value on iOS 17+
    Class _UIFluidSliderInteraction = objc_getClass("_UIFluidSliderInteraction");
    if(_UIFluidSliderInteraction) {
        method_setImplementation(class_getInstanceMethod(_UIFluidSliderInteraction, @selector(_state)), (IMP)hook_return_2);
    }
    // Fix physical keyboard focus on iOS 17+
    if(@available(iOS 17.0, *)) {
        method_exchangeImplementations(class_getClassMethod(RBSTarget.class, @selector(targetWithPid:environmentIdentifier:)), class_getClassMethod(RBSTarget.class, @selector(hook_targetWithPid:environmentIdentifier:)));
    }
}

@interface DecoratedAppSceneViewController()
@property(nonatomic) NSArray* activatedVerticalConstraints;
@property(nonatomic) NSString* dataUUID;
@property(nonatomic) NSString* windowName;
@property(nonatomic) int pid;
@property(nonatomic) CGRect originalFrame;
@property(nonatomic) UIBarButtonItem *maximizeButton;
@property(nonatomic) bool isAppTerminationRequested;
@end

@implementation DecoratedAppSceneViewController
- (instancetype)initWindowName:(NSString*)windowName bundleId:(NSString*)bundleId dataUUID:(NSString*)dataUUID {
    self = [super initWithNibName:nil bundle:nil];
    _appSceneVC = [[AppSceneViewController alloc] initWithBundleId:bundleId dataUUID:dataUUID delegate:self];
    [self setupDecoratedView];
    
    [MultitaskDockManager.shared addRunningApp:windowName appUUID:dataUUID view:self.view];
    
    self.dataUUID = dataUUID;
    self.scaleRatio = 1.0;
    self.isMaximized = NO;
    self.originalFrame = CGRectZero;
    self.windowName = windowName;
    self.navigationItem.title = windowName;
    
    NSArray *menuItems = @[
        [UIAction actionWithTitle:@"lc.multitask.copyPid".loc image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction * _Nonnull action) {
            UIPasteboard.generalPasteboard.string = @(self.appSceneVC.pid).stringValue;
        }],
        [UIAction actionWithTitle:@"lc.multitask.enablePip".loc image:[UIImage systemImageNamed:@"pip.enter"] identifier:nil handler:^(UIAction * _Nonnull action) {
            if ([PiPManager.shared isPiPWithVC:self.appSceneVC]) {
                [PiPManager.shared stopPiP];
            } else {
                [PiPManager.shared startPiPWithVC:self.appSceneVC];
            }
        }],
        [UICustomViewMenuElement elementWithViewProvider:^UIView *(UICustomViewMenuElement *element) {
            return [self scaleSliderViewWithTitle:@"lc.multitask.scale".loc min:0.5 max:2.0 value:self.scaleRatio stepInterval:0.01];
        }]
    ];
    

    __weak typeof(self) weakSelf = self;
    [self.navigationItem setTitleMenuProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions){
        if(!weakSelf.appSceneVC.isAppRunning) {
            return [UIMenu menuWithTitle:NSLocalizedString(@"lc.multitaskAppWindow.appTerminated", nil) children:@[]];
        } else {
            NSString *pidText = [NSString stringWithFormat:@"PID: %d", weakSelf.pid];
            return [UIMenu menuWithTitle:pidText children:menuItems];
        }
    }];
    
    UIImage *minimizeImage = [UIImage systemImageNamed:@"minus.circle"];
    UIImageConfiguration *minimizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    minimizeImage = [minimizeImage imageWithConfiguration:minimizeConfig];
    UIBarButtonItem *minimizeButton = [[UIBarButtonItem alloc] initWithImage:minimizeImage style:UIBarButtonItemStylePlain target:self action:@selector(minimizeWindow)];
    minimizeButton.tintColor = [UIColor systemYellowColor];
    
    UIImage *maximizeImage = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right.circle"];
    UIImageConfiguration *maximizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    maximizeImage = [maximizeImage imageWithConfiguration:maximizeConfig];
    self.maximizeButton = [[UIBarButtonItem alloc] initWithImage:maximizeImage style:UIBarButtonItemStylePlain target:self action:@selector(maximizeWindow)];
    self.maximizeButton.tintColor = [UIColor systemGreenColor];
    
    UIImage *closeImage = [UIImage systemImageNamed:@"xmark.circle"];
    UIImageConfiguration *closeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    closeImage = [closeImage imageWithConfiguration:closeConfig];
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithImage:closeImage style:UIBarButtonItemStylePlain target:self action:@selector(closeWindow)];
    closeButton.tintColor = [UIColor systemRedColor];
    
    NSArray *barButtonItems = @[closeButton, self.maximizeButton, minimizeButton];
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"]) {
        // resize handle overlaps the close button, so put the buttons on the left
        self.navigationItem.leftBarButtonItems = barButtonItems;
    } else {
        self.navigationItem.rightBarButtonItems = barButtonItems;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self adjustNavigationBarButtonSpacingWithNegativeSpacing:-8.0 rightMargin:-4.0];
    });

    return self;
}

- (void)setupDecoratedView {
    CGFloat navBarHeight = 44;
    self.view = [UIStackView new];
    if(UIInterfaceOrientationIsLandscape(UIApplication.sharedApplication.statusBarOrientation)) {
        self.view.frame = CGRectMake(50, 150, 480, 320 + navBarHeight);
    } else {
        self.view.frame = CGRectMake(50, 150, 320, 480 + navBarHeight);
    }
    
    // Navigation bar
    UINavigationBar *navigationBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, navBarHeight)];
    navigationBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UINavigationItem *navigationItem = [[UINavigationItem alloc] initWithTitle:@"Unnamed window"];
    navigationBar.items = @[navigationItem];
    
    self.view.axis = UILayoutConstraintAxisVertical;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.layer.cornerRadius = 10;
    self.view.layer.masksToBounds = YES;

    self.navigationBar = navigationBar;
    self.navigationItem = navigationBar.items.firstObject;
    if (!self.navigationBar.superview) {
        [self.view addArrangedSubview:self.navigationBar];
    }
    
    CGRect contentFrame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height - navBarHeight);
    UIView *fixedPositionContentView = [[UIView alloc] initWithFrame:contentFrame];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"]) {
        [self.view insertArrangedSubview:fixedPositionContentView atIndex:0];
    } else {
        [self.view addArrangedSubview:fixedPositionContentView];
    }
    [self.view sendSubviewToBack:fixedPositionContentView];
    
    self.contentView = [[UIView alloc] initWithFrame:contentFrame];
    self.contentView.layer.anchorPoint = self.contentView.layer.position = CGPointMake(0, 0);
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [fixedPositionContentView addSubview:self.contentView];
    
    UIPanGestureRecognizer *moveGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveWindow:)];
    moveGesture.minimumNumberOfTouches = 1;
    moveGesture.maximumNumberOfTouches = 1;
    [self.navigationBar addGestureRecognizer:moveGesture];

    // Resize handle (idea stolen from Notes debugging window)
    UIPanGestureRecognizer *resizeGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizeWindow:)];
    resizeGesture.minimumNumberOfTouches = 1;
    resizeGesture.maximumNumberOfTouches = 1;
    self.resizeHandle = [[ResizeHandleView alloc] initWithFrame:CGRectMake(self.view.frame.size.width - navBarHeight, self.view.frame.size.height - navBarHeight, navBarHeight, navBarHeight)];
    [self.resizeHandle addGestureRecognizer:resizeGesture];
    [self.view addSubview:self.resizeHandle];
    
    self.view.layer.borderWidth = 1.0;
    self.view.layer.borderColor = UIColor.secondarySystemBackgroundColor.CGColor;
    
    [self addChildViewController:_appSceneVC];
    [self.view insertSubview:_appSceneVC.view atIndex:0];
    _appSceneVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self updateVerticalConstraints];
    [NSLayoutConstraint activateConstraints:@[
        [_appSceneVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_appSceneVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    
    
    NSUserDefaults *defaults = NSUserDefaults.lcSharedDefaults;

    [defaults addObserver:self forKeyPath:@"LCMultitaskBottomWindowBar" options:NSKeyValueObservingOptionNew context:NULL];
    [self updateOriginalFrame];
}


// Stolen from UIKitester
- (UIView *)scaleSliderViewWithTitle:(NSString *)title min:(CGFloat)minValue max:(CGFloat)maxValue value:(CGFloat)initialValue stepInterval:(CGFloat)step {
    UIView *containerView = [[UIView alloc] init];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    containerView.exclusiveTouch = YES;

    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 0.0;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:stackView];
    
    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:10.0],
        [stackView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-8.0],
        [stackView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:16.0],
        [stackView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16.0]
    ]];
    
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont boldSystemFontOfSize:12.0];
    [stackView addArrangedSubview:label];
    
    _UIPrototypingMenuSlider *slider = [[_UIPrototypingMenuSlider alloc] init];
    slider.minimumValue = minValue;
    slider.maximumValue = maxValue;
    slider.value = initialValue;
    slider.stepSize = step;
    
    NSLayoutConstraint *sliderHeight = [slider.heightAnchor constraintEqualToConstant:40.0];
    sliderHeight.active = YES;
    
    [stackView addArrangedSubview:slider];
    
    [slider addTarget:self action:@selector(scaleSliderChanged:) forControlEvents:UIControlEventValueChanged];
    
    return containerView;
}

- (void)scaleSliderChanged:(_UIPrototypingMenuSlider *)slider {
    self.scaleRatio = slider.value;
    self.appSceneVC.scaleRatio = _scaleRatio;
    self.appSceneVC.contentView.layer.sublayerTransform = CATransform3DMakeScale(_scaleRatio, _scaleRatio, 1.0);
    [self.appSceneVC updateFrameWithSettingsBlock:^(UIMutableApplicationSceneSettings *settings) {
        [self updateMaximizedSafeAreaWithSettings:settings];
    }];
}

- (void)closeWindow {
    _isAppTerminationRequested = true;
    if([_appSceneVC isAppRunning]) {
        [_appSceneVC terminate];
    } else {
        [self appSceneVCAppDidExit:self.appSceneVC];
    }
}

- (void)minimizeWindow {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.alpha = 0;
        self.view.transform = CGAffineTransformMakeScale(0.1, 0.1);
    } completion:^(BOOL finished) {
        self.view.hidden = YES;
        self.view.transform = CGAffineTransformIdentity;
    }];
}

- (void)minimizeWindowPiP {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished) {
        self.view.hidden = YES;
    }];
}

- (void)unminimizeWindowPiP {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.hidden = NO;
        self.view.alpha = 1;
    } completion:nil];
}

- (void)maximizeWindow {
    if (self.isMaximized) {
        CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, self.view.window.safeAreaInsets);
        CGRect newFrame = CGRectMake(self.originalFrame.origin.x * maxFrame.size.width, self.originalFrame.origin.y * maxFrame.size.height, self.originalFrame.size.width, self.originalFrame.size.height);
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.view.frame = newFrame;
            self.view.layer.borderWidth = 1;
            self.resizeHandle.alpha = 1;
            [self.appSceneVC.presenter.scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
                [self updateWindowedFrameWithSettings:settings];
            }];
        } completion:^(BOOL finished) {
            self.isMaximized = NO;
            UIImage *maximizeImage = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right.circle"];
            UIImageConfiguration *maximizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
            self.maximizeButton.image = [maximizeImage imageWithConfiguration:maximizeConfig];
        }];
    } else {
        [self updateOriginalFrame];
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.isMaximized = YES;
            [self updateVerticalConstraints];
            
            self.view.layer.borderWidth = 0;
            self.resizeHandle.alpha = 0;
            [self.appSceneVC.presenter.scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
                [self updateMaximizedFrameWithSettings:settings];
            }];
        } completion:^(BOOL finished) {
            UIImage *restoreImage = [UIImage systemImageNamed:@"arrow.down.right.and.arrow.up.left.circle"];
            UIImageConfiguration *restoreConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
            self.maximizeButton.image = [restoreImage imageWithConfiguration:restoreConfig];
        }];
    }
}

- (void)appSceneVCAppDidExit:(AppSceneViewController*)vc {
    if(_isAppTerminationRequested) {
        
        MultitaskDockManager *dock = [MultitaskDockManager shared];
        [dock removeRunningApp:self.dataUUID];
        
        self.view.layer.masksToBounds = NO;
        [UIView transitionWithView:self.view duration:0.4 options:UIViewAnimationOptionTransitionCurlUp animations:^{
            self.view.hidden = YES;
        } completion:^(BOOL b){
            [self.view removeFromSuperview];
        }];
    } else {
        UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.numberOfLines = 0;
        label.text = NSLocalizedString(@"lc.multitaskAppWindow.appTerminated", @"");
        label.textAlignment = NSTextAlignmentCenter;
        [self.view insertSubview:label atIndex:0];
    }
}

- (void)appSceneVC:(AppSceneViewController*)vc didInitializeWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if(error) {
            [vc appTerminationCleanUp];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"lc.common.error".loc message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"lc.common.copy".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                UIPasteboard.generalPasteboard.string = error.localizedDescription;
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            self.pid = vc.pid;
            [self updateOriginalFrame];
            
            // Check if default maximized mode is enabled
            if ([NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskDefaultMaximized"]) {
                // Delay the maximization slightly to allow the window to be properly set up
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (!self.isMaximized) {
                        [self maximizeWindow];
                    }
                });
            }
        }
    });
}

- (void)appSceneVC:(AppSceneViewController*)vc didUpdateFromSettings:(UIMutableApplicationSceneSettings *)baseSettings transitionContext:(id)newContext {
    UIMutableApplicationSceneSettings *newSettings = [vc.presenter.scene.settings mutableCopy];
    newSettings.userInterfaceStyle = baseSettings.userInterfaceStyle;
    newSettings.interfaceOrientation = baseSettings.interfaceOrientation;
    newSettings.deviceOrientation = baseSettings.deviceOrientation;
    newSettings.foreground = YES;
    
    if(self.isMaximized) {
        [self updateMaximizedFrameWithSettings:newSettings];
    } else {
        [self updateWindowedFrameWithSettings:newSettings];
    }
    CGRect newFrame = CGRectMake(0, 0, self.view.frame.size.width/self.scaleRatio, (self.view.frame.size.height - self.navigationBar.frame.size.height)/self.scaleRatio);
    
    if(UIInterfaceOrientationIsLandscape(baseSettings.interfaceOrientation)) {
        newSettings.frame = CGRectMake(0, 0, newFrame.size.height, newFrame.size.width);
    } else {
        newSettings.frame = CGRectMake(0, 0, newFrame.size.width, newFrame.size.height);
    }
    
    [_appSceneVC.presenter.scene updateSettings:newSettings withTransitionContext:newContext completion:nil];
}

- (void)adjustNavigationBarButtonSpacingWithNegativeSpacing:(CGFloat)spacing rightMargin:(CGFloat)margin {
    if (!self.navigationBar) return;
    [self findAndAdjustButtonBarStackView:self.navigationBar withSpacing:spacing rightMargin:margin];
}

- (void)findAndAdjustButtonBarStackView:(UIView *)view withSpacing:(CGFloat)spacing rightMargin:(CGFloat)margin {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"_UIButtonBarStackView")]) {
            if ([subview respondsToSelector:@selector(setSpacing:)]) {
                [(_UIButtonBarStackView *)subview setSpacing:spacing];
            }
            
            if (subview.superview) {
                for (NSLayoutConstraint *constraint in subview.superview.constraints) {
                    if ((constraint.firstItem == subview && constraint.firstAttribute == NSLayoutAttributeTrailing) ||
                        (constraint.secondItem == subview && constraint.secondAttribute == NSLayoutAttributeTrailing)) {
                        constraint.constant = (constraint.firstItem == subview) ? -margin : margin;
                        break;
                    }
                }
                
                [subview setNeedsLayout];
                [subview.superview setNeedsLayout];
            }
            
            return;
        }
        
        [self findAndAdjustButtonBarStackView:subview withSpacing:spacing rightMargin:margin];
    }
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(_isMaximized) {
        [self.appSceneVC.presenter.scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
            [self updateMaximizedFrameWithSettings:settings];
        }];
    }
    
    BOOL bottomWindowBar = [change[NSKeyValueChangeNewKey] boolValue];
    [UIView animateWithDuration:0.3 animations:^{
        if(bottomWindowBar) {
            self.navigationItem.leftBarButtonItems = self.navigationItem.rightBarButtonItems;
            self.navigationItem.rightBarButtonItems = nil;
            [self.view addArrangedSubview:self.navigationBar];
        } else {
            self.navigationItem.rightBarButtonItems = self.navigationItem.leftBarButtonItems;
            self.navigationItem.leftBarButtonItems = nil;
            [self.view insertArrangedSubview:self.navigationBar atIndex:0];
        }
        
        [self updateVerticalConstraints];
        [self adjustNavigationBarButtonSpacingWithNegativeSpacing:-8.0 rightMargin:-4.0];
    }];
}

- (void)moveWindow:(UIPanGestureRecognizer*)sender {
    if(_isMaximized) return;
    
    CGPoint point = [sender translationInView:self.view];
    [sender setTranslation:CGPointZero inView:self.view];

    self.view.center = CGPointMake(self.view.center.x + point.x, self.view.center.y + point.y);
    [self updateOriginalFrame];
}

- (void)resizeWindow:(UIPanGestureRecognizer*)sender {
    if(_isMaximized) return;
    
    CGPoint point = [sender translationInView:self.view];
    [sender setTranslation:CGPointZero inView:self.view];

    CGRect frame = self.view.frame;
    frame.size.width = MAX(50, frame.size.width + point.x);
    frame.size.height = MAX(50, frame.size.height + point.y);
    self.view.frame = frame;
    [self updateOriginalFrame];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    // FIXME: how to bring view to front when touching the passthrough view?
    [self.view.superview bringSubviewToFront:self.view];
}

- (void)updateVerticalConstraints {
    // Update safe area insets
    if(_isMaximized) {
        __weak typeof(self) weakSelf = self;
        self.appSceneVC.nextUpdateSettingsBlock = ^(UIMutableApplicationSceneSettings *settings) {
            [weakSelf updateMaximizedFrameWithSettings:settings];
        };
    }
    
    BOOL bottomWindowBar = [NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"];
    BOOL hideWindowBar = MultitaskDockManager.shared.isCollapsed && _isMaximized;
    CGFloat navBarHeight = hideWindowBar ? 0 : 44;
    self.navigationBar.hidden = hideWindowBar;
    
    [NSLayoutConstraint deactivateConstraints:self.activatedVerticalConstraints];
    if(bottomWindowBar) {
        self.activatedVerticalConstraints = @[
            [self.appSceneVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [self.appSceneVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-navBarHeight],
            [self.navigationBar.heightAnchor constraintEqualToConstant:navBarHeight]
        ];
    } else {
        self.activatedVerticalConstraints = @[
            [self.appSceneVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:navBarHeight],
            [self.appSceneVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
            [self.navigationBar.heightAnchor constraintEqualToConstant:navBarHeight]
        ];
    }
    [NSLayoutConstraint activateConstraints:self.activatedVerticalConstraints];
}

- (UIEdgeInsets)updateMaximizedSafeAreaWithSettings:(UIMutableApplicationSceneSettings *)settings {
    BOOL bottomWindowBar = [NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"];
    UIEdgeInsets safeAreaInsets = self.view.window.safeAreaInsets;
    if(self.navigationBar.hidden) {
        settings.peripheryInsets = safeAreaInsets;
        safeAreaInsets = UIEdgeInsetsZero;
    } else if(bottomWindowBar) {
        // allow the control bar to overlap the bottom safe area
        safeAreaInsets.bottom = 0;
        settings.peripheryInsets = safeAreaInsets;
        safeAreaInsets.top = safeAreaInsets.left = safeAreaInsets.right = 0;
    } else {
        settings.peripheryInsets = UIEdgeInsetsMake(0, safeAreaInsets.left, safeAreaInsets.bottom, safeAreaInsets.right);
        safeAreaInsets.bottom = safeAreaInsets.left = safeAreaInsets.right = 0;
    }
    
    // scale peripheryInsets to match the scale ratio
    settings.peripheryInsets = UIEdgeInsetsMake(settings.peripheryInsets.top/_scaleRatio, settings.peripheryInsets.left/_scaleRatio, settings.peripheryInsets.bottom/_scaleRatio, settings.peripheryInsets.right/_scaleRatio);
    if(UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation currentOrientation = UIApplication.sharedApplication.statusBarOrientation;
        if(UIInterfaceOrientationIsLandscape(currentOrientation)) {
            safeAreaInsets.top = 0;
        }
        switch(currentOrientation) {
            case UIInterfaceOrientationLandscapeLeft:
                settings.safeAreaInsetsPortrait = UIEdgeInsetsMake(settings.peripheryInsets.left, 0, settings.peripheryInsets.right, settings.peripheryInsets.bottom);
                break;
            case UIInterfaceOrientationLandscapeRight:
                settings.safeAreaInsetsPortrait = UIEdgeInsetsMake(settings.peripheryInsets.left, settings.peripheryInsets.bottom, settings.peripheryInsets.right, 0);
                break;
            default:
                settings.safeAreaInsetsPortrait = UIEdgeInsetsMake(settings.peripheryInsets.top, settings.peripheryInsets.left, settings.peripheryInsets.bottom, settings.peripheryInsets.right);
                break;
        }

    } else {
        settings.safeAreaInsetsPortrait = UIEdgeInsetsMake(settings.peripheryInsets.top, settings.peripheryInsets.left, settings.peripheryInsets.bottom, settings.peripheryInsets.right);
    }
    
    safeAreaInsets.bottom = 0;
    return safeAreaInsets;
}

- (void)updateMaximizedFrameWithSettings:(UIMutableApplicationSceneSettings *)settings {
    CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, [self updateMaximizedSafeAreaWithSettings:settings]);
    self.view.frame = maxFrame;
}

- (void)updateWindowedFrameWithSettings:(UIMutableApplicationSceneSettings *)settings {
    UIEdgeInsets safeAreaInsets = self.view.window.safeAreaInsets;
    CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, safeAreaInsets);
    settings.peripheryInsets = UIEdgeInsetsZero;
    settings.safeAreaInsetsPortrait = UIEdgeInsetsZero;
    
    CGRect newFrame = CGRectMake(self.originalFrame.origin.x * maxFrame.size.width, self.originalFrame.origin.y * maxFrame.size.height, self.originalFrame.size.width, self.originalFrame.size.height);
    CGPoint center = self.view.center;
    CGRect frame = CGRectZero;
    frame.size.width = MIN(newFrame.size.width, maxFrame.size.width);
    frame.size.height = MIN(newFrame.size.height, maxFrame.size.height);
    CGFloat oobOffset = MAX(30, frame.size.width - 30);
    frame.origin.x = MAX(maxFrame.origin.x - oobOffset, MIN(CGRectGetMaxX(maxFrame) - frame.size.width + oobOffset, center.x - frame.size.width / 2));
    frame.origin.y = MAX(maxFrame.origin.y, MIN(center.y - frame.size.height / 2, CGRectGetMaxY(maxFrame) - frame.size.height));
    [UIView animateWithDuration:0.3 animations:^{
        self.view.frame = frame;
    }];
}

- (void)updateOriginalFrame {
    CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, self.view.window.safeAreaInsets);
    // save origin as normalized coordinates
    self.originalFrame = CGRectMake(self.view.frame.origin.x / maxFrame.size.width, self.view.frame.origin.y / maxFrame.size.height, self.view.frame.size.width, self.view.frame.size.height);
}

@end
