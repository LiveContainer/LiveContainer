//
//  PiPManager.m
//  LiveContainer
//
//  Created by s s on 2025/6/3.
//
#include "PiPManager.h"
#include "AppSceneViewController.h"
#include "DecoratedAppSceneViewController.h"
#include "../LiveContainer/utils.h"

API_AVAILABLE(ios(16.0))
@interface PiPManager()
@property(nonatomic, strong) AVPictureInPictureVideoCallViewController *pipVideoCallViewController;
@property(nonatomic, strong) AVPictureInPictureController *pipController;
@property(nonatomic) AppSceneViewController* displayingVC;
@end


@implementation PiPManager
API_AVAILABLE(ios(16.0))
static PiPManager* sharedInstance = nil;

+ (instancetype)shared {
    if(!sharedInstance)
        sharedInstance = [[self alloc] init];
    return sharedInstance;
}

- (DecoratedAppSceneViewController *)displayingDecoratedVC {
    return (id)self.displayingVC.delegate;
}

- (BOOL)isPiP {
    return self.pipController.isPictureInPictureActive;
}

- (BOOL)isPiPWithVC:(AppSceneViewController*)vc {
    return self.pipController.isPictureInPictureActive && self.displayingVC == vc;
}

- (BOOL)isPiPWithDecoratedVC:(UIViewController*)vc {
    return self.pipController.isPictureInPictureActive && self.displayingDecoratedVC == vc;
}

- (instancetype)init {
    NSError* error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    [[AVAudioSession sharedInstance] setActive:YES withOptions:1 error:&error];
    return self;
}

- (void)startPiPWithVC:(AppSceneViewController*)vc {
    [self.pipController stopPictureInPicture];
    if(self.displayingVC) {
        [self.displayingVC.view insertSubview:self.displayingVC.contentView atIndex:0];
        self.displayingVC.contentView.transform = CGAffineTransformIdentity;
        self.displayingVC = nil;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([self.pipController isPictureInPictureActive] * 0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.pipVideoCallViewController = [AVPictureInPictureVideoCallViewController new];
        self.pipVideoCallViewController.preferredContentSize = vc.view.bounds.size;
        AVPictureInPictureControllerContentSource* contentSource =  [[AVPictureInPictureControllerContentSource alloc] initWithActiveVideoCallSourceView:vc.view contentViewController:self.pipVideoCallViewController];
        self.pipController = [[AVPictureInPictureController alloc] initWithContentSource:contentSource];
        self.pipController.canStartPictureInPictureAutomaticallyFromInline = YES;
        self.pipController.delegate = self;
        [self.pipController setValue:@1 forKey:@"controlsStyle"];
        self.displayingVC = vc;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.pipController startPictureInPicture];
        });
    });

}

- (void)stopPiP {
    [self.pipController stopPictureInPicture];
}

// PIP delegate
- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    [self.displayingDecoratedVC minimizeWindowPiP];
    UIWindow *firstWindow = [UIApplication sharedApplication].windows.firstObject;
    self.displayingVC.contentView.frame = CGRectMake(0, 0, self.displayingVC.view.bounds.size.width, self.displayingVC.view.bounds.size.height);
    [firstWindow addSubview:self.displayingVC.contentView];
    [firstWindow.layer addObserver:self
                                forKeyPath:@"bounds"
                                   options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                                   context:NULL];
    self.pipVideoCallViewController.preferredContentSize = self.displayingVC.view.bounds.size;
    [self.displayingVC setBackgroundNotificationEnabled:false];
}


//⭐️⭐️⭐️
- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    [MultitaskDockManager.shared refreshMenu];
}

- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    [self.displayingDecoratedVC unminimizeWindowPiP];
}
//⭐️⭐️⭐️
- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    [MultitaskDockManager.shared refreshMenu];
    [self.displayingVC.view insertSubview:self.displayingVC.contentView atIndex:0];
    self.displayingVC.contentView.transform = CGAffineTransformIdentity;
    [self.displayingVC setBackgroundNotificationEnabled:true];
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCAutoEndPiP"]) {
        self.pipController = nil;
        self.pipVideoCallViewController = nil;
    }
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {
    NSLog(@"%@", error.description);
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(NSObject*)object change:(NSDictionary<NSString *,id> *) change context:(void *) context {
    CGRect rect = [change[@"new"] CGRectValue];
    CGAffineTransform transform1 = CGAffineTransformScale(CGAffineTransformIdentity, rect.size.width / self.displayingVC.contentView.bounds.size.width,rect.size.height /self.displayingVC.contentView.bounds.size.height);
    self.displayingVC.contentView.transform = transform1;
}

@end
