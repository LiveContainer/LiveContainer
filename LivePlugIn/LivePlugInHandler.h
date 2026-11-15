#pragma once

#import <Foundation/Foundation.h>

@interface LivePlugInHandler : NSObject
+ (void)reportLivePlugInError:(NSString *)error;
@end
