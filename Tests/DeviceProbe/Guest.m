// Controlled guest for manual device validation. Same license as this repository.
#import <UIKit/UIKit.h>

@interface LCOSProbeController : UIViewController
@property(nonatomic, strong) UILabel *result;
- (void)probeTapped:(id)sender;
@end
@implementation LCOSProbeController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.result = [UILabel new];
    self.result.text = @"Tap Run hook probe. Unmodified result: ORIGINAL";
    self.result.numberOfLines = 0;
    self.result.accessibilityIdentifier = @"probe-result";
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"Run hook probe" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(probeTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.result, button]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 24;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}
- (void)probeTapped:(id)sender { self.result.text = @"ORIGINAL"; }
@end

@interface LCOSProbeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation LCOSProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [LCOSProbeController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(LCOSProbeDelegate.class)); }
}
