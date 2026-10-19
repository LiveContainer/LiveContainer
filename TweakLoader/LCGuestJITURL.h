#import <Foundation/Foundation.h>

/// A guest runs in the host's process; debug that process rather than its unregistered bundle ID.
static inline NSURL *LCGuestJITURL(NSURL *url, NSString *guestID, NSString *hostID, int pid) {
    if (![url.scheme.lowercaseString isEqualToString:@"stikjit"] ||
        ![url.host.lowercaseString isEqualToString:@"enable-jit"] || !guestID.length || !hostID.length || pid <= 0) return url;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *target = nil, *requestedPID = nil;
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"bundle-id"]) target = item.value;
        if ([item.name isEqualToString:@"pid"]) requestedPID = item.value;
    }
    if (![target isEqualToString:guestID] || (requestedPID && requestedPID.intValue != pid)) return url;
    NSMutableArray *items = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems) {
        if (![item.name isEqualToString:@"bundle-id"] && ![item.name isEqualToString:@"pid"]) [items addObject:item];
    }
    [items addObject:[NSURLQueryItem queryItemWithName:@"bundle-id" value:hostID]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"pid" value:[NSString stringWithFormat:@"%d", pid]]];
    components.queryItems = items;
    components.percentEncodedQuery = [components.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
    return components.URL ?: url;
}
