//
//  DeviceSpoofing.h
//  LiveContainer
//
//  Device spoofing to prevent fingerprinting
//  Extended for iOS 18.x and 26.x support
//

#ifndef DeviceSpoofing_h
#define DeviceSpoofing_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <stdint.h>

// Device profile structure - extended with more fields
typedef struct {
    const char *modelIdentifier;    // e.g., "iPhone17,1"
    const char *hardwareModel;      // e.g., "D93AP"
    const char *marketingName;      // e.g., "iPhone 16 Pro Max"
    const char *systemVersion;      // e.g., "18.1"
    const char *buildVersion;       // e.g., "22B83"
    const char *kernelVersion;      // e.g., "Darwin Kernel Version 24.1.0..."
    const char *kernelRelease;      // e.g., "24.1.0"
    uint64_t physicalMemory;        // In bytes
    uint32_t cpuCoreCount;          // Number of CPU cores
    uint32_t performanceCores;      // Performance cores
    uint32_t efficiencyCores;       // Efficiency cores
    CGFloat screenScale;            // Screen scale (3.0 for Retina)
    CGFloat screenWidth;            // Native screen width
    CGFloat screenHeight;           // Native screen height
    const char *chipName;           // e.g., "A18 Pro"
    const char *gpuName;            // e.g., "Apple GPU"
} LCDeviceProfile;

// Available device profiles - iOS 26.x / 18.x / 17.x compatible
// iOS 26.x - iPhone 17 Series
extern const LCDeviceProfile kDeviceProfileiPhone17ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone17Pro;
extern const LCDeviceProfile kDeviceProfileiPhone17;
extern const LCDeviceProfile kDeviceProfileiPhone17Air;
// iOS 18.x - iPhone 16 Series
extern const LCDeviceProfile kDeviceProfileiPhone16ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone16Pro;
extern const LCDeviceProfile kDeviceProfileiPhone16;
extern const LCDeviceProfile kDeviceProfileiPhone16e;
// iOS 17.x - iPhone 15/14/13 Series
extern const LCDeviceProfile kDeviceProfileiPhone15ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone15Pro;
extern const LCDeviceProfile kDeviceProfileiPhone14ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone14Pro;
extern const LCDeviceProfile kDeviceProfileiPhone13ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone13Pro;

// Initialize device spoofing hooks
void DeviceSpoofingGuestHooksInit(void);
void LCDeviceSpoofingBeginConfiguration(void);
void LCDeviceSpoofingEndConfiguration(void);

// Configuration functions
void LCSetDeviceSpoofingEnabled(BOOL enabled);
BOOL LCIsDeviceSpoofingEnabled(void);

void LCSetDeviceProfile(NSString *profileName);
NSString *LCGetCurrentDeviceProfile(void);
NSDictionary *LCGetCurrentProfileData(void);

// Get available profiles
NSDictionary<NSString *, NSDictionary *> *LCGetAvailableDeviceProfiles(void);

// Custom spoofing values
void LCSetSpoofedDeviceModel(NSString *model);
void LCSetSpoofedSystemVersion(NSString *version);
void LCSetSpoofedBuildVersion(NSString *build);
void LCSetSpoofedKernelVersion(NSString *kernelVersion);
void LCSetSpoofedKernelRelease(NSString *kernelRelease);
void LCSetSpoofedCPUCount(uint32_t cpuCount);
void LCSetSpoofedPhysicalMemory(uint64_t memory);
void LCSetSpoofedVendorID(NSString *vendorID);
void LCSetSpoofedAdvertisingID(NSString *advertisingID);
void LCSetSpoofedPersistentDeviceID(NSString *persistentDeviceID);
void LCSetSpoofedLocaleCurrencyCode(NSString *currencyCode);      // e.g., "USD"
void LCSetSpoofedLocaleCurrencySymbol(NSString *currencySymbol);  // e.g., "$"
void LCSetProximitySpoofingEnabled(BOOL enabled);
void LCSetOrientationSpoofingEnabled(BOOL enabled);
void LCSetGyroscopeSpoofingEnabled(BOOL enabled);

// Fingerprint spoofing - Battery
void LCSetSpoofedBatteryLevel(float level);        // 0.0-1.0
void LCSetSpoofedBatteryState(NSInteger state);    // 0=Unknown, 1=Unplugged, 2=Charging, 3=Full
void LCRandomizeBattery(void);

// Fingerprint spoofing - Screen/Brightness
void LCSetSpoofedBrightness(float brightness);     // 0.0-1.0
void LCRandomizeBrightness(void);

// Fingerprint spoofing - Uptime/Boot Time (critical fingerprinting vectors!)
void LCSetSpoofedBootTimeRange(NSString *range); // "short","medium","long","week" or exact presets like "1h","12h","1d"
void LCSetSpoofedUptimeSeconds(NSTimeInterval uptimeSeconds); // Set exact spoofed uptime target in seconds
void LCSetUptimeOffset(NSTimeInterval offset);     // Offset in seconds to add to uptime
void LCRandomizeUptime(void);                      // Randomize uptime to 1-7 days
void LCSetSpoofedBootTime(time_t bootTimestamp);   // Set specific boot time (Unix timestamp)
time_t LCGetSpoofedBootTime(void);                 // Get current spoofed boot time
NSTimeInterval LCGetSpoofedUptime(void);           // Get current spoofed uptime

// Fingerprint spoofing - Thermal/Power state
void LCSetSpoofedThermalState(NSInteger state);    // 0=Nominal, 1=Fair, 2=Serious, 3=Critical
void LCSetSpoofedLowPowerMode(BOOL enabled, BOOL value);

// Storage spoofing - based on Project-X StorageManager approach
void LCSetStorageSpoofingEnabled(BOOL enabled);
BOOL LCIsStorageSpoofingEnabled(void);
void LCSetStorageRandomFreeEnabled(BOOL enabled);          // Randomize free space based on selected capacity
BOOL LCIsStorageRandomFreeEnabled(void);
void LCSetSpoofedStorageCapacity(long long capacityGB);  // e.g., 128 for 128GB
void LCSetSpoofedStorageFree(NSString *freeGB);          // e.g., "45.2" for 45.2GB free
void LCSetSpoofedStorageBytes(uint64_t totalBytes, uint64_t freeBytes);
NSDictionary *LCGenerateStorageForCapacity(NSString *capacityGB);  // Generate realistic storage values
NSString *LCRandomizeStorageCapacity(void);              // Get random capacity (64/128/256/512/1024)
void LCRandomizeStorage(void);                           // Randomize storage with realistic values
uint64_t LCGetSpoofedStorageTotal(void);
uint64_t LCGetSpoofedStorageFree(void);
NSString *LCGetSpoofedStorageCapacityGB(void);
NSString *LCGetSpoofedStorageFreeGB(void);

// Legacy disk space function (kept for compatibility)
void LCSetSpoofedDiskSpace(uint64_t freeSpace, uint64_t totalSpace);

// Canvas/WebGL/Audio Fingerprint Protection
// Injects JavaScript into WKWebView to protect against browser fingerprinting
void LCSetCanvasFingerprintProtectionEnabled(BOOL enabled);
BOOL LCIsCanvasFingerprintProtectionEnabled(void);

// iCloud/CloudKit Privacy Protection
// Blocks iCloud account fingerprinting and CloudKit access
void LCSetICloudPrivacyProtectionEnabled(BOOL enabled);
BOOL LCIsICloudPrivacyProtectionEnabled(void);

// Siri Privacy Protection  
// Blocks Siri authorization and vocabulary access
void LCSetSiriPrivacyProtectionEnabled(BOOL enabled);
BOOL LCIsSiriPrivacyProtectionEnabled(void);

// Device name and carrier spoofing
void LCSetSpoofedDeviceName(NSString *deviceName);  // e.g., "John's iPhone"
NSString *LCGetSpoofedDeviceName(void);
void LCSetSpoofedCarrierName(NSString *carrierName);  // e.g., "Verizon"
NSString *LCGetSpoofedCarrierName(void);
void LCSetSpoofedCarrierMCC(NSString *mcc);           // e.g., "311"
void LCSetSpoofedCarrierMNC(NSString *mnc);           // e.g., "480"
void LCSetSpoofedCarrierCountryCode(NSString *code);  // e.g., "us"
void LCSetSpoofedCellularType(NSInteger type);        // 0=NRNSA, 1=LTE, 2=WCDMA
void LCSetNetworkInfoSpoofingEnabled(BOOL enabled);
void LCSetWiFiAddressSpoofingEnabled(BOOL enabled);
void LCSetCellularAddressSpoofingEnabled(BOOL enabled);
void LCSetSpoofedWiFiAddress(NSString *wifiAddress);      // e.g., "192.168.1.15"
void LCSetSpoofedCellularAddress(NSString *cellularAddress); // e.g., "10.123.45.67"
void LCSetSpoofedWiFiSSID(NSString *ssid);                // e.g., "Public Network"
void LCSetSpoofedWiFiBSSID(NSString *bssid);              // e.g., "22:66:99:00:11:22"

// Identifier spoofing - IDFV/IDFA
void LCSetSpoofedVendorID(NSString *vendorID);    // Identifier for Vendor (IDFV)
NSString *LCGetSpoofedVendorID(void);
void LCSetSpoofedAdvertisingID(NSString *advertisingID);  // Identifier for Advertising (IDFA)
NSString *LCGetSpoofedAdvertisingID(void);
void LCSetSpoofedAdTrackingEnabled(BOOL enabled);  // Ad tracking limit
BOOL LCGetSpoofedAdTrackingEnabled(void);
void LCSetSpoofedInstallationID(NSString *installationID);  // App installation ID
NSString *LCGetSpoofedInstallationID(void);
void LCSetSpoofedMACAddress(NSString *macAddress);  // MAC address (02:00:00:xx:xx:xx format)
NSString *LCGetSpoofedMACAddress(void);

// Battery spoofing
void LCSetSpoofedBatteryLevel(float level);  // 0.0 to 1.0
float LCGetSpoofedBatteryLevel(void);
void LCSetSpoofedBatteryState(NSInteger state);  // UIDeviceBatteryState values
NSInteger LCGetSpoofedBatteryState(void);

// Screen/brightness spoofing
void LCSetSpoofedScreenScale(CGFloat scale);  // Not implemented - use device profile
void LCSetSpoofedBrightness(float brightness);  // 0.0 to 1.0
float LCGetSpoofedBrightness(void);

// Initialize all fingerprint protection with random values
void LCInitializeFingerprintProtection(void);

// User-Agent spoofing
void LCSetSpoofedUserAgent(NSString *userAgent);   // Set custom User-Agent (nil to use auto-generated)
void LCSetUserAgentSpoofingEnabled(BOOL enabled);  // Enable/disable User-Agent spoofing
BOOL LCIsUserAgentSpoofingEnabled(void);           // Check if User-Agent spoofing is enabled
NSString *LCGetCurrentUserAgent(void);             // Get current spoofed User-Agent string
void LCUpdateUserAgentForProfile(void);            // Auto-update User-Agent based on device profile

// Timezone spoofing
void LCSetSpoofedTimezone(NSString *timezone);       // e.g., "America/New_York"
NSString *LCGetSpoofedTimezone(void);

// Locale spoofing
void LCSetSpoofedLocale(NSString *locale);           // e.g., "en_US"
NSString *LCGetSpoofedLocale(void);
void LCSetSpoofedPreferredCountryCode(NSString *countryCode); // e.g., "US"

// Screen capture detection blocking
void LCSetScreenCaptureBlockEnabled(BOOL enabled);   // Block UIScreen.isCaptured
void LCSetSpoofMessageEnabled(BOOL enabled);         // MFMessageComposeViewController.canSendText
void LCSetSpoofMailEnabled(BOOL enabled);            // MFMailComposeViewController.canSendMail
void LCSetSpoofBugsnagEnabled(BOOL enabled);         // Bugsnag jailbreak payload patch
void LCSetSpoofCraneEnabled(BOOL enabled);           // Crane marker filtering
void LCSetSpoofPasteboardEnabled(BOOL enabled);      // UIPasteboard.string
void LCSetSpoofAlbumEnabled(BOOL enabled);           // Photos album filtering
void LCSetSpoofAppiumEnabled(BOOL enabled);          // Appium/WebDriver marker filtering
void LCSetKeyboardSpoofingEnabled(BOOL enabled);     // UITextInputMode keyboard surfaces
void LCSetUserDefaultsSpoofingEnabled(BOOL enabled); // NSUserDefaults fingerprint keys
void LCSetEntitlementsSpoofingEnabled(BOOL enabled); // Entitlement key sanitization (targeted)
void LCSetFileTimestampSpoofingEnabled(BOOL enabled);// File creation/modification metadata
BOOL LCIsScreenCaptureBlockEnabled(void);
void LCSetAlbumBlacklistArray(NSArray<NSString *> *blacklist); // "<localId>-<title>" entries

// Device attestation spoofing
void LCSetDeviceCheckSpoofingEnabled(BOOL enabled);  // DCDevice
void LCSetAppAttestSpoofingEnabled(BOOL enabled);    // DCAppAttestService

// Random generation helpers
NSString *LCGenerateRandomUUID(void);
NSString *LCGenerateRandomMACAddress(void);
NSString *LCGenerateRandomInstallationID(int length);

#endif /* DeviceSpoofing_h */
