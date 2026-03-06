#import "CoreLocation+GuestHooks.h"
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import "../utils.h"

static BOOL spoofGPSEnabled = NO;
static CLLocationCoordinate2D spoofedCoordinate = {37.7749, -122.4194};
static CLLocationDistance spoofedAltitude = 0.0;

static id LCValidValueOrNil(id value) {
    if (value == nil || [value isKindOfClass:NSNull.class]) {
        return nil;
    }
    return value;
}

static double LCDoubleValueOrFallback(id value, double fallback) {
    if (value && [value respondsToSelector:@selector(doubleValue)]) {
        return [value doubleValue];
    }
    return fallback;
}

static NSString *LCActiveContainerFolderName(void) {
    const char *homePath = getenv("HOME");
    if (!homePath) {
        return nil;
    }
    NSString *home = [NSString stringWithUTF8String:homePath];
    if (home.length == 0) {
        return nil;
    }
    return home.lastPathComponent;
}

static NSString *LCContainerFolderNameFromGuestAppInfo(NSDictionary *guestAppInfo) {
    id containerIdObj = guestAppInfo[@"LCDataUUID"];
    if ([containerIdObj isKindOfClass:NSString.class]) {
        NSString *containerId = (NSString *)containerIdObj;
        if (containerId.length > 0) {
            return containerId;
        }
    }
    return LCActiveContainerFolderName();
}

static NSDictionary *LCContainerScopedLocationSettingsFromAppInfoFile(NSDictionary *guestAppInfo) {
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    if (bundlePath.length == 0) {
        return nil;
    }
    NSString *appInfoPath = [bundlePath stringByAppendingPathComponent:@"LCAppInfo.plist"];
    NSDictionary *appInfo = [NSDictionary dictionaryWithContentsOfFile:appInfoPath];
    if (![appInfo isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSString *containerFolder = LCContainerFolderNameFromGuestAppInfo(guestAppInfo);
    if (containerFolder.length == 0) {
        return nil;
    }

    NSDictionary *settingsByContainer = appInfo[@"LCAddonSettingsByContainer"];
    if (![settingsByContainer isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSDictionary *containerSettings = settingsByContainer[containerFolder];
    return [containerSettings isKindOfClass:NSDictionary.class] ? containerSettings : nil;
}

@interface CLLocationManager (GuestHooks)
- (void)lc_startUpdatingLocation;
- (void)lc_requestLocation;
- (CLLocation *)lc_location;
@end

@implementation CLLocationManager (GuestHooks)

- (void)lc_startUpdatingLocation {
    if (spoofGPSEnabled && self.delegate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CLLocation *spoofedLocation = [[CLLocation alloc] 
                initWithCoordinate:spoofedCoordinate
                altitude:spoofedAltitude
                horizontalAccuracy:5.0
                verticalAccuracy:5.0
                timestamp:[NSDate date]];
            
            if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                [self.delegate locationManager:self didUpdateLocations:@[spoofedLocation]];
            }
        });
        return;
    }
    
    [self lc_startUpdatingLocation];
}

- (void)lc_requestLocation {
    if (spoofGPSEnabled && self.delegate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CLLocation *spoofedLocation = [[CLLocation alloc] 
                initWithCoordinate:spoofedCoordinate
                altitude:spoofedAltitude
                horizontalAccuracy:5.0
                verticalAccuracy:5.0
                timestamp:[NSDate date]];
            
            if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                [self.delegate locationManager:self didUpdateLocations:@[spoofedLocation]];
            }
        });
        return;
    }
    
    [self lc_requestLocation];
}

- (CLLocation *)lc_location {
    if (spoofGPSEnabled) {
        return [[CLLocation alloc] 
            initWithCoordinate:spoofedCoordinate
            altitude:spoofedAltitude
            horizontalAccuracy:5.0
            verticalAccuracy:5.0
            timestamp:[NSDate date]];
    }
    
    return [self lc_location];
}

@end

void CoreLocationGuestHooksInit(void) {
    @try {
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        NSDictionary *containerScopedSettings = LCContainerScopedLocationSettingsFromAppInfoFile(guestAppInfo);
        
        NSLog(@"[LC] CoreLocationGuestHooksInit: guestAppInfo = %@", guestAppInfo);
        if (containerScopedSettings) {
            NSLog(@"[LC] CoreLocationGuestHooksInit: containerScopedSettings = %@", containerScopedSettings);
        }
        
        if (guestAppInfo) {
            id spoofGPSValue = LCValidValueOrNil(guestAppInfo[@"spoofGPS"]);
            NSString *spoofGPSSource = @"guestAppInfo";
            if (![spoofGPSValue respondsToSelector:@selector(boolValue)]) {
                spoofGPSValue = LCValidValueOrNil(containerScopedSettings[@"spoofGPS"]);
                spoofGPSSource = @"containerScopedSettings";
            }
            spoofGPSEnabled = [spoofGPSValue boolValue];

            NSLog(@"[LC] spoofGPS from guestAppInfo: %@", guestAppInfo[@"spoofGPS"]);
            if (containerScopedSettings) {
                NSLog(@"[LC] spoofGPS from containerScopedSettings: %@", containerScopedSettings[@"spoofGPS"]);
            }
            NSLog(@"[LC] spoofGPSEnabled: %d (source=%@)", spoofGPSEnabled, spoofGPSSource);
            
            if (spoofGPSEnabled) {
                id latValue = LCValidValueOrNil(guestAppInfo[@"spoofLatitude"]);
                id lonValue = LCValidValueOrNil(guestAppInfo[@"spoofLongitude"]);
                id altValue = LCValidValueOrNil(guestAppInfo[@"spoofAltitude"]);
                NSString *latSource = @"guestAppInfo";
                NSString *lonSource = @"guestAppInfo";
                NSString *altSource = @"guestAppInfo";

                if (![latValue respondsToSelector:@selector(doubleValue)]) {
                    latValue = LCValidValueOrNil(containerScopedSettings[@"spoofLatitude"]);
                    latSource = @"containerScopedSettings";
                }
                if (![lonValue respondsToSelector:@selector(doubleValue)]) {
                    lonValue = LCValidValueOrNil(containerScopedSettings[@"spoofLongitude"]);
                    lonSource = @"containerScopedSettings";
                }
                if (![altValue respondsToSelector:@selector(doubleValue)]) {
                    altValue = LCValidValueOrNil(containerScopedSettings[@"spoofAltitude"]);
                    altSource = @"containerScopedSettings";
                }

                spoofedCoordinate.latitude = LCDoubleValueOrFallback(latValue, 37.7749);
                spoofedCoordinate.longitude = LCDoubleValueOrFallback(lonValue, -122.4194);
                spoofedAltitude = LCDoubleValueOrFallback(altValue, 0.0);
                
                NSLog(@"[LC] GPS coordinates from guestAppInfo:");
                NSLog(@"[LC] - spoofLatitude: %@ (%@) -> %f (source=%@)", latValue, [latValue class], spoofedCoordinate.latitude, latSource);
                NSLog(@"[LC] - spoofLongitude: %@ (%@) -> %f (source=%@)", lonValue, [lonValue class], spoofedCoordinate.longitude, lonSource);
                NSLog(@"[LC] - spoofAltitude: %@ (%@) -> %f (source=%@)", altValue, [altValue class], spoofedAltitude, altSource);
                
                NSLog(@"[LC] Final GPS spoofing coordinates: %f, %f, %f", 
                      spoofedCoordinate.latitude, 
                      spoofedCoordinate.longitude, 
                      spoofedAltitude);
                
                // Only hook if CoreLocation is available and GPS spoofing is enabled
                Class clLocationManagerClass = NSClassFromString(@"CLLocationManager");
                if (clLocationManagerClass) {
                    NSLog(@"[LC] Hooking CLLocationManager methods");
                    // Hook CLLocationManager methods
                    swizzle(clLocationManagerClass, 
                            @selector(startUpdatingLocation), 
                            @selector(lc_startUpdatingLocation));
                    
                    swizzle(clLocationManagerClass, 
                            @selector(requestLocation), 
                            @selector(lc_requestLocation));
                    
                    swizzle(clLocationManagerClass, 
                            @selector(location), 
                            @selector(lc_location));
                } else {
                    NSLog(@"[LC] Warning: CLLocationManager class not found");
                }
            }
        } else {
            NSLog(@"[LC] No guestAppInfo available for GPS spoofing");
        }
    } @catch (NSException *exception) {
        NSLog(@"[LC] Error initializing GPS hooks: %@", exception);
    }
}
