@import UIKit;
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "../LiveContainer/utils.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import "Localization.h"

UIInterfaceOrientation LCOrientationLock = UIInterfaceOrientationUnknown;
NSMutableArray<NSString*>* LCSupportedUrlSchemes = nil;
BOOL launchURLProcessed = NO;

__attribute__((constructor))
static void UIKitGuestHooksInit() {
    if(!NSUserDefaults.lcGuestAppId) return;
    swizzle(UIApplication.class, @selector(_applicationOpenURLAction:payload:origin:), @selector(hook__applicationOpenURLAction:payload:origin:));
    swizzle(UIApplication.class, @selector(_connectUISceneFromFBSScene:transitionContext:), @selector(hook__connectUISceneFromFBSScene:transitionContext:));
    swizzle(UIApplication.class, @selector(openURL:options:completionHandler:), @selector(hook_openURL:options:completionHandler:));
    swizzle(UIApplication.class, @selector(canOpenURL:), @selector(hook_canOpenURL:));
    swizzle(UIApplication.class, @selector(setDelegate:), @selector(hook_setDelegate:));
    swizzle(UIScene.class, @selector(scene:didReceiveActions:fromTransitionContext:), @selector(hook_scene:didReceiveActions:fromTransitionContext:));
    swizzle(UIScene.class, @selector(openURL:options:completionHandler:), @selector(hook_openURL:options:completionHandler:));
    NSInteger LCOrientationLockDirection = [NSUserDefaults.guestAppInfo[@"LCOrientationLock"] integerValue];
    if(LCOrientationLockDirection != 0 && [UIDevice.currentDevice userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        switch (LCOrientationLockDirection) {
            case 1:
                LCOrientationLock = UIInterfaceOrientationLandscapeRight;
                break;
            case 2:
                LCOrientationLock = UIInterfaceOrientationPortrait;
                break;
            default:
                break;
        }
        if(!NSUserDefaults.isLiveProcess && LCOrientationLock != UIInterfaceOrientationUnknown) {
//            swizzle(UIApplication.class, @selector(_handleDelegateCallbacksWithOptions:isSuspended:restoreState:), @selector(hook__handleDelegateCallbacksWithOptions:isSuspended:restoreState:));
            swizzle(FBSSceneParameters.class, @selector(initWithXPCDictionary:), @selector(hook_initWithXPCDictionary:));
            swizzle(UIViewController.class, @selector(__supportedInterfaceOrientations), @selector(hook___supportedInterfaceOrientations));
            swizzle(UIViewController.class, @selector(shouldAutorotateToInterfaceOrientation:), @selector(hook_shouldAutorotateToInterfaceOrientation:));
            swizzle(UIWindow.class, @selector(setAutorotates:forceUpdateInterfaceOrientation:), @selector(hook_setAutorotates:forceUpdateInterfaceOrientation:));
        }

    }
}

NSString* findDefaultContainerWithBundleId(NSString* bundleId) {
    // find app's default container
    NSString *appGroupPath = [NSUserDefaults lcAppGroupPath];
    NSString* appGroupFolder = [appGroupPath stringByAppendingPathComponent:@"LiveContainer"];
    
    NSString* bundleInfoPath = [NSString stringWithFormat:@"%@/Applications/%@/LCAppInfo.plist", appGroupFolder, bundleId];
    NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfFile:bundleInfoPath];
    if(!infoDict) {
        NSString* lcDocFolder = [[NSString stringWithUTF8String:getenv("LC_HOME_PATH")] stringByAppendingPathComponent:@"Documents"];
        
        bundleInfoPath = [NSString stringWithFormat:@"%@/Applications/%@/LCAppInfo.plist", lcDocFolder, bundleId];
        infoDict = [NSDictionary dictionaryWithContentsOfFile:bundleInfoPath];
    }
    
    return infoDict[@"LCDataUUID"];
}

void forEachInstalledNotCurrentLC(BOOL isFree, void (^block)(NSString* scheme, BOOL* isBreak)) {
    for(NSString* scheme in [NSClassFromString(@"LCSharedUtils") lcUrlSchemes]) {
        if([scheme isEqualToString:NSUserDefaults.lcAppUrlScheme]) {
            continue;
        }
        BOOL isInstalled = [UIApplication.sharedApplication canOpenURL:[NSURL URLWithString: [NSString stringWithFormat: @"%@://", scheme]]];
        if(!isInstalled) {
            continue;
        }
        BOOL isBreak = false;
        if(isFree && [NSClassFromString(@"LCSharedUtils") isLCSchemeInUse:scheme]) {
            continue;
        }
        block(scheme, &isBreak);
        if(isBreak) {
            return;
        }
    }
}

void LCShowSwitchAppConfirmation(NSURL *url, NSString* bundleId, bool isSharedApp) {
    NSURLComponents* newUrlComp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    
    // check if there's any free LiveContainer to run the app
    if(isSharedApp) {
        __block BOOL anotherLCLaunched = false;
        forEachInstalledNotCurrentLC(YES, ^(NSString * scheme, BOOL* isBreak) {
            newUrlComp.scheme = scheme;
            [UIApplication.sharedApplication openURL:newUrlComp.URL options:@{} completionHandler:nil];
            *isBreak = YES;
            anotherLCLaunched = YES;
            return;
        });
        if(anotherLCLaunched) {
            return;
        }
    }
    
    // if LCSwitchAppWithoutAsking is enabled we directly open the app in current lc
    if ([NSUserDefaults.lcUserDefaults boolForKey:@"LCSwitchAppWithoutAsking"]) {
        [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithURL:url];
        return;
    }

    NSString *message = [@"lc.guestTweak.appSwitchTip %@" localizeWithFormat:bundleId];
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [NSUserDefaults.lcUserDefaults setBool:NO forKey:@"LCOpenSideStore"];
        [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithURL:url];
        window.windowScene = nil;
    }];
    [alert addAction:okAction];
    
    if(isSharedApp) {
        forEachInstalledNotCurrentLC(NO, ^(NSString * scheme, BOOL* isBreak) {
            UIAlertAction* openlcAction = [UIAlertAction actionWithTitle:[@"lc.guestTweak.openInLc %@" localizeWithFormat:scheme] style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
                newUrlComp.scheme = scheme;
                [UIApplication.sharedApplication openURL:newUrlComp.URL options:@{} completionHandler:nil];
                window.windowScene = nil;
            }];
            [alert addAction:openlcAction];
        });
    }
    
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"lc.common.cancel".loc style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void LCShowAlert(NSString* message) {
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:okAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void LCShowAppNotFoundAlert(NSString* bundleId) {
    LCShowAlert([@"lc.guestTweak.error.bundleNotFound %@" localizeWithFormat: bundleId]);
}

void openUniversalLink(NSString* decodedUrl) {
    NSURL* urlToOpen = [NSURL URLWithString: decodedUrl];
    if(![urlToOpen.scheme isEqualToString:@"https"] && ![urlToOpen.scheme isEqualToString:@"http"]) {
        NSData *data = [decodedUrl dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
        
        NSString* finalUrl = [NSString stringWithFormat:@"%@://open-url?url=%@", NSUserDefaults.lcAppUrlScheme, encodedUrl];
        NSURL* url = [NSURL URLWithString: finalUrl];
        
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    UIActivityContinuationManager* uacm = [[UIApplication sharedApplication] _getActivityContinuationManager];
    NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
    activity.webpageURL = urlToOpen;
    NSDictionary* dict = @{
        @"UIApplicationLaunchOptionsUserActivityKey": activity,
        @"UICanvasConnectionOptionsUserActivityKey": activity,
        @"UIApplicationLaunchOptionsUserActivityIdentifierKey": NSUUID.UUID.UUIDString,
        @"UINSUserActivitySourceApplicationKey": @"com.apple.mobilesafari",
        @"UIApplicationLaunchOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb,
        @"_UISceneConnectionOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb,
        @"_UISceneConnectionOptionsUserActivityKey": activity,
        @"UICanvasConnectionOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb
    };
    
    [uacm handleActivityContinuation:dict isSuspended:nil];
}

void LCOpenWebPage(NSString* webPageUrlString, NSString* originalUrl) {
    if ([NSUserDefaults.lcUserDefaults boolForKey:@"LCOpenWebPageWithoutAsking"]) {
        openUniversalLink(webPageUrlString);
        return;
    }
    
    NSURLComponents* newUrlComp = [NSURLComponents componentsWithString:originalUrl];
    __block BOOL anotherLCLaunched = false;
    forEachInstalledNotCurrentLC(YES, ^(NSString * scheme, BOOL* isBreak) {
        newUrlComp.scheme = scheme;
        [UIApplication.sharedApplication openURL:newUrlComp.URL options:@{} completionHandler:nil];
        *isBreak = YES;
        anotherLCLaunched = YES;
        return;
    });
    if(anotherLCLaunched) {
        return;
    }
    
    NSString *message = @"lc.guestTweak.openWebPageTip".loc;
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [NSClassFromString(@"LCSharedUtils") setWebPageUrlForNextLaunch:webPageUrlString];
        [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithClassicMode:0];
    }];
    [alert addAction:okAction];
    UIAlertAction* openNowAction = [UIAlertAction actionWithTitle:@"lc.guestTweak.openInCurrentApp".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        openUniversalLink(webPageUrlString);
        window.windowScene = nil;
    }];

    forEachInstalledNotCurrentLC(NO, ^(NSString * scheme, BOOL* isBreak) {
        UIAlertAction* openlc2Action = [UIAlertAction actionWithTitle:[@"lc.guestTweak.openInLc %@" localizeWithFormat:scheme] style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            newUrlComp.scheme = scheme;
            [UIApplication.sharedApplication openURL:newUrlComp.URL options:@{} completionHandler:nil];
            window.windowScene = nil;
        }];
        [alert addAction:openlc2Action];
    });
    
    [alert addAction:openNowAction];
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"lc.common.cancel".loc style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    

}

void LCOpenSideStoreURL(NSURL* sidestoreUrl) {
    if ([NSUserDefaults.lcUserDefaults boolForKey:@"LCSwitchAppWithoutAsking"]) {
        [NSUserDefaults.lcUserDefaults setObject:sidestoreUrl.absoluteString forKey:@"launchAppUrlScheme"];
        [NSUserDefaults.lcUserDefaults setObject:@"builtinSideStore" forKey:@"selected"];
        [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithClassicMode:0];
    }
    NSString *message = [@"lc.guestTweak.appSwitchTip %@" localizeWithFormat:@"SideStore"];
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [NSUserDefaults.lcUserDefaults setObject:sidestoreUrl.absoluteString forKey:@"launchAppUrlScheme"];
        [NSUserDefaults.lcUserDefaults setObject:@"builtinSideStore" forKey:@"selected"];
        [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithClassicMode:0];
    }];
    [alert addAction:okAction];
    
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"lc.common.cancel".loc style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
}

void authenticateUser(void (^completion)(BOOL success, NSError *error)) {
    LAContext *context = [[LAContext alloc] init];
    NSError *error = nil;

    if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&error]) {
        NSString *reason = @"lc.utils.requireAuthentication".loc;

        // Evaluate the policy for both biometric and passcode authentication
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
                localizedReason:reason
                          reply:^(BOOL success, NSError * _Nullable evaluationError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    completion(YES, nil);
                } else {
                    completion(NO, evaluationError);
                }
            });
        }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if([error code] == LAErrorPasscodeNotSet) {
                completion(YES, nil);
            } else {
                completion(NO, error);
            }
        });
    }
}

void handleLiveContainerLaunch(NSString* bundleName, NSString* containerFolderName, NSURL* url) {
    // check if there are other LCs is running this app
        NSString* runningLC = [NSClassFromString(@"LCSharedUtils") getContainerUsingLCSchemeWithFolderName:containerFolderName];
        // the app is running in an lc, that lc is not me, also is not my avatar
        if(runningLC) {
            if([runningLC hasSuffix:@"liveprocess"]) {
                runningLC = runningLC.stringByDeletingPathExtension;
            }
            NSString* urlStr = [NSString stringWithFormat:@"%@://livecontainer-launch?bundle-name=%@&container-folder-name=%@", runningLC, bundleName, containerFolderName];
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:urlStr] options:@{} completionHandler:nil];
            return;
        }
        
        bool isSharedApp = false;
        NSBundle* bundle = [NSClassFromString(@"LCSharedUtils") findBundleWithBundleId: bundleName isSharedAppOut:&isSharedApp];
        NSDictionary* lcAppInfo;
        if(bundle) {
            lcAppInfo = [NSDictionary dictionaryWithContentsOfURL:[bundle URLForResource:@"LCAppInfo" withExtension:@"plist"]];
        }
        
        if(!bundle || ([lcAppInfo[@"isHidden"] boolValue] && [NSUserDefaults.lcSharedDefaults boolForKey:@"LCStrictHiding"])) {
            LCShowAppNotFoundAlert(bundleName);
        } else if ([lcAppInfo[@"isLocked"] boolValue]) {
            // need authentication
            authenticateUser(^(BOOL success, NSError *error) {
                if (success) {
                    LCShowSwitchAppConfirmation(url, bundleName, isSharedApp);
                } else {
                    if ([error.domain isEqualToString:LAErrorDomain]) {
                        if (error.code != LAErrorUserCancel) {
                            NSLog(@"[LC] Authentication Error: %@", error.localizedDescription);
                        }
                    } else {
                        NSLog(@"[LC] Authentication Error: %@", error.localizedDescription);
                    }
                }
            });
        } else {
            LCShowSwitchAppConfirmation(url, bundleName, isSharedApp);
        }
    
}

BOOL shouldRedirectOpenURLToHost(NSURL* url) {
    NSUserDefaults *ud = NSUserDefaults.lcSharedDefaults;
    return NSUserDefaults.isLiveProcess &&
    [ud boolForKey:@"LCRedirectURLToHost"] &&
    [[ud arrayForKey:@"LCGuestURLSchemes"] containsObject:url.scheme];
}
BOOL canAppOpenItself(NSURL* url) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        NSArray *urlTypes = [infoDictionary objectForKey:@"CFBundleURLTypes"];
        LCSupportedUrlSchemes = [[NSMutableArray alloc] init];
        for (NSDictionary *urlType in urlTypes) {
            NSArray *schemes = [urlType objectForKey:@"CFBundleURLSchemes"];
            for(NSString* scheme in schemes) {
                [LCSupportedUrlSchemes addObject:[scheme lowercaseString]];
            }
        }
    });
    return [LCSupportedUrlSchemes containsObject:[url.scheme lowercaseString]];
}

typedef NS_ENUM(NSInteger, LCControlAppURLHandling) {
    LCControlAppURLHandlingPassThrough,
    LCControlAppURLHandlingReplaceURL,
    LCControlAppURLHandlingStop,
};

static NSString* LCDecodedURLStringFromControlURL(NSURL *url) {
    NSURLComponents* lcUrl = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString* realUrlEncoded = nil;
    for(NSURLQueryItem *queryItem in lcUrl.queryItems) {
        if([queryItem.name isEqualToString:@"url"]) {
            realUrlEncoded = queryItem.value;
            break;
        }
    }
    if(!realUrlEncoded) {
        realUrlEncoded = lcUrl.queryItems.firstObject.value;
    }
    if(!realUrlEncoded) {
        return nil;
    }
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
    if(!decodedData) {
        return nil;
    }
    return [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
}

static void resolveLaunchExtensionFileBookmark(void) {
    NSData* bookmarkData = [NSUserDefaults.lcSharedDefaults dataForKey:@"LCLaunchExtensionFileBookmark"];
    if(!bookmarkData) {
        return;
    }
    BOOL isStale = NO;
    NSError* error = nil;
    NSURL* resolvedURL = [NSURL URLByResolvingBookmarkData:bookmarkData
                                                   options:(1UL << 10)
                                             relativeToURL:nil
                                       bookmarkDataIsStale:&isStale
                                                     error:&error];
    if(!resolvedURL) {
        NSLog(@"[LC] Failed to resolve shared file bookmark: %@", error.localizedDescription);
    }
    [NSUserDefaults.lcSharedDefaults removeObjectForKey:@"LCLaunchExtensionFileBookmark"];
    
}

static LCControlAppURLHandling LCHandleControlAppURL(NSURL *url, NSString** modifiedURLStr) {
    if(!url || url.isFileURL) {
        return LCControlAppURLHandlingPassThrough;
    }

    // pass through sidestore urls
    if(NSUserDefaults.isSideStore && ![url.scheme isEqualToString:@"livecontainer"]) {
        return LCControlAppURLHandlingPassThrough;
    }

    if([url.scheme isEqualToString:@"sidestore"]) {
        LCOpenSideStoreURL(url);
        return LCControlAppURLHandlingStop;
    }

    NSString *lcScheme = NSUserDefaults.lcAppUrlScheme;
    // pass through any url that should not be handled by current lc
    if(![url.scheme isEqualToString:lcScheme]) {
        return LCControlAppURLHandlingPassThrough;
    }
    NSString* urlHost = url.host;
    
    if([urlHost isEqualToString:@"livecontainer-relaunch"]) {
        return LCControlAppURLHandlingStop;
    }
    
    if([urlHost isEqualToString:@"livecontainer-launch"]) {
        // If it's not current app, then switch, otherwise check if we need to open the url
        NSString* bundleName = nil;
        NSString* openUrl = nil;
        NSString* containerFolderName = nil;
        NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem* queryItem in components.queryItems) {
            if ([queryItem.name isEqualToString:@"bundle-name"]) {
                bundleName = queryItem.value;
            } else if ([queryItem.name isEqualToString:@"open-url"]) {
                NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:queryItem.value options:0];
                openUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
            } else if ([queryItem.name isEqualToString:@"container-folder-name"]) {
                containerFolderName = queryItem.value;
            }
        }
        
        // launch to LiveContainerUI
        if([bundleName isEqualToString:@"ui"]) {
            LCShowSwitchAppConfirmation(url, @"LiveContainer", false);
            return LCControlAppURLHandlingStop;
        }
        
        NSString* containerId = [NSString stringWithUTF8String:getenv("HOME")].lastPathComponent;
        if(!containerFolderName) {
            containerFolderName = findDefaultContainerWithBundleId(bundleName);
        }
        // current bundlename and container folder name matches OR sidestore is running and we are launching builtinSideStore
        if (([bundleName isEqualToString:NSBundle.mainBundle.bundlePath.lastPathComponent] && [containerId isEqualToString:containerFolderName]) ||
            (NSUserDefaults.isSideStore && [bundleName isEqualToString:@"builtinSideStore"])) {
            if(openUrl) {
                if([openUrl hasPrefix:@"file:"]) {
                    resolveLaunchExtensionFileBookmark();
                    *modifiedURLStr = openUrl;
                    return LCControlAppURLHandlingReplaceURL;
                } else {
                    openUniversalLink(openUrl);
                }
            }
        } else {
            if([bundleName isEqualToString:@"builtinSideStore"]) {
                LCShowSwitchAppConfirmation(url, @"SideStore", NO);
                return LCControlAppURLHandlingStop;
            }
            handleLiveContainerLaunch(bundleName, containerFolderName, url);
        }
        
        return LCControlAppURLHandlingStop;
    }

    if([urlHost isEqualToString:@"open-web-page"]) {
        NSString *decodedUrl = LCDecodedURLStringFromControlURL(url);
        if(decodedUrl) {
            LCOpenWebPage(decodedUrl, url.absoluteString);
        }
        return LCControlAppURLHandlingStop;
    }

    if([urlHost isEqualToString:@"open-url"]) {
        NSString *decodedUrl = LCDecodedURLStringFromControlURL(url);
        if(!decodedUrl) {
            return LCControlAppURLHandlingStop;
        }
        // it's a Universal link, let's call -[UIActivityContinuationManager handleActivityContinuation:isSuspended:]
        if([decodedUrl hasPrefix:@"https"]) {
            openUniversalLink(decodedUrl);
            return LCControlAppURLHandlingStop;
        }
        *modifiedURLStr = decodedUrl;
        return LCControlAppURLHandlingReplaceURL;
    }

    if([urlHost isEqualToString:@"install"]) {
        LCShowAlert(@"lc.guestTweak.restartToInstall".loc);
        return LCControlAppURLHandlingStop;
    }

    return LCControlAppURLHandlingStop;
}

// Handler for AppDelegate
@implementation UIApplication(LiveContainerHook)
- (void)hook__applicationOpenURLAction:(id)action payload:(NSDictionary *)payload origin:(id)origin {
    NSURL *url = [NSURL URLWithString:payload[UIApplicationLaunchOptionsURLKey]];
    NSString* replacementURLString = nil;
    LCControlAppURLHandling decision = LCHandleControlAppURL(url, &replacementURLString);
    if(decision == LCControlAppURLHandlingStop) {
        return;
    }
    if(decision == LCControlAppURLHandlingReplaceURL) {
        NSMutableDictionary* newPayload = [payload mutableCopy];
        newPayload[UIApplicationLaunchOptionsURLKey] = replacementURLString;
        [self hook__applicationOpenURLAction:action payload:newPayload origin:origin];
        return;
    }
    [self hook__applicationOpenURLAction:action payload:payload origin:origin];
}

- (void)hook__connectUISceneFromFBSScene:(id)scene transitionContext:(UIApplicationSceneTransitionContext*)context {
#if !TARGET_OS_MACCATALYST
    NSString* decodedUrlStr = launchURLProcessed ? nil : NSUserDefaults.lcLaunchURL;
    launchURLProcessed = YES;
    NSString* urlStr;
        
    if(!decodedUrlStr && context.payload && (urlStr = context.payload[UIApplicationLaunchOptionsURLKey])) {
        do {
            if([urlStr hasPrefix:[NSString stringWithFormat: @"%@://open-url", NSUserDefaults.lcAppUrlScheme]]) {
                NSURLComponents* lcUrl = [NSURLComponents componentsWithString:urlStr];
                NSString* realUrlEncoded = lcUrl.queryItems[0].value;
                if(!realUrlEncoded) break;
                // Convert the base64 encoded url into String
                NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
                decodedUrlStr = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
            } else if([urlStr hasPrefix:NSUserDefaults.lcAppUrlScheme]) {
                context.payload = nil;
                context.actions = nil;
            }
        } while (0);
    }
    
    do {
        if(!decodedUrlStr) break;
        NSURL* decodedUrl = [NSURL URLWithString:decodedUrlStr];
        if(decodedUrl.isFileURL) {
            resolveLaunchExtensionFileBookmark();
        }
        
        NSMutableDictionary* newDict = [context.payload mutableCopy];
        if(!newDict) newDict = [NSMutableDictionary new];
        newDict[UIApplicationLaunchOptionsURLKey] = decodedUrlStr;
        context.payload = newDict;
        
        
        UIOpenURLAction *urlAction = nil;
        for (id obj in context.actions.allObjects) {
            if ([obj isKindOfClass:UIOpenURLAction.class]) {
                urlAction = obj;
                break;
            }
        }
        
        NSMutableSet *newActions = context.actions.mutableCopy;
        if(newActions && urlAction) {
            [newActions removeObject:urlAction];
        }
        if(!newActions) newActions = [NSMutableSet new];
        
        UIOpenURLAction *newUrlAction = [[UIOpenURLAction alloc] initWithURL:decodedUrl];
        [newActions addObject:newUrlAction];
        context.actions = newActions;
        
    } while(0);
    
#endif
    [self hook__connectUISceneFromFBSScene:scene transitionContext:context];
}

-(BOOL)hook__handleDelegateCallbacksWithOptions:(id)arg1 isSuspended:(BOOL)arg2 restoreState:(BOOL)arg3 {
    BOOL ans = [self hook__handleDelegateCallbacksWithOptions:arg1 isSuspended:arg2 restoreState:arg3];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            LSApplicationWorkspace* workspace = [objc_lookUpClass("LSApplicationWorkspace") defaultWorkspace];
            [workspace openApplicationWithBundleID:@"com.apple.springboard"];
            [workspace openApplicationWithBundleID:NSUserDefaults.lcMainBundle.bundleIdentifier];
        });

    });


    return ans;
}

- (void)hook_openURL:(NSURL *)url options:(NSDictionary<NSString *,id> *)options completionHandler:(void (^)(_Bool))completion {
    if(NSUserDefaults.isSideStore && ![url.scheme isEqualToString:@"livecontainer"]) {
        [self hook_openURL:url options:options completionHandler:completion];
        return;
    }
    
    BOOL openSelf = canAppOpenItself(url);
    BOOL redirectToHost = shouldRedirectOpenURLToHost(url);;
    if(openSelf || redirectToHost) {
        NSString* schemeToUse = openSelf ? NSUserDefaults.lcAppUrlScheme : @"livecontainer";
        NSData *data = [url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
        NSString* finalUrlStr = [NSString stringWithFormat:@"%@://open-url?url=%@", schemeToUse, encodedUrl];
        NSURL* finalUrl = [NSURL URLWithString:finalUrlStr];
        [self hook_openURL:finalUrl options:options completionHandler:completion];
    } else {
        [self hook_openURL:url options:options completionHandler:completion];
    }
}
- (BOOL)hook_canOpenURL:(NSURL *) url {
    return canAppOpenItself(url) || shouldRedirectOpenURLToHost(url) || [self hook_canOpenURL:url];
}

- (void)hook_setDelegate:(id<UIApplicationDelegate>)delegate {
    if(![delegate respondsToSelector:@selector(application:configurationForConnectingSceneSession:options:)]) {
        // Fix old apps black screen when UIApplicationSupportsMultipleScenes is YES
        swizzle(UIWindow.class, @selector(makeKeyAndVisible), @selector(hook_makeKeyAndVisible));
        swizzle(UIWindow.class, @selector(makeKeyWindow), @selector(hook_makeKeyWindow));
        swizzle(UIWindow.class, @selector(setHidden:), @selector(hook_setHidden:));
        // Fix apps that do not support UISceneDelegate getting 0 status bar frame
        swizzle(UIApplication.class, @selector(statusBarFrame), @selector(hook_statusBarFrame));
    }
    [self hook_setDelegate:delegate];
}

+ (BOOL)_wantsApplicationBehaviorAsExtension {
    // Fix LiveProcess: Make _UIApplicationWantsExtensionBehavior return NO so delegate code runs in the run loop
    return YES;
}

- (CGRect)hook_statusBarFrame {
    UIStatusBarManager* manager = [(UIWindowScene*)(UIApplication.sharedApplication.connectedScenes.anyObject) statusBarManager];
    if(manager) {
        return manager.statusBarFrame;
    } else {
        return [self hook_statusBarFrame];
    }
}

@end

// Handler for SceneDelegate
@implementation UIScene(LiveContainerHook)
- (void)hook_scene:(id)scene didReceiveActions:(NSSet *)actions fromTransitionContext:(id)context {
    UIOpenURLAction *urlAction = nil;
    for (id obj in actions.allObjects) {
        if ([obj isKindOfClass:UIOpenURLAction.class]) {
            urlAction = obj;
            break;
        }
    }

    if(!urlAction) {
        [self hook_scene:scene didReceiveActions:actions fromTransitionContext:context];
        return;
    }
    NSString* replacementURLString = nil;
    LCControlAppURLHandling decision = LCHandleControlAppURL(urlAction.url, &replacementURLString);
    if(decision == LCControlAppURLHandlingStop) {
        return;
    }
    if(decision == LCControlAppURLHandlingReplaceURL) {
        NSURL* finalURL = [NSURL URLWithString:replacementURLString];
        if(!finalURL) {
            return;
        }
        NSMutableSet *newActions = actions.mutableCopy;
        [newActions removeObject:urlAction];
        UIOpenURLAction *newUrlAction = [[UIOpenURLAction alloc] initWithURL:finalURL];
        [newActions addObject:newUrlAction];
        [self hook_scene:scene didReceiveActions:newActions fromTransitionContext:context];
        return;
    }
    [self hook_scene:scene didReceiveActions:actions fromTransitionContext:context];
}

- (void)hook_openURL:(NSURL *)url options:(UISceneOpenExternalURLOptions *)options completionHandler:(void (^)(BOOL success))completion {
    BOOL openSelf = canAppOpenItself(url);
    BOOL redirectToHost = shouldRedirectOpenURLToHost(url);
    if(openSelf || redirectToHost) {
        NSString* schemeToUse = openSelf ? NSUserDefaults.lcAppUrlScheme : @"livecontainer";
        NSData *data = [url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
        NSString* finalUrlStr = [NSString stringWithFormat:@"%@://open-url?url=%@", schemeToUse, encodedUrl];
        NSURL* finalUrl = [NSURL URLWithString:finalUrlStr];
        [self hook_openURL:finalUrl options:options completionHandler:completion];
    } else {
        [self hook_openURL:url options:options completionHandler:completion];
    }
}
@end

@implementation FBSSceneParameters(LiveContainerHook)
- (instancetype)hook_initWithXPCDictionary:(NSDictionary*)dict {

    FBSSceneParameters* ans = [self hook_initWithXPCDictionary:dict];
    UIMutableApplicationSceneSettings* settings = [ans.settings mutableCopy];
    UIMutableApplicationSceneClientSettings* clientSettings = [ans.clientSettings mutableCopy];
    [settings setInterfaceOrientation:LCOrientationLock];
    [clientSettings setInterfaceOrientation:LCOrientationLock];
    ans.settings = settings;
    ans.clientSettings = clientSettings;
    return ans;
}
@end



@implementation UIViewController(LiveContainerHook)

- (UIInterfaceOrientationMask)hook___supportedInterfaceOrientations {
    if(LCOrientationLock == UIInterfaceOrientationLandscapeRight) {
        return UIInterfaceOrientationMaskLandscape;
    } else {
        return UIInterfaceOrientationMaskPortrait;
    }

}

- (BOOL)hook_shouldAutorotateToInterfaceOrientation:(NSInteger)orientation {
    return YES;
}

@end

@implementation UIWindow(hook)
- (void)hook_setAutorotates:(BOOL)autorotates forceUpdateInterfaceOrientation:(BOOL)force {
    [self hook_setAutorotates:YES forceUpdateInterfaceOrientation:YES];
}

- (void)hook_makeKeyAndVisible {
    [self updateWindowScene];
    [self hook_makeKeyAndVisible];
}
- (void)hook_makeKeyWindow {
    [self updateWindowScene];
    [self hook_makeKeyWindow];
}
- (void)hook_resignKeyWindow {
    [self updateWindowScene];
    [self hook_resignKeyWindow];
}
- (void)hook_setHidden:(BOOL)hidden {
    [self updateWindowScene];
    [self hook_setHidden:hidden];
}
- (void)updateWindowScene {
    for(UIWindowScene *windowScene in UIApplication.sharedApplication.connectedScenes) {
        if(!self.windowScene && self.screen == windowScene.screen) {
            self.windowScene = windowScene;
            break;
        }
    }
}
@end
