#import "Network+GuestHooks.h"

void NetworkGuestHooksInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[LC] Network proxy hooks are retired and disabled.");
    });
}
