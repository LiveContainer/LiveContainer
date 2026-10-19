#import <Foundation/Foundation.h>

static inline NSDictionary<NSString *, NSString *> *LCGuestEnvironment(NSDictionary<NSString *, NSString *> *environment, BOOL conceal) {
    if (!conceal) return environment;
    NSMutableDictionary *filtered = environment.mutableCopy;
    for (NSString *key in environment) {
        if ([key hasPrefix:@"LC_"] || [key hasPrefix:@"LP_"] || [key isEqualToString:@"DYLD_INSERT_LIBRARIES"]) {
            [filtered removeObjectForKey:key];
        }
    }
    return filtered;
}
