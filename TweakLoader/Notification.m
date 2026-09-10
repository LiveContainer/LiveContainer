//
//  Notification.m
//  LiveContainer
//
//  Created by s s on 2025/7/21.
//

#import "UserNotifications/UserNotifications.h"
#import "../LiveContainer/utils.h"
@interface UNUserNotificationCenter(private)
@property (nonatomic, copy) NSString *bundleIdentifier;
@end

__attribute__((constructor))
static void UNHooksInit(void) {
    if(!NSUserDefaults.lcGuestAppId) return;
    if([NSUserDefaults.guestAppInfo[@"fixLocalNotification"] boolValue] || NSUserDefaults.isSideStore) {
        [UNUserNotificationCenter.currentNotificationCenter setBundleIdentifier:[NSUserDefaults.lcMainBundle bundleIdentifier]];
    }
}
