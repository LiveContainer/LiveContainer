//
//  LCAppInfo+Multitask.m
//  LiveContainer
//
//  Created by Duy Tran on 27/7/26.
//
#import "../LiveContainerSwiftUI/Models/LCAppInfo.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "UIKitPrivate+MultitaskSupport.h"

API_AVAILABLE(ios(16.0))
@implementation LCAppInfo(Multitask)

- (BOOL)multitaskMaximized {
    if(!_info[@"multitaskMaximized"]) {
        return [NSUserDefaults.lcUserDefaults boolForKey:@"LCLaunchMultitaskMaximized"];
    } else {
        return [_info[@"multitaskMaximized"] boolValue];
    }
}

- (void)setMultitaskMaximized:(BOOL)value {
    _info[@"multitaskMaximized"] = @(value);
    [self save];
}

- (CGRect)multitaskFrame {
    if(!_info[@"multitaskFrame"]) {
        return CGRectNull;
    } else {
        return CGRectFromString(_info[@"multitaskFrame"]);
    }
}

- (void)setMultitaskFrame:(CGRect)value {
    _info[@"multitaskFrame"] = NSStringFromCGRect(value);
    [self save];
}

- (CGFloat)windowScale {
    return [_info[@"windowScale"] ?: @(1.0) doubleValue];
}

- (void)setWindowScale:(CGFloat)value {
    _info[@"windowScale"] = @(value);
    [self save];
}

@end
