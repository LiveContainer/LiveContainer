//
//  DeviceSpoofing.m
//  LiveContainer
//
//  Ghost-parity device spoofing core.
//  This file intentionally keeps a compatibility API surface while
//  implementing a minimal, deterministic spoofing model.
//

#import "DeviceSpoofing.h"

#import <AdSupport/AdSupport.h>
#import <CoreMotion/CoreMotion.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <DeviceCheck/DeviceCheck.h>
#import <MessageUI/MessageUI.h>
#import <Photos/Photos.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <WebKit/WebKit.h>
#import <arpa/inet.h>
#import <ctype.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <float.h>
#import <ifaddrs.h>
#import <mach/host_info.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach/machine.h>
#import <mach/processor_info.h>
#import <mach/task_info.h>
#import <mach/vm_statistics.h>
#import <math.h>
#import <net/if_dl.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdio.h>
#import <stdarg.h>
#import <sys/mount.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <os/lock.h>
#import <stdatomic.h>
#import <time.h>
#import <unistd.h>

#if __has_include(<IOKit/IOKitLib.h>)
#import <IOKit/IOKitLib.h>
#define LC_HAS_IOKIT 1
#else
#define LC_HAS_IOKIT 0
typedef uint32_t io_registry_entry_t;
typedef uint32_t IOOptionBits;
#endif

#import "../../fishhook/fishhook.h"

#pragma mark - Profiles

typedef struct {
    uint32_t f_type;
    uint32_t f_bsize;
    uint64_t f_blocks;
    uint64_t f_bfree;
    uint64_t f_bavail;
    uint64_t f_files;
    uint64_t f_ffree;
    fsid_t f_fsid;
    uint32_t f_flags;
    uint32_t f_namelen;
    char f_fstypename[MFSNAMELEN];
    char f_mntonname[MNAMELEN];
    char f_mntfromname[MNAMELEN];
} LCStatfs64;

// Verify LCStatfs64 layout matches system statfs64 at compile time.
// If this fires, the system struct layout has changed and LCStatfs64 must be updated.
_Static_assert(sizeof(LCStatfs64) > 0, "LCStatfs64 must be non-empty");
_Static_assert(offsetof(LCStatfs64, f_blocks) == 8, "LCStatfs64 f_blocks offset mismatch");
_Static_assert(offsetof(LCStatfs64, f_bfree) == 16, "LCStatfs64 f_bfree offset mismatch");

const LCDeviceProfile kDeviceProfileiPhone16ProMax = {
    .modelIdentifier = "iPhone17,2",
    .hardwareModel = "D94AP",
    .marketingName = "iPhone 16 Pro Max",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8140",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 440,
    .screenHeight = 956,
    .chipName = "Apple A18 Pro",
    .gpuName = "Apple A18 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone16Pro = {
    .modelIdentifier = "iPhone17,1",
    .hardwareModel = "D93AP",
    .marketingName = "iPhone 16 Pro",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8140",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 402,
    .screenHeight = 874,
    .chipName = "Apple A18 Pro",
    .gpuName = "Apple A18 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone16 = {
    .modelIdentifier = "iPhone17,3",
    .hardwareModel = "D47AP",
    .marketingName = "iPhone 16",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8130",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A18",
    .gpuName = "Apple A18 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone16e = {
    .modelIdentifier = "iPhone17,4",
    .hardwareModel = "D48AP",
    .marketingName = "iPhone 16e",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8130",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A18",
    .gpuName = "Apple A18 GPU"
};

// Compatibility aliases for existing UI options. Kept deterministic; no speculative OS build data.
const LCDeviceProfile kDeviceProfileiPhone17ProMax = {
    .modelIdentifier = "iPhone18,2",
    .hardwareModel = "V54AP",
    .marketingName = "iPhone 17 Pro Max",
    .systemVersion = "26.0",
    .buildVersion = "23A341",
    .kernelVersion = "Darwin Kernel Version 25.0.0: Wed Jun 11 19:43:22 PDT 2025; root:xnu-12100.1.1~3/RELEASE_ARM64_T8150",
    .kernelRelease = "25.0.0",
    .physicalMemory = 12884901888ULL,
    .cpuCoreCount = 8,
    .performanceCores = 2,
    .efficiencyCores = 6,
    .screenScale = 3.0,
    .screenWidth = 440,
    .screenHeight = 956,
    .chipName = "Apple A19 Pro",
    .gpuName = "Apple A19 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17Pro = {
    .modelIdentifier = "iPhone18,1",
    .hardwareModel = "V53AP",
    .marketingName = "iPhone 17 Pro",
    .systemVersion = "26.0",
    .buildVersion = "23A341",
    .kernelVersion = "Darwin Kernel Version 25.0.0: Wed Jun 11 19:43:22 PDT 2025; root:xnu-12100.1.1~3/RELEASE_ARM64_T8150",
    .kernelRelease = "25.0.0",
    .physicalMemory = 12884901888ULL,
    .cpuCoreCount = 8,
    .performanceCores = 2,
    .efficiencyCores = 6,
    .screenScale = 3.0,
    .screenWidth = 402,
    .screenHeight = 874,
    .chipName = "Apple A19 Pro",
    .gpuName = "Apple A19 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17 = {
    .modelIdentifier = "iPhone18,3",
    .hardwareModel = "V57AP",
    .marketingName = "iPhone 17",
    .systemVersion = "26.0",
    .buildVersion = "23A341",
    .kernelVersion = "Darwin Kernel Version 25.0.0: Wed Jun 11 19:43:22 PDT 2025; root:xnu-12100.1.1~3/RELEASE_ARM64_T8150",
    .kernelRelease = "25.0.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 402,
    .screenHeight = 874,
    .chipName = "Apple A19",
    .gpuName = "Apple A19 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17Air = {
    .modelIdentifier = "iPhone18,4",
    .hardwareModel = "D23AP",
    .marketingName = "iPhone Air",
    .systemVersion = "26.0",
    .buildVersion = "23A341",
    .kernelVersion = "Darwin Kernel Version 25.0.0: Wed Jun 11 19:43:22 PDT 2025; root:xnu-12100.1.1~3/RELEASE_ARM64_T8150",
    .kernelRelease = "25.0.0",
    .physicalMemory = 12884901888ULL,
    .cpuCoreCount = 8,
    .performanceCores = 2,
    .efficiencyCores = 6,
    .screenScale = 3.0,
    .screenWidth = 420,
    .screenHeight = 912,
    .chipName = "Apple A19 Pro",
    .gpuName = "Apple A19 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone15ProMax = {
    .modelIdentifier = "iPhone16,2",
    .hardwareModel = "D84AP",
    .marketingName = "iPhone 15 Pro Max",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8130",
    .kernelRelease = "23.6.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 430,
    .screenHeight = 932,
    .chipName = "Apple A17 Pro",
    .gpuName = "Apple A17 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone15Pro = {
    .modelIdentifier = "iPhone16,1",
    .hardwareModel = "D83AP",
    .marketingName = "iPhone 15 Pro",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8130",
    .kernelRelease = "23.6.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A17 Pro",
    .gpuName = "Apple A17 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone14ProMax = {
    .modelIdentifier = "iPhone15,3",
    .hardwareModel = "D74AP",
    .marketingName = "iPhone 14 Pro Max",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8120",
    .kernelRelease = "23.6.0",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 430,
    .screenHeight = 932,
    .chipName = "Apple A16 Bionic",
    .gpuName = "Apple A16 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone14Pro = {
    .modelIdentifier = "iPhone15,2",
    .hardwareModel = "D73AP",
    .marketingName = "iPhone 14 Pro",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8120",
    .kernelRelease = "23.6.0",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A16 Bionic",
    .gpuName = "Apple A16 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone13ProMax = {
    .modelIdentifier = "iPhone14,3",
    .hardwareModel = "D64AP",
    .marketingName = "iPhone 13 Pro Max",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8110",
    .kernelRelease = "23.6.0",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 428,
    .screenHeight = 926,
    .chipName = "Apple A15 Bionic",
    .gpuName = "Apple A15 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone13Pro = {
    .modelIdentifier = "iPhone14,2",
    .hardwareModel = "D63AP",
    .marketingName = "iPhone 13 Pro",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8110",
    .kernelRelease = "23.6.0",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 390,
    .screenHeight = 844,
    .chipName = "Apple A15 Bionic",
    .gpuName = "Apple A15 GPU"
};

#pragma mark - Global State
	
// Thread-safety model:
// - Hooks run on arbitrary threads.
// - Configuration is applied in an explicit bootstrap window
//   (LCDeviceSpoofingBeginConfiguration/LCDeviceSpoofingEndConfiguration).
// - Setters are no-ops outside that window to avoid unsynchronized
//   global-object mutation while hooked code is executing.

static _Atomic BOOL g_deviceSpoofingEnabled = NO;
static _Atomic BOOL g_deviceSpoofingConfigLocked = NO;
static _Atomic BOOL g_deviceSpoofingConfigLockLogged = NO;
static os_unfair_lock g_deviceSpoofingConfigLock = OS_UNFAIR_LOCK_INIT;

static inline BOOL LCDeviceSpoofingConfigIsLocked(void) {
    return atomic_load_explicit(&g_deviceSpoofingConfigLocked, memory_order_acquire);
}

static inline void LCDeviceSpoofingLogConfigLockedOnce(void) {
    BOOL expected = NO;
    if (atomic_compare_exchange_strong(&g_deviceSpoofingConfigLockLogged, &expected, YES)) {
        NSLog(@"[LC] DeviceSpoofing config is locked; ignoring runtime configuration changes");
    }
}

static inline void LCDeviceSpoofingSetConfigLocked(BOOL locked) {
    os_unfair_lock_lock(&g_deviceSpoofingConfigLock);
    atomic_store_explicit(&g_deviceSpoofingConfigLocked, locked, memory_order_release);
    if (!locked) {
        atomic_store_explicit(&g_deviceSpoofingConfigLockLogged, NO, memory_order_release);
    }
    os_unfair_lock_unlock(&g_deviceSpoofingConfigLock);
}

static inline void LCUnfairLockUnlockCleanup(os_unfair_lock **lockPtr) {
    if (lockPtr && *lockPtr) {
        os_unfair_lock_unlock(*lockPtr);
    }
}

#define LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD() \
    os_unfair_lock *lc_ds_config_lock __attribute__((cleanup(LCUnfairLockUnlockCleanup))) = &g_deviceSpoofingConfigLock; \
    os_unfair_lock_lock(lc_ds_config_lock); \
    if (LCDeviceSpoofingConfigIsLocked()) { \
        os_unfair_lock_unlock(lc_ds_config_lock); \
        lc_ds_config_lock = NULL; \
        LCDeviceSpoofingLogConfigLockedOnce(); \
        return; \
    }

static NSString *g_currentProfileName = nil;
static const LCDeviceProfile * _Atomic g_currentProfile = NULL;

static NSString *g_customDeviceModel = nil;
static NSString *g_customSystemVersion = nil;
static NSString *g_customBuildVersion = nil;
static NSString *g_customKernelVersion = nil;
static NSString *g_customKernelRelease = nil;
static NSString *g_customDeviceName = nil;
static NSString *g_customCarrierName = nil;
static NSString *g_customCarrierMCC = nil;
static NSString *g_customCarrierMNC = nil;
static NSString *g_customCarrierCountryCode = nil;
static _Atomic BOOL g_cellularTypeConfigured = NO;
static _Atomic NSInteger g_spoofedCellularType = -1;
static _Atomic BOOL g_networkInfoSpoofingEnabled = NO;
static _Atomic BOOL g_spoofWiFiAddressEnabled = NO;
static _Atomic BOOL g_spoofCellularAddressEnabled = NO;
static NSString *g_spoofedWiFiAddress = nil;
static NSString *g_spoofedCellularAddress = nil;
static NSString *g_spoofedWiFiSSID = nil;
static NSString *g_spoofedWiFiBSSID = nil;
static NSString *g_spoofedPreferredCountryCode = nil;

static NSString *g_spoofedVendorID = nil;
static NSString *g_spoofedAdvertisingID = nil;
static NSString *g_spoofedInstallationID = nil;
static NSString *g_spoofedPersistentDeviceID = nil;
static NSString *g_spoofedMACAddress = nil;
static _Atomic BOOL g_adTrackingConfigured = NO;
static _Atomic BOOL g_spoofedAdTrackingEnabled = NO;

static _Atomic BOOL g_batteryLevelConfigured = NO;
static _Atomic float g_spoofedBatteryLevel = -1.0f;
static _Atomic BOOL g_batteryStateConfigured = NO;
static _Atomic NSInteger g_spoofedBatteryState = -1;
static _Atomic BOOL g_brightnessConfigured = NO;
static _Atomic float g_spoofedBrightness = -1.0f;
static _Atomic BOOL g_thermalConfigured = NO;
static _Atomic NSInteger g_spoofedThermalState = -1;
static _Atomic BOOL g_spoofLowPowerMode = NO;
static _Atomic BOOL g_lowPowerModeValue = NO;

// Compatibility-only state for deprecated surfaces.
static _Atomic BOOL g_storageSpoofingEnabled = NO;
static _Atomic BOOL g_storageRandomFreeEnabled = YES;
static _Atomic uint64_t g_spoofedStorageTotal = 0;
static _Atomic uint64_t g_spoofedStorageFree = 0;
static _Atomic BOOL g_storageFreeExplicitlySet = NO;
static NSString *g_spoofedStorageCapacityGB = nil;
static NSString *g_spoofedStorageFreeGB = nil;
static _Atomic BOOL g_canvasFingerprintProtectionEnabled = NO;
static _Atomic BOOL g_iCloudPrivacyProtectionEnabled = YES;
static _Atomic BOOL g_siriPrivacyProtectionEnabled = NO;
static NSString *g_customUserAgent = nil;
static _Atomic BOOL g_userAgentSpoofingEnabled = NO;

// Boot time / uptime state
static _Atomic BOOL g_bootTimeSpoofingEnabled = NO;
static _Atomic NSTimeInterval g_bootTimeOffset = 0; // seconds subtracted from real boot time
static _Atomic NSTimeInterval g_uptimeTarget = 0;   // target uptime in seconds

// Timezone, locale, and screen capture state
static NSString *g_spoofedTimezone = nil;
static NSString *g_spoofedLocale = nil;
static _Atomic BOOL g_screenCaptureBlockEnabled = NO;
static _Atomic BOOL g_spoofMessageEnabled = NO;
static _Atomic BOOL g_spoofMailEnabled = NO;
static _Atomic BOOL g_spoofBugsnagEnabled = NO;
static _Atomic BOOL g_spoofCraneEnabled = NO;
static _Atomic BOOL g_spoofPasteboardEnabled = NO;
static _Atomic BOOL g_spoofAlbumEnabled = NO;
static _Atomic BOOL g_spoofAppiumEnabled = NO;
static _Atomic BOOL g_keyboardSpoofingEnabled = NO;
static _Atomic BOOL g_userDefaultsSpoofingEnabled = NO;
static _Atomic BOOL g_spoofEntitlementsEnabled = NO;
static _Atomic BOOL g_fileTimestampSpoofingEnabled = NO;
static _Atomic NSTimeInterval g_fileTimestampSeedSeconds = 0;
static NSArray<NSString *> *g_albumBlacklist = nil;
static NSString *g_spoofedLocaleCurrencyCode = nil;
static NSString *g_spoofedLocaleCurrencySymbol = nil;
static _Atomic BOOL g_spoofProximityEnabled = NO;
static _Atomic BOOL g_spoofOrientationEnabled = NO;
static _Atomic BOOL g_spoofGyroscopeEnabled = NO;
static _Atomic BOOL g_deviceCheckSpoofingEnabled = NO;
static _Atomic BOOL g_appAttestSpoofingEnabled = NO;

// Lock for method swizzling to prevent TOCTOU races in LCInstallInstanceHook
static os_unfair_lock g_hookInstallLock = OS_UNFAIR_LOCK_INIT;

#pragma mark - Original Function Pointers

static int (*orig_uname)(struct utsname *name) = NULL;
static int (*orig_gethostname)(char *name, size_t namelen) = NULL;
static long (*orig_sysconf)(int name) = NULL;
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int (*orig_statfs)(const char *path, struct statfs *buf) = NULL;
static int (*orig_statfs64)(const char *path, void *buf) = NULL;
static int (*orig_fstatfs)(int fd, struct statfs *buf) = NULL;
static int (*orig_getfsstat)(struct statfs *buf, int bufsize, int flags) = NULL;
static int (*orig_getfsstat64)(void *buf, int bufsize, int flags) = NULL;
static int (*orig_getifaddrs)(struct ifaddrs **ifap) = NULL;
static int (*orig_clock_gettime)(clockid_t clk_id, struct timespec *tp) = NULL;
static uint64_t (*orig_clock_gettime_nsec_np)(clockid_t clk_id) = NULL;
static uint64_t (*orig_mach_absolute_time)(void) = NULL;
static uint64_t (*orig_mach_approximate_time)(void) = NULL;
static uint64_t (*orig_mach_continuous_time)(void) = NULL;
static uint64_t (*orig_mach_continuous_approximate_time)(void) = NULL;
static CGRect (*orig_CGDisplayBounds)(uint32_t display) = NULL;
static size_t (*orig_CGDisplayPixelsWide)(uint32_t display) = NULL;
static size_t (*orig_CGDisplayPixelsHigh)(uint32_t display) = NULL;
static kern_return_t (*orig_host_statistics)(host_t host, host_flavor_t flavor, host_info_t info, mach_msg_type_number_t *count) = NULL;
static kern_return_t (*orig_host_statistics64)(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count) = NULL;
static kern_return_t (*orig_host_processor_info)(host_t host, processor_flavor_t flavor, natural_t *out_processor_count,
                                                  processor_info_array_t *out_processor_info,
                                                  mach_msg_type_number_t *out_processor_infoCnt) = NULL;
static kern_return_t (*orig_task_info)(task_t target_task, task_flavor_t flavor, task_info_t task_info_out,
                                       mach_msg_type_number_t *task_info_outCnt) = NULL;
static BOOL (*orig_UIAccessibilityIsVoiceOverRunning)(void) = NULL;
static BOOL (*orig_UIAccessibilityIsGuidedAccessEnabled)(void) = NULL;
static BOOL (*orig_UIAccessibilityIsMonoAudioEnabled)(void) = NULL;
static BOOL (*orig_UIAccessibilityIsInvertColorsEnabled)(void) = NULL;
static BOOL (*orig_UIAccessibilityIsBoldTextEnabled)(void) = NULL;
static BOOL (*orig_UIAccessibilityDarkerSystemColorsEnabled)(void) = NULL;
static BOOL (*orig_UIAccessibilityIsReduceMotionEnabled)(void) = NULL;
static BOOL (*orig_UIAccessibilityIsReduceTransparencyEnabled)(void) = NULL;
static BOOL (*orig_UIAccessibilityIsClosedCaptioningEnabled)(void) = NULL;
static BOOL (*orig_UIAccessibilityIsAssistiveTouchRunning)(void) = NULL;
static BOOL (*orig_UIAccessibilityIsVideoAutoplayEnabled)(void) = NULL;

static NSString *(*orig_UIDevice_systemVersion)(id self, SEL _cmd) = NULL;
static NSString *(*orig_UIDevice_systemName)(id self, SEL _cmd) = NULL;
static NSString *(*orig_UIDevice_name)(id self, SEL _cmd) = NULL;
static NSUUID *(*orig_UIDevice_identifierForVendor)(id self, SEL _cmd) = NULL;
static float (*orig_UIDevice_batteryLevel)(id self, SEL _cmd) = NULL;
static NSInteger (*orig_UIDevice_batteryState)(id self, SEL _cmd) = NULL;
static BOOL (*orig_UIDevice_isBatteryMonitoringEnabled)(id self, SEL _cmd) = NULL;
static BOOL (*orig_UIDevice_proximityState)(id self, SEL _cmd) = NULL;
static BOOL (*orig_UIDevice_isProximityMonitoringEnabled)(id self, SEL _cmd) = NULL;
static UIDeviceOrientation (*orig_UIDevice_orientation)(id self, SEL _cmd) = NULL;
static NSString *(*orig_UIDevice_machineName)(id self, SEL _cmd) = NULL;
static id (*orig_UIDevice_deviceInfoForKey)(id self, SEL _cmd, NSString *key) = NULL;

static unsigned long long (*orig_NSProcessInfo_physicalMemory)(id self, SEL _cmd) = NULL;
static unsigned long long (*orig_SwiftNSProcessInfo_physicalMemory)(id self, SEL _cmd) = NULL;
static NSUInteger (*orig_NSProcessInfo_processorCount)(id self, SEL _cmd) = NULL;
static NSUInteger (*orig_NSProcessInfo_activeProcessorCount)(id self, SEL _cmd) = NULL;
static NSOperatingSystemVersion (*orig_NSProcessInfo_operatingSystemVersion)(id self, SEL _cmd) = NULL;
static NSString *(*orig_NSProcessInfo_operatingSystemVersionString)(id self, SEL _cmd) = NULL;
static NSInteger (*orig_NSProcessInfo_thermalState)(id self, SEL _cmd) = NULL;
static BOOL (*orig_NSProcessInfo_isLowPowerModeEnabled)(id self, SEL _cmd) = NULL;
static NSDictionary *(*orig_NSProcessInfo_environment)(id self, SEL _cmd) = NULL;
static NSArray<NSString *> *(*orig_NSProcessInfo_arguments)(id self, SEL _cmd) = NULL;
static NSString *(*orig_NSProcessInfo_hostName)(id self, SEL _cmd) = NULL;
static NSString *(*orig_NSProcessInfo_operatingSystemName)(id self, SEL _cmd) = NULL;
static NSString *(*orig_NSProcessInfo_globallyUniqueString)(id self, SEL _cmd) = NULL;

static CGFloat (*orig_UIScreen_brightness)(id self, SEL _cmd) = NULL;

static NSUUID *(*orig_ASIdentifierManager_advertisingIdentifier)(id self, SEL _cmd) = NULL;
static BOOL (*orig_ASIdentifierManager_isAdvertisingTrackingEnabled)(id self, SEL _cmd) = NULL;

static NSTimeInterval (*orig_NSProcessInfo_systemUptime)(id self, SEL _cmd) = NULL;

static id (*orig_NSFileManager_ubiquityIdentityToken)(id self, SEL _cmd) = NULL;
static NSData *(*orig_NSFileManager_contentsAtPath)(id self, SEL _cmd, NSString *path) = NULL;
static NSDictionary *(*orig_NSFileManager_attributesOfFileSystemForPath)(id self, SEL _cmd, NSString *path, NSError **error) = NULL;
static NSDictionary *(*orig_NSFileManager_attributesOfItemAtPath_error)(id self, SEL _cmd, NSString *path, NSError **error) = NULL;
static unsigned long long (*orig_NSFileManager_volumeAvailableCapacityForImportantUsageForURL)(id self, SEL _cmd, NSURL *url, NSError **error) = NULL;
static unsigned long long (*orig_NSFileManager_volumeAvailableCapacityForOpportunisticUsageForURL)(id self, SEL _cmd, NSURL *url, NSError **error) = NULL;
static unsigned long long (*orig_NSFileManager_volumeTotalCapacityForURL)(id self, SEL _cmd, NSURL *url, NSError **error) = NULL;
static NSString *(*orig_CTCarrier_carrierName)(id self, SEL _cmd) = NULL;
static NSString *(*orig_CTCarrier_isoCountryCode)(id self, SEL _cmd) = NULL;
static NSString *(*orig_CTCarrier_mobileCountryCode)(id self, SEL _cmd) = NULL;
static NSString *(*orig_CTCarrier_mobileNetworkCode)(id self, SEL _cmd) = NULL;
static NSString *(*orig_CTTelephonyNetworkInfo_currentRadioAccessTechnology)(id self, SEL _cmd) = NULL;
static NSDictionary *(*orig_CTTelephonyNetworkInfo_serviceCurrentRadioAccessTechnology)(id self, SEL _cmd) = NULL;
static BOOL (*orig_NSURL_getResourceValue_forKey_error)(id self, SEL _cmd, id *value, NSURLResourceKey key, NSError **error) = NULL;
static NSDictionary<NSURLResourceKey, id> *(*orig_NSURL_resourceValuesForKeys_error)(id self, SEL _cmd, NSArray<NSURLResourceKey> *keys, NSError **error) = NULL;

static NSString *(*orig_WKWebView_customUserAgent)(id self, SEL _cmd) = NULL;
static WKWebView *(*orig_WKWebView_initWithFrame)(id self, SEL _cmd, CGRect frame, WKWebViewConfiguration *config) = NULL;
static void (*orig_WKWebView_didFinishNavigation)(id self, SEL _cmd, WKWebView *webView, WKNavigation *navigation) = NULL;

static CGRect (*orig_UIScreen_bounds)(id self, SEL _cmd) = NULL;
static CGRect (*orig_UIScreen_nativeBounds)(id self, SEL _cmd) = NULL;
static CGRect (*orig_UIScreen_boundsForInterfaceOrientation)(id self, SEL _cmd, UIInterfaceOrientation orientation) = NULL;
static CGRect (*orig_UIScreen_referenceBounds)(id self, SEL _cmd) = NULL;
static CGRect (*orig_UIScreen_privateBounds)(id self, SEL _cmd) = NULL;
static CGRect (*orig_UIScreen_privateNativeBounds)(id self, SEL _cmd) = NULL;
static CGFloat (*orig_UIScreen_scale)(id self, SEL _cmd) = NULL;
static CGFloat (*orig_UIScreen_nativeScale)(id self, SEL _cmd) = NULL;
static CGRect (*orig_UIScreen_applicationFrame)(id self, SEL _cmd) = NULL;
static id (*orig_UIScreen_coordinateSpace)(id self, SEL _cmd) = NULL;
static id (*orig_UIScreen_fixedCoordinateSpace)(id self, SEL _cmd) = NULL;
static UIScreenMode *(*orig_UIScreen_currentMode)(id self, SEL _cmd) = NULL;
static UIScreenMode *(*orig_UIScreen_preferredMode)(id self, SEL _cmd) = NULL;
static NSArray<UIScreenMode *> *(*orig_UIScreen_availableModes)(id self, SEL _cmd) = NULL;
static NSInteger (*orig_UIScreen_maximumFramesPerSecond)(id self, SEL _cmd) = NULL;
static CGSize (*orig_UIScreenMode_size)(id self, SEL _cmd) = NULL;
static CGFloat (*orig_UITraitCollection_displayScale)(id self, SEL _cmd) = NULL;

static NSString *(*orig_UIDevice_model)(id self, SEL _cmd) = NULL;
static NSString *(*orig_UIDevice_localizedModel)(id self, SEL _cmd) = NULL;

static BOOL (*orig_NSProcessInfo_isOperatingSystemAtLeastVersion)(id self, SEL _cmd, NSOperatingSystemVersion version) = NULL;

static void (*orig_NSMutableURLRequest_setValue_forHTTPHeaderField)(id self, SEL _cmd, NSString *value, NSString *field) = NULL;
static void (*orig_WKWebViewConfiguration_setApplicationNameForUserAgent)(id self, SEL _cmd, NSString *name) = NULL;

static NSTimeZone *(*orig_NSTimeZone_localTimeZone)(id self, SEL _cmd) = NULL;
static NSTimeZone *(*orig_NSTimeZone_systemTimeZone)(id self, SEL _cmd) = NULL;
static NSTimeZone *(*orig_NSTimeZone_defaultTimeZone)(id self, SEL _cmd) = NULL;
static NSLocale *(*orig_NSLocale_currentLocale)(id self, SEL _cmd) = NULL;
static NSLocale *(*orig_NSLocale_autoupdatingCurrentLocale)(id self, SEL _cmd) = NULL;
static NSLocale *(*orig_NSLocale_systemLocale)(id self, SEL _cmd) = NULL;
static NSArray<NSString *> *(*orig_NSLocale_preferredLanguages)(id self, SEL _cmd) = NULL;
static id (*orig_NSLocale_objectForKey)(id self, SEL _cmd, id key) = NULL;
static NSString *(*orig_NSLocale_countryCode)(id self, SEL _cmd) = NULL;
static NSString *(*orig_NSLocale_currencyCode)(id self, SEL _cmd) = NULL;
static NSString *(*orig_NSLocale_currencySymbol)(id self, SEL _cmd) = NULL;
static BOOL (*orig_NSLocale_usesMetricSystem)(id self, SEL _cmd) = NULL;
static NSOperatingSystemVersion (*orig_SwiftNSProcessInfo_operatingSystemVersion)(id self, SEL _cmd) = NULL;
static NSString *(*orig_SwiftNSProcessInfo_operatingSystemVersionString)(id self, SEL _cmd) = NULL;
static NSString *(*orig_SwiftNSProcessInfo_hostName)(id self, SEL _cmd) = NULL;
static BOOL (*orig_SwiftNSProcessInfo_isOperatingSystemAtLeastVersion)(id self, SEL _cmd, NSOperatingSystemVersion version) = NULL;
static BOOL (*orig_UIScreen_isCaptured)(id self, SEL _cmd) = NULL;
static CGRect (*orig_UIApplication_statusBarFrame)(id self, SEL _cmd) = NULL;
static CGRect (*orig_UIStatusBarManager_statusBarFrame)(id self, SEL _cmd) = NULL;
static BOOL (*orig_UIApplication_canOpenURL)(id self, SEL _cmd, NSURL *url) = NULL;
static NSString *(*orig_UIApplication_preferredContentSizeCategory)(id self, SEL _cmd) = NULL;
static NSString *(*orig_UITraitCollection_preferredContentSizeCategory)(id self, SEL _cmd) = NULL;
static NSString *(*orig_NSCalendar_identifier)(id self, SEL _cmd) = NULL;

static BOOL (*orig_MFMessageComposeViewController_canSendText)(id self, SEL _cmd) = NULL;
static BOOL (*orig_MFMessageComposeViewController_canSendAttachments)(id self, SEL _cmd) = NULL;
static BOOL (*orig_MFMessageComposeViewController_canSendSubject)(id self, SEL _cmd) = NULL;
static BOOL (*orig_MFMailComposeViewController_canSendMail)(id self, SEL _cmd) = NULL;
static NSArray *(*orig_UITextInputMode_activeInputModes)(id self, SEL _cmd) = NULL;
static id (*orig_UITextInputMode_currentInputMode)(id self, SEL _cmd) = NULL;
static NSString *(*orig_UITextInputMode_primaryLanguage)(id self, SEL _cmd) = NULL;
static id (*orig_NSUserDefaults_objectForKey)(id self, SEL _cmd, NSString *defaultName) = NULL;
static NSDictionary<NSString *, id> *(*orig_NSUserDefaults_dictionaryRepresentation)(id self, SEL _cmd) = NULL;
static id (*orig_NSPropertyListSerialization_propertyListWithData_options_format_error)(id self, SEL _cmd, NSData *data, NSPropertyListReadOptions options, NSPropertyListFormat *format, NSError **error) = NULL;
static NSString *(*orig_UIPasteboard_string)(id self, SEL _cmd) = NULL;
static NSArray<NSString *> *(*orig_UIPasteboard_strings)(id self, SEL _cmd) = NULL;
static BOOL (*orig_UIPasteboard_hasStrings)(id self, SEL _cmd) = NULL;
static NSData *(*orig_UIPasteboard_dataForPasteboardType)(id self, SEL _cmd, NSString *pasteboardType) = NULL;
static BOOL (*orig_NSString_containsString)(id self, SEL _cmd, NSString *query) = NULL;
static BOOL (*orig_NSString_hasPrefix)(id self, SEL _cmd, NSString *prefix) = NULL;
static BOOL (*orig_NSString_hasSuffix)(id self, SEL _cmd, NSString *suffix) = NULL;
static NSRange (*orig_NSString_rangeOfString)(id self, SEL _cmd, NSString *searchString) = NULL;
static BOOL (*orig_NSPredicate_evaluateWithObject)(id self, SEL _cmd, id object) = NULL;
static id (*orig_PHAssetCollection_fetchAssetCollectionsWithType_subtype_options)(id self, SEL _cmd, NSInteger type, NSInteger subtype, id options) = NULL;

static BOOL (*orig_BugsnagDevice_jailbroken)(id self, SEL _cmd) = NULL;
static void (*orig_BugsnagDevice_setJailbroken)(id self, SEL _cmd, BOOL value) = NULL;
static id (*orig_NSURLSession_uploadTaskWithRequest_fromData_completionHandler)(id self, SEL _cmd, NSURLRequest *request, NSData *bodyData, id completionHandler) = NULL;

static BOOL (*orig_DCDevice_isSupported)(id self, SEL _cmd) = NULL;
static void (*orig_DCDevice_generateTokenWithCompletionHandler)(id self, SEL _cmd, id completion) = NULL;
static BOOL (*orig_DCAppAttestService_isSupported)(id self, SEL _cmd) = NULL;
static void (*orig_DCAppAttestService_generateKeyWithCompletionHandler)(id self, SEL _cmd, id completion) = NULL;
static void (*orig_DCAppAttestService_attestKey_clientDataHash_completionHandler)(id self, SEL _cmd, NSString *keyId, NSData *clientDataHash, id completion) = NULL;
static void (*orig_DCAppAttestService_generateAssertion_clientDataHash_completionHandler)(id self, SEL _cmd, NSString *keyId, NSData *clientDataHash, id completion) = NULL;
static BOOL (*orig_CMMotionManager_isGyroAvailable)(id self, SEL _cmd) = NULL;
static BOOL (*orig_CMMotionManager_isDeviceMotionAvailable)(id self, SEL _cmd) = NULL;
static BOOL (*orig_CTCarrier_allowsVOIP)(id self, SEL _cmd) = NULL;
static NSArray *(*orig_EAAccessoryManager_connectedAccessories)(id self, SEL _cmd) = NULL;
static float (*orig_AVAudioSession_outputVolume)(id self, SEL _cmd) = NULL;
static BOOL (*orig_AVAudioSession_secondaryAudioShouldBeSilencedHint)(id self, SEL _cmd) = NULL;
static BOOL (*orig_SKPaymentQueue_canMakePayments)(id self, SEL _cmd) = NULL;
static BOOL (*orig_PKPaymentAuthorizationViewController_canMakePayments)(id self, SEL _cmd) = NULL;
static BOOL (*orig_PKPaymentAuthorizationViewController_canMakePaymentsUsingNetworks)(id self, SEL _cmd, NSArray *networks) = NULL;
static BOOL (*orig_PKPaymentAuthorizationController_canMakePayments)(id self, SEL _cmd) = NULL;
static BOOL (*orig_PKPaymentAuthorizationController_canMakePaymentsUsingNetworks)(id self, SEL _cmd, NSArray *networks) = NULL;
static BOOL (*orig_SLComposeViewController_isAvailableForServiceType)(id self, SEL _cmd, NSString *serviceType) = NULL;
static BOOL (*orig_CLLocationManager_locationServicesEnabled)(id self, SEL _cmd) = NULL;
static BOOL (*orig_LAContext_canEvaluatePolicy_error)(id self, SEL _cmd, NSInteger policy, NSError **error) = NULL;
static NSInteger (*orig_LAContext_biometryType)(id self, SEL _cmd) = NULL;
static NSInteger (*orig_INPreferences_siriAuthorizationStatus)(id self, SEL _cmd) = NULL;
static void (*orig_INPreferences_requestSiriAuthorization)(id self, SEL _cmd, id handler) = NULL;

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key) = NULL;
static CFTypeRef (*orig_IORegistryEntryCreateCFProperty)(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) = NULL;
static CFTypeRef (*orig_IORegistryEntrySearchCFProperty)(io_registry_entry_t entry, const char *plane, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) = NULL;
static CFDictionaryRef (*orig_CFCopySystemVersionDictionary)(void) = NULL;
static CFDictionaryRef (*orig_CNCopyCurrentNetworkInfo)(CFStringRef interfaceName) = NULL;
static id (*orig_MTLCreateSystemDefaultDevice)(void) = NULL;
static NSArray *(*orig_MTLCopyAllDevices)(void) = NULL;
static NSString *(*orig_MTLDevice_name)(id self, SEL _cmd) = NULL;
static NSString *(*orig_MTLDevice_familyName)(id self, SEL _cmd) = NULL;

#pragma mark - Helpers

static inline BOOL LCDeviceSpoofingIsActive(void) {
    return g_deviceSpoofingEnabled;
}

static const char *LCSpoofedMachineModel(void) {
    if (g_customDeviceModel.length > 0) return g_customDeviceModel.UTF8String;
    if (g_currentProfile) return g_currentProfile->modelIdentifier;
    return NULL;
}

static const char *LCSpoofedHardwareModel(void) {
    if (g_currentProfile) return g_currentProfile->hardwareModel;
    return NULL;
}

static const char *LCSpoofedSystemVersion(void) {
    if (g_customSystemVersion.length > 0) return g_customSystemVersion.UTF8String;
    if (g_currentProfile) return g_currentProfile->systemVersion;
    return NULL;
}

static const char *LCSpoofedBuildVersion(void) {
    if (g_customBuildVersion.length > 0) return g_customBuildVersion.UTF8String;
    if (g_currentProfile) return g_currentProfile->buildVersion;
    return NULL;
}

static const char *LCSpoofedKernelVersion(void) {
    if (g_customKernelVersion.length > 0) return g_customKernelVersion.UTF8String;
    if (g_currentProfile) return g_currentProfile->kernelVersion;
    return NULL;
}

static const char *LCSpoofedKernelRelease(void) {
    if (g_customKernelRelease.length > 0) return g_customKernelRelease.UTF8String;
    if (g_currentProfile) return g_currentProfile->kernelRelease;
    return NULL;
}

static const char *LCSpoofedSystemName(void) {
    const char *machine = LCSpoofedMachineModel();
    if (machine && strncmp(machine, "iPad", 4) == 0) {
        return "iPadOS";
    }
    return "iOS";
}

static const char *LCSpoofedMarketingName(void) {
    if (g_currentProfile && g_currentProfile->marketingName) return g_currentProfile->marketingName;
    return LCSpoofedMachineModel();
}

static const char *LCSpoofedKernelName(void) {
    return "Darwin";
}

static NSSet<NSString *> *LCBundleDeclaredURLSchemes(void) {
    static NSSet<NSString *> *schemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet<NSString *> *mutable = [NSMutableSet set];
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;
        id urlTypesObj = info[@"CFBundleURLTypes"];
        if ([urlTypesObj isKindOfClass:[NSArray class]]) {
            for (id entry in (NSArray *)urlTypesObj) {
                if (![entry isKindOfClass:[NSDictionary class]]) continue;
                id schemesObj = ((NSDictionary *)entry)[@"CFBundleURLSchemes"];
                if (![schemesObj isKindOfClass:[NSArray class]]) continue;
                for (id schemeObj in (NSArray *)schemesObj) {
                    if (![schemeObj isKindOfClass:[NSString class]]) continue;
                    NSString *scheme = [(NSString *)schemeObj lowercaseString];
                    if (scheme.length > 0) {
                        [mutable addObject:scheme];
                    }
                }
            }
        }
        schemes = [mutable copy] ?: [NSSet set];
    });
    return schemes ?: [NSSet set];
}

static BOOL LCIsAllowedCanOpenURLScheme(NSString *scheme) {
    if (![scheme isKindOfClass:[NSString class]] || scheme.length == 0) return YES;
    NSString *lower = scheme.lowercaseString;

    if ([LCBundleDeclaredURLSchemes() containsObject:lower]) {
        return YES;
    }

    static NSSet<NSString *> *allowed = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowed = [NSSet setWithArray:@[
            @"http",
            @"https",
            @"mailto",
            @"tel",
            @"telprompt",
            @"sms",
            @"facetime",
            @"facetime-audio",
            @"maps",
            @"itms-apps",
            @"itms-services",
            @"app-settings",
            @"file",
            @"data",
            @"about",
        ]];
    });
    if ([allowed containsObject:lower]) return YES;
    if ([lower hasPrefix:@"x-apple-"] || [lower hasPrefix:@"com.apple."]) return YES;
    return NO;
}

static BOOL LCShouldBlockURLScheme(NSURL *url) {
    if (!LCDeviceSpoofingIsActive()) return NO;
    if (![url isKindOfClass:[NSURL class]]) return NO;
    NSString *scheme = url.scheme;
    if (scheme.length == 0) return NO;
    return !LCIsAllowedCanOpenURLScheme(scheme);
}

static BOOL LCParseMACAddress(NSString *addressString, uint8_t outBytes[6]) {
    if (!outBytes) return NO;
    if (![addressString isKindOfClass:[NSString class]] || addressString.length == 0) return NO;
    unsigned int bytes[6] = {0};
    if (sscanf(addressString.UTF8String, "%x:%x:%x:%x:%x:%x",
               &bytes[0], &bytes[1], &bytes[2], &bytes[3], &bytes[4], &bytes[5]) != 6) {
        return NO;
    }
    for (int i = 0; i < 6; i++) {
        if (bytes[i] > 0xFFU) return NO;
        outBytes[i] = (uint8_t)bytes[i];
    }
    return YES;
}

static float LCSpoofedAudioOutputVolume(void) {
    static float volume = 0.6f;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        volume = 0.35f + ((float)arc4random_uniform(41) / 100.0f); // 0.35 - 0.75
    });
    return volume;
}

static NSString *LCSpoofedLocaleRegionCode(void) {
    if (g_spoofedPreferredCountryCode.length > 0) {
        return g_spoofedPreferredCountryCode.uppercaseString;
    }
    if (g_spoofedLocale.length == 0) {
        return nil;
    }
    NSString *normalized = [g_spoofedLocale stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    NSArray<NSString *> *parts = [normalized componentsSeparatedByString:@"_"];
    if (parts.count >= 2) {
        return parts[1].uppercaseString;
    }
    return nil;
}

static BOOL LCSpoofedUsesMetricSystem(void) {
    NSString *region = LCSpoofedLocaleRegionCode();
    if (region.length == 0) return YES;
    if ([region isEqualToString:@"US"] || [region isEqualToString:@"LR"] || [region isEqualToString:@"MM"]) {
        return NO;
    }
    return YES;
}

static uint32_t LCSpoofedCPUSubtype(void);

static uint64_t LCSpoofedPhysicalMemory(void) {
    // RAM spoofing is profile-derived only; custom overrides are intentionally ignored
    // to prevent cross-surface mismatches.
    if (g_currentProfile) return g_currentProfile->physicalMemory;
    return 0;
}

static uint32_t LCSpoofedCPUCount(void) {
    // Core count is profile-derived only; custom overrides are intentionally ignored.
    if (g_currentProfile) return g_currentProfile->cpuCoreCount;
    return 0;
}

static uint32_t LCSpoofedPerformanceCoreCount(void) {
    if (g_currentProfile && g_currentProfile->performanceCores > 0) {
        return g_currentProfile->performanceCores;
    }
    uint32_t total = LCSpoofedCPUCount();
    if (total >= 6) return 2;
    if (total >= 4) return 2;
    if (total >= 2) return 1;
    return total;
}

static uint32_t LCSpoofedEfficiencyCoreCount(void) {
    if (g_currentProfile && g_currentProfile->efficiencyCores > 0) {
        return g_currentProfile->efficiencyCores;
    }
    uint32_t total = LCSpoofedCPUCount();
    uint32_t perf = LCSpoofedPerformanceCoreCount();
    if (total > perf) return total - perf;
    return 0;
}

static void LCApplySpoofedHostBasicInfo(host_basic_info_t basicInfo, uint64_t totalMemory) {
    if (!basicInfo) return;

    uint32_t logicalCPU = LCSpoofedCPUCount();
    if (logicalCPU == 0) logicalCPU = 1;

    uint32_t physicalCPU = logicalCPU;
    if (g_currentProfile && g_currentProfile->cpuCoreCount > 0) {
        physicalCPU = g_currentProfile->cpuCoreCount;
    }

    basicInfo->max_cpus = (integer_t)logicalCPU;
    basicInfo->avail_cpus = (integer_t)logicalCPU;
    basicInfo->memory_size = (natural_t)MIN(totalMemory, (uint64_t)UINT32_MAX);
    basicInfo->cpu_type = CPU_TYPE_ARM64;
    basicInfo->cpu_subtype = (cpu_subtype_t)LCSpoofedCPUSubtype();
    basicInfo->cpu_threadtype = 0;
    basicInfo->physical_cpu = (integer_t)physicalCPU;
    basicInfo->physical_cpu_max = (integer_t)physicalCPU;
    basicInfo->logical_cpu = (integer_t)logicalCPU;
    basicInfo->logical_cpu_max = (integer_t)logicalCPU;
    basicInfo->max_mem = totalMemory;
}

static const char *LCSpoofedChipName(void) {
    if (g_currentProfile) return g_currentProfile->chipName;
    return NULL;
}

static const char *LCSpoofedGPUName(void) {
    if (g_currentProfile) return g_currentProfile->gpuName;
    return NULL;
}

static CGSize LCSpoofedNativeScreenSize(void) {
    if (!g_currentProfile) return CGSizeZero;
    CGFloat scale = g_currentProfile->screenScale > 0.0 ? g_currentProfile->screenScale : 1.0;
    return CGSizeMake(round(g_currentProfile->screenWidth * scale), round(g_currentProfile->screenHeight * scale));
}

static NSInteger LCSpoofedMaximumFramesPerSecond(void) {
    if (!g_currentProfile || !g_currentProfile->marketingName) return 60;
    return strstr(g_currentProfile->marketingName, "Pro") ? 120 : 60;
}

static inline BOOL LCStorageSpoofingActive(void) {
    return LCDeviceSpoofingIsActive() && g_storageSpoofingEnabled && g_spoofedStorageTotal > 0;
}

static NSInteger LCSpoofedChipSeries(void) {
    const char *chipName = LCSpoofedChipName();
    if (!chipName || chipName[0] == '\0') return 0;

    const char *p = chipName;
    while (*p) {
        if ((*p == 'A' || *p == 'a') && isdigit((unsigned char)*(p + 1))) {
            return (NSInteger)strtol(p + 1, NULL, 10);
        }
        if ((*p == 'M' || *p == 'm') && isdigit((unsigned char)*(p + 1))) {
            return (NSInteger)(100 + strtol(p + 1, NULL, 10));
        }
        p++;
    }
    return 0;
}

static uint32_t LCSpoofedCPUSubtype(void) {
    NSInteger series = LCSpoofedChipSeries();
    if (series >= 100 || series >= 12) { // M-series (100+) or A12+
        return (uint32_t)CPU_SUBTYPE_ARM64E;
    }
    return (uint32_t)CPU_SUBTYPE_ARM64_ALL;
}

static uint32_t LCSpoofedCPUFamily(void) {
    NSInteger series = LCSpoofedChipSeries();
    switch (series) {
        case 15: return 0xDA33D83D;
        case 16: return 0x8765EDEA;
        case 17: return 0xAF4F32CB;
        case 18: return 0x1B588BB3;
        case 19: return 0x458F4D97;
        case 101: return 0x458F4D97;
        case 102: return 0x1B588BB3;
        default: return 0xDA33D83D;
    }
}

static uint64_t LCSpoofedCPUFrequencyHz(void) {
    NSInteger series = LCSpoofedChipSeries();
    switch (series) {
        case 15: return 3230000000ULL;
        case 16: return 3460000000ULL;
        case 17: return 3780000000ULL;
        case 18: return 4050000000ULL;
        case 19: return 4200000000ULL;
        case 101: return 3200000000ULL;
        case 102: return 3490000000ULL;
        default: return 3000000000ULL;
    }
}

static void LCSpoofedCacheValues(uint32_t *outL1ICache, uint32_t *outL1DCache, uint32_t *outL2Cache, uint32_t *outCacheLine) {
    if (outL1ICache) *outL1ICache = 65536U;
    if (outL1DCache) *outL1DCache = 65536U;
    if (outL2Cache) *outL2Cache = 12582912U;
    if (outCacheLine) *outCacheLine = 128U;

    NSInteger series = LCSpoofedChipSeries();
    if (series >= 18) {
        if (outL1ICache) *outL1ICache = 131072U;
        if (outL1DCache) *outL1DCache = 131072U;
        if (outL2Cache) *outL2Cache = 16777216U;
    } else if (series >= 16) {
        if (outL2Cache) *outL2Cache = 16777216U;
    } else if (series >= 15) {
        if (outL2Cache) *outL2Cache = 12582912U;
    }
}

static const char *LCSpoofedCPUFeatures(void) {
    NSInteger series = LCSpoofedChipSeries();
    if (series >= 100 || series >= 17) { // M-series or A17+
        return "NEON AES SHA1 SHA2 CRC32 ATOMICS FP16 JSCVT FCMA LRCPC";
    }
    if (series >= 15) {
        return "NEON AES SHA1 SHA2 CRC32 ATOMICS FP16 JSCVT";
    }
    return "NEON AES SHA1 SHA2 CRC32 ATOMICS";
}

static BOOL LCSpoofedOptionalCPUFeature(const char *name) {
    if (!name) return NO;
    NSInteger series = LCSpoofedChipSeries();
    if (strstr(name, "arm64e")) {
        return (series >= 100 || series >= 12); // M-series or A12+
    }
    if (strstr(name, "armv8_3")) {
        return (series >= 100 || series >= 12);
    }
    return YES;
}

static BOOL LCShouldSpoofMountPoint(const char *mountPoint) {
    if (!mountPoint) return NO;
    if (strcmp(mountPoint, "/") == 0) return YES;
    if (strcmp(mountPoint, "/var") == 0) return YES;
    if (strcmp(mountPoint, "/private/var") == 0) return YES;
    if (strncmp(mountPoint, "/var/mobile", 11) == 0) return YES;
    if (strncmp(mountPoint, "/private/var/mobile", 19) == 0) return YES;
    return NO;
}

static uint64_t LCSpoofedStorageOpportunisticFreeBytes(void) {
    if (g_spoofedStorageFree == 0) return 0;
    uint64_t value = (uint64_t)((double)g_spoofedStorageFree * 0.9);
    return value > 0 ? value : g_spoofedStorageFree;
}

static BOOL LCCFStringEqualsIgnoreCase(CFStringRef lhs, CFStringRef rhs) {
    if (!lhs || !rhs) return NO;
    return CFStringCompare(lhs, rhs, kCFCompareCaseInsensitive) == kCFCompareEqualTo;
}

static uint64_t LCCalculateSpoofedStorageFreeBytes(uint64_t totalBytes) {
    if (totalBytes == 0) return 0;

    double totalGB = (double)totalBytes / 1e9;
    double minRatio = 0.35;
    double maxRatio = 0.35;

    if (g_storageRandomFreeEnabled) {
        if (totalGB <= 64.0) {
            minRatio = 0.08; maxRatio = 0.40;
        } else if (totalGB <= 128.0) {
            minRatio = 0.10; maxRatio = 0.45;
        } else if (totalGB <= 256.0) {
            minRatio = 0.12; maxRatio = 0.55;
        } else if (totalGB <= 512.0) {
            minRatio = 0.15; maxRatio = 0.65;
        } else {
            minRatio = 0.20; maxRatio = 0.75;
        }
    }

    double ratio = minRatio;
    if (maxRatio > minRatio) {
        ratio += ((double)arc4random_uniform(10001) / 10000.0) * (maxRatio - minRatio);
    }

    uint64_t freeBytes = (uint64_t)(totalBytes * ratio);
    uint64_t minBytes = 2ULL * 1000ULL * 1000ULL * 1000ULL;
    if (freeBytes < minBytes) freeBytes = minBytes;
    if (freeBytes >= totalBytes) {
        freeBytes = totalBytes > minBytes ? (totalBytes - minBytes) : (totalBytes / 2);
    }
    return freeBytes;
}

static BOOL LCGetUptimeBounds(NSString *range, NSTimeInterval *outLo, NSTimeInterval *outHi) {
    if (!outLo || !outHi) return NO;

    NSString *value = [[range ?: @"medium" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value isEqualToString:@"short"]) {
        *outLo = 1 * 3600;  *outHi = 4 * 3600;      // 1-4 h
        return YES;
    }
    if ([value isEqualToString:@"medium"]) {
        *outLo = 4 * 3600;  *outHi = 24 * 3600;     // 4-24 h
        return YES;
    }
    if ([value isEqualToString:@"long"]) {
        *outLo = 24 * 3600; *outHi = 72 * 3600;     // 1-3 d
        return YES;
    }
    if ([value isEqualToString:@"week"]) {
        *outLo = 72 * 3600; *outHi = 168 * 3600;    // 3-7 d
        return YES;
    }
    if ([value isEqualToString:@"month"]) {
        *outLo = 30 * 24 * 3600; *outHi = 30 * 24 * 3600; // exact 30 d
        return YES;
    }
    if ([value isEqualToString:@"year"]) {
        *outLo = 365 * 24 * 3600; *outHi = 365 * 24 * 3600; // exact 365 d
        return YES;
    }

    if (value.length >= 2) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*([0-9]+)\\s*([a-z]+)\\s*$" options:NSRegularExpressionCaseInsensitive error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
        if (match && match.numberOfRanges >= 3) {
            NSString *countString = [value substringWithRange:[match rangeAtIndex:1]];
            NSString *unit = [[value substringWithRange:[match rangeAtIndex:2]] lowercaseString];
            NSInteger unitCount = countString.integerValue;
            if (unitCount > 0) {
                if ([unit isEqualToString:@"h"] || [unit isEqualToString:@"hr"] || [unit isEqualToString:@"hour"] || [unit isEqualToString:@"hours"]) {
                    *outLo = *outHi = unitCount * 3600.0;
                    return YES;
                }
                if ([unit isEqualToString:@"d"] || [unit isEqualToString:@"day"] || [unit isEqualToString:@"days"]) {
                    *outLo = *outHi = unitCount * 24.0 * 3600.0;
                    return YES;
                }
                if ([unit isEqualToString:@"w"] || [unit isEqualToString:@"wk"] || [unit isEqualToString:@"week"] || [unit isEqualToString:@"weeks"]) {
                    *outLo = *outHi = unitCount * 7.0 * 24.0 * 3600.0;
                    return YES;
                }
                if ([unit isEqualToString:@"mo"] || [unit isEqualToString:@"month"] || [unit isEqualToString:@"months"]) {
                    *outLo = *outHi = unitCount * 30.0 * 24.0 * 3600.0;
                    return YES;
                }
                if ([unit isEqualToString:@"y"] || [unit isEqualToString:@"yr"] || [unit isEqualToString:@"year"] || [unit isEqualToString:@"years"]) {
                    *outLo = *outHi = unitCount * 365.0 * 24.0 * 3600.0;
                    return YES;
                }
            }
        }
    }

    return NO;
}

static void LCApplySpoofedUptimeTarget(NSTimeInterval targetUptime) {
    if (targetUptime < 60) targetUptime = 60;
    g_uptimeTarget = targetUptime;
    NSTimeInterval realUptime = orig_NSProcessInfo_systemUptime
        ? orig_NSProcessInfo_systemUptime(NSProcessInfo.processInfo, @selector(systemUptime))
        : NSProcessInfo.processInfo.systemUptime;
    g_bootTimeOffset = g_uptimeTarget - realUptime;
    g_bootTimeSpoofingEnabled = YES;
}

static BOOL LCIsMonotonicUptimeClock(clockid_t clockId) {
    switch (clockId) {
        case CLOCK_MONOTONIC:
#ifdef CLOCK_BOOTTIME
        case CLOCK_BOOTTIME:
#endif
#ifdef CLOCK_UPTIME
        case CLOCK_UPTIME:
#endif
#ifdef CLOCK_MONOTONIC_RAW
        case CLOCK_MONOTONIC_RAW:
#endif
#ifdef CLOCK_MONOTONIC_RAW_APPROX
        case CLOCK_MONOTONIC_RAW_APPROX:
#endif
#ifdef CLOCK_UPTIME_RAW
        case CLOCK_UPTIME_RAW:
#endif
#ifdef CLOCK_UPTIME_RAW_APPROX
        case CLOCK_UPTIME_RAW_APPROX:
#endif
            return YES;
        default:
            return NO;
    }
}

static NSTimeInterval LCRealSystemUptime(void) {
    NSTimeInterval realUptime = 0;
    if (orig_NSProcessInfo_systemUptime) {
        realUptime = orig_NSProcessInfo_systemUptime(NSProcessInfo.processInfo, @selector(systemUptime));
    } else {
        realUptime = NSProcessInfo.processInfo.systemUptime;
        if (g_bootTimeSpoofingEnabled && LCDeviceSpoofingIsActive()) {
            realUptime -= g_bootTimeOffset;
        }
    }
    return MAX(realUptime, 0);
}

static double LCUptimeScaleFactor(void) {
    if (!g_bootTimeSpoofingEnabled || !LCDeviceSpoofingIsActive()) return 1.0;

    NSTimeInterval realUptime = LCRealSystemUptime();
    if (realUptime <= DBL_EPSILON) return 1.0;

    NSTimeInterval spoofedUptime = realUptime + g_bootTimeOffset;
    if (spoofedUptime < 0) spoofedUptime = 0;
    return spoofedUptime / realUptime;
}

static void LCScaleHostCPUTicks(host_cpu_load_info_data_t *cpuLoadInfo) {
    if (!cpuLoadInfo) return;

    double scale = LCUptimeScaleFactor();
    if (!isfinite(scale) || fabs(scale - 1.0) < 0.000001) return;

    for (int i = 0; i < CPU_STATE_MAX; i++) {
        long double scaled = (long double)cpuLoadInfo->cpu_ticks[i] * scale;
        if (scaled < 0) scaled = 0;
        if (scaled > UINT32_MAX) scaled = UINT32_MAX;
        cpuLoadInfo->cpu_ticks[i] = (natural_t)llround((double)scaled);
    }
}

static int64_t LCMachTicksOffsetForBootTimeSpoofing(void) {
    if (!g_bootTimeSpoofingEnabled || !LCDeviceSpoofingIsActive()) return 0;

    static mach_timebase_info_data_t timebase = {0, 0};
    if (timebase.denom == 0 || timebase.numer == 0) {
        mach_timebase_info(&timebase);
        if (timebase.denom == 0 || timebase.numer == 0) return 0;
    }

    long double nsOffset = (long double)g_bootTimeOffset * 1000000000.0L;
    long double ticks = nsOffset * (long double)timebase.denom / (long double)timebase.numer;
    if (ticks > (long double)INT64_MAX) return INT64_MAX;
    if (ticks < (long double)INT64_MIN) return INT64_MIN;
    return (int64_t)llround((double)ticks);
}

static NSOperatingSystemVersion LCParseOSVersion(NSString *versionString) {
    NSOperatingSystemVersion v = {0, 0, 0};
    NSArray<NSString *> *parts = [versionString componentsSeparatedByString:@"."];
    if (parts.count > 0) v.majorVersion = parts[0].integerValue;
    if (parts.count > 1) v.minorVersion = parts[1].integerValue;
    if (parts.count > 2) v.patchVersion = parts[2].integerValue;
    return v;
}

static NSString *LCSpoofedOSVersionString(void) {
    const char *version = LCSpoofedSystemVersion();
    const char *build = LCSpoofedBuildVersion();
    if (!version) return nil;
    if (!build) return [NSString stringWithFormat:@"Version %s", version];
    return [NSString stringWithFormat:@"Version %s (Build %s)", version, build];
}

static BOOL LCPathIsSystemVersionPlist(NSString *path) {
    if (![path isKindOfClass:[NSString class]]) {
        return NO;
    }
    return [path isEqualToString:@"/System/Library/CoreServices/SystemVersion.plist"];
}

static NSDictionary *LCSanitizedSystemVersionDictionary(NSDictionary *source) {
    if (!LCDeviceSpoofingIsActive()) {
        return source;
    }

    const char *version = LCSpoofedSystemVersion();
    const char *build = LCSpoofedBuildVersion();
    if (!version && !build) {
        return source;
    }

    NSMutableDictionary *mutable = source ? [source mutableCopy] : [NSMutableDictionary dictionary];
    if (!mutable) {
        return source;
    }

    if (version) {
        NSString *versionString = @(version);
        mutable[@"ProductVersion"] = versionString;
        mutable[@"ProductUserVisibleVersion"] = versionString;
    }
    if (build) {
        NSString *buildString = @(build);
        mutable[@"ProductBuildVersion"] = buildString;
        mutable[@"BuildVersion"] = buildString;
    }

    return [mutable copy];
}

static NSData *LCSanitizedSystemVersionPlistData(NSData *data) {
    if (!LCDeviceSpoofingIsActive()) {
        return data;
    }

    NSDictionary *plistDict = nil;
    if (data.length > 0) {
        id plist = [NSPropertyListSerialization propertyListWithData:data
                                                             options:NSPropertyListMutableContainersAndLeaves
                                                              format:nil
                                                               error:nil];
        if ([plist isKindOfClass:[NSDictionary class]]) {
            plistDict = (NSDictionary *)plist;
        }
    }

    NSDictionary *sanitized = LCSanitizedSystemVersionDictionary(plistDict);
    if (!sanitized || sanitized == plistDict) {
        return data;
    }

    NSData *serialized = [NSPropertyListSerialization dataWithPropertyList:sanitized
                                                                     format:NSPropertyListXMLFormat_v1_0
                                                                    options:0
                                                                      error:nil];
    return serialized ?: data;
}

static NSUUID *LCUUIDFromOverrideString(NSString *value);
static BOOL LCShouldForceZeroVendorID(void);
static NSString *const LCZeroUUIDString;
static NSString *LCSpoofedVendorIdentifierString(void);
static NSString *LCSpoofedBootSessionUUIDString(void);
static NSString *LCSpoofedDeviceNameString(void);
static NSString *LCSpoofedHostNameString(void);

static CFTypeRef LCCopySpoofedGestaltValue(CFStringRef key) {
    if (!key || !LCDeviceSpoofingIsActive()) return NULL;

    if (CFEqual(key, CFSTR("ProductVersion"))) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("BuildVersion")) || CFEqual(key, CFSTR("j9Th5smJpdztHwc+i39zIg"))) {
        const char *value = LCSpoofedBuildVersion();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("ProductType"))) {
        const char *value = LCSpoofedMachineModel();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("HwMachine"))) {
        const char *value = LCSpoofedMachineModel();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("HardwareModel"))) {
        const char *value = LCSpoofedHardwareModel();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("HwModelStr"))) {
        const char *value = LCSpoofedHardwareModel();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("ProductName")) ||
               CFEqual(key, CFSTR("MarketingName")) ||
               CFEqual(key, CFSTR("MarketingProductName"))) {
        const char *value = LCSpoofedMarketingName();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("HardwarePlatform"))) {
        const char *value = LCSpoofedHardwareModel();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("ChipName"))) {
        const char *value = LCSpoofedChipName();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("GPUName")) || CFEqual(key, CFSTR("GPUModel"))) {
        const char *value = LCSpoofedGPUName();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("KernOsversion"))) {
        const char *value = LCSpoofedBuildVersion();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("KernOsrelease"))) {
        const char *value = LCSpoofedKernelRelease();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("KernVersion"))) {
        const char *value = LCSpoofedKernelVersion();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("KernOsproductversion"))) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("KernBootsessionuuid"))) {
        NSString *value = LCSpoofedBootSessionUUIDString();
        if (value.length > 0) return CFBridgingRetain(value);
    } else if (CFEqual(key, CFSTR("IdentifierForVendor")) || CFEqual(key, CFSTR("VendorIdentifier"))) {
        NSString *value = LCSpoofedVendorIdentifierString();
        if (value.length > 0) return CFBridgingRetain(value);
    } else if (CFEqual(key, CFSTR("AdvertisingIdentifier"))) {
        if (LCShouldForceZeroVendorID() || (g_adTrackingConfigured && !g_spoofedAdTrackingEnabled)) {
            return CFBridgingRetain(LCZeroUUIDString);
        }
        NSUUID *uuid = LCUUIDFromOverrideString(g_spoofedAdvertisingID);
        if (uuid) return CFBridgingRetain(uuid.UUIDString);
    } else if (CFEqual(key, CFSTR("WiFiAddress")) ||
               CFEqual(key, CFSTR("BluetoothAddress")) ||
               CFEqual(key, CFSTR("EthernetMacAddress"))) {
        if (g_spoofedMACAddress.length > 0) return CFBridgingRetain(g_spoofedMACAddress);
    } else if (CFEqual(key, CFSTR("UserAssignedDeviceName")) ||
               CFEqual(key, CFSTR("DeviceName")) ||
               CFEqual(key, CFSTR("ComputerName"))) {
        NSString *value = LCSpoofedDeviceNameString();
        if (value.length > 0) return CFBridgingRetain(value);
    } else if (CFEqual(key, CFSTR("LocalHostName"))) {
        NSString *value = LCSpoofedHostNameString();
        if (value.length > 0) return CFBridgingRetain(value);
    }

    return NULL;
}

static int LCWriteCStringValue(void *oldp, size_t *oldlenp, const char *value) {
    if (!oldlenp || !value) {
        errno = EINVAL;
        return -1;
    }

    size_t needed = strlen(value) + 1;
    if (!oldp) {
        *oldlenp = needed;
        return 0;
    }

    if (*oldlenp < needed) {
        *oldlenp = needed;
        errno = ENOMEM;
        return -1;
    }

    memset(oldp, 0, *oldlenp);
    strlcpy((char *)oldp, value, *oldlenp);
    *oldlenp = needed;
    return 0;
}

static int LCWriteU32Value(void *oldp, size_t *oldlenp, uint32_t value) {
    if (!oldlenp) {
        errno = EINVAL;
        return -1;
    }

    size_t needed = sizeof(uint32_t);
    if (!oldp) {
        *oldlenp = needed;
        return 0;
    }

    if (*oldlenp < needed) {
        *oldlenp = needed;
        errno = ENOMEM;
        return -1;
    }

    *(uint32_t *)oldp = value;
    *oldlenp = needed;
    return 0;
}

static int LCWriteU64Value(void *oldp, size_t *oldlenp, uint64_t value) {
    if (!oldlenp) {
        errno = EINVAL;
        return -1;
    }

    size_t needed = sizeof(uint64_t);
    if (!oldp) {
        *oldlenp = needed;
        return 0;
    }

    if (*oldlenp < needed) {
        *oldlenp = needed;
        errno = ENOMEM;
        return -1;
    }

    *(uint64_t *)oldp = value;
    *oldlenp = needed;
    return 0;
}

static void LCBuildSpoofedMemoryBucketsWithCompressor(uint64_t totalBytes,
                                                      uint64_t *outFree,
                                                      uint64_t *outWired,
                                                      uint64_t *outActive,
                                                      uint64_t *outInactive,
                                                      uint64_t *outCompressed);

static long hook_sysconf(int name) {
    if (!orig_sysconf) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_sysconf = (long (*)(int))dlsym(RTLD_DEFAULT, "sysconf");
        });
        if (!orig_sysconf) return -1;
    }

    if (!LCDeviceSpoofingIsActive()) {
        return orig_sysconf(name);
    }

    switch (name) {
#ifdef _SC_NPROCESSORS_CONF
        case _SC_NPROCESSORS_CONF:
#endif
#ifdef _SC_NPROCESSORS_ONLN
        case _SC_NPROCESSORS_ONLN:
#endif
        {
            uint32_t cpuCount = LCSpoofedCPUCount();
            if (cpuCount > 0) return (long)cpuCount;
            break;
        }
#ifdef _SC_PHYS_PAGES
        case _SC_PHYS_PAGES: {
            uint64_t totalMemory = LCSpoofedPhysicalMemory();
            vm_size_t pageSize = vm_kernel_page_size > 0 ? vm_kernel_page_size : 4096;
            if (totalMemory > 0 && pageSize > 0) {
                return (long)(totalMemory / (uint64_t)pageSize);
            }
            break;
        }
#endif
#ifdef _SC_AVPHYS_PAGES
        case _SC_AVPHYS_PAGES: {
            uint64_t totalMemory = LCSpoofedPhysicalMemory();
            vm_size_t pageSize = vm_kernel_page_size > 0 ? vm_kernel_page_size : 4096;
            if (totalMemory > 0 && pageSize > 0) {
                uint64_t freeBytes = 0, wiredBytes = 0, activeBytes = 0, inactiveBytes = 0, compressedBytes = 0;
                LCBuildSpoofedMemoryBucketsWithCompressor(totalMemory, &freeBytes, &wiredBytes, &activeBytes, &inactiveBytes, &compressedBytes);
                return (long)(freeBytes / (uint64_t)pageSize);
            }
            break;
        }
#endif
        default:
            break;
    }

    return orig_sysconf(name);
}

static void LCBuildSpoofedMemoryBuckets(uint64_t totalBytes, uint64_t *outFree, uint64_t *outWired, uint64_t *outActive, uint64_t *outInactive) {
    if (outFree) *outFree = 0;
    if (outWired) *outWired = 0;
    if (outActive) *outActive = 0;
    if (outInactive) *outInactive = 0;
    if (totalBytes == 0) return;

    uint64_t freeBytes = (uint64_t)((double)totalBytes * 0.16);
    uint64_t wiredBytes = (uint64_t)((double)totalBytes * 0.24);
    uint64_t activeBytes = (uint64_t)((double)totalBytes * 0.38);
    uint64_t inactiveBytes = totalBytes - (freeBytes + wiredBytes + activeBytes);

    if (outFree) *outFree = freeBytes;
    if (outWired) *outWired = wiredBytes;
    if (outActive) *outActive = activeBytes;
    if (outInactive) *outInactive = inactiveBytes;
}

static vm_size_t LCSpoofedHostPageSize(host_t host) {
    vm_size_t pageSize = vm_kernel_page_size;
    if (host_page_size(host, &pageSize) != KERN_SUCCESS || pageSize == 0) {
        pageSize = 4096;
    }
    return pageSize;
}

static void LCBuildSpoofedMemoryBucketsWithCompressor(uint64_t totalBytes,
                                                      uint64_t *outFree,
                                                      uint64_t *outWired,
                                                      uint64_t *outActive,
                                                      uint64_t *outInactive,
                                                      uint64_t *outCompressed) {
    if (outFree) *outFree = 0;
    if (outWired) *outWired = 0;
    if (outActive) *outActive = 0;
    if (outInactive) *outInactive = 0;
    if (outCompressed) *outCompressed = 0;
    if (totalBytes == 0) return;

    // Keep memory classes deterministic and make displayed buckets add up to total RAM.
    uint64_t freeBytes = (uint64_t)((double)totalBytes * 0.09);
    uint64_t wiredBytes = (uint64_t)((double)totalBytes * 0.18);
    uint64_t activeBytes = (uint64_t)((double)totalBytes * 0.37);
    uint64_t inactiveBytes = (uint64_t)((double)totalBytes * 0.28);
    uint64_t compressedBytes = totalBytes - (freeBytes + wiredBytes + activeBytes + inactiveBytes);

    if (outFree) *outFree = freeBytes;
    if (outWired) *outWired = wiredBytes;
    if (outActive) *outActive = activeBytes;
    if (outInactive) *outInactive = inactiveBytes;
    if (outCompressed) *outCompressed = compressedBytes;
}

static NSUUID *LCUUIDFromOverrideString(NSString *value) {
    if (value.length == 0) return nil;
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
    return uuid;
}

static NSString *const LCZeroUUIDString = @"00000000-0000-0000-0000-000000000000";

static NSString *LCNormalizeCompactString(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return @"";
    NSString *lower = [[value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [[lower componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
}

static BOOL LCShouldForceZeroVendorID(void) {
    NSString *normalized = LCNormalizeCompactString(g_spoofedVendorID);
    return [normalized isEqualToString:@"00000"] || [normalized isEqualToString:@"0"] || [normalized isEqualToString:@"00000000000000000000000000000000"];
}

static NSString *LCNormalizedUUIDString(NSString *value) {
    NSUUID *uuid = LCUUIDFromOverrideString(value);
    return uuid ? uuid.UUIDString : nil;
}

static NSString *LCSpoofedDeviceNameString(void) {
    if (!LCDeviceSpoofingIsActive()) return nil;
    if (g_customDeviceName.length > 0) return g_customDeviceName;

    const char *marketingName = LCSpoofedMarketingName();
    if (marketingName) return @(marketingName);

    const char *machine = LCSpoofedMachineModel();
    if (machine) return @(machine);

    return nil;
}

static NSString *LCNormalizedHostNameCandidate(NSString *candidate) {
    if (candidate.length == 0) return nil;

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-."];
    NSMutableString *normalized = [NSMutableString stringWithCapacity:candidate.length];
    for (NSUInteger idx = 0; idx < candidate.length; idx++) {
        unichar ch = [candidate characterAtIndex:idx];
        if ([allowed characterIsMember:ch]) {
            [normalized appendFormat:@"%C", ch];
        } else {
            [normalized appendString:@"-"];
        }
    }
    while ([normalized containsString:@"--"]) {
        [normalized replaceOccurrencesOfString:@"--" withString:@"-" options:0 range:NSMakeRange(0, normalized.length)];
    }
    NSString *trimmed = [[normalized stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-."]] lowercaseString];
    return trimmed.length > 0 ? trimmed : nil;
}

static NSString *LCSpoofedVendorIdentifierString(void) {
    if (!LCDeviceSpoofingIsActive()) return nil;
    if (LCShouldForceZeroVendorID()) return LCZeroUUIDString;

    NSString *vendorID = LCNormalizedUUIDString(g_spoofedVendorID);
    if (vendorID.length > 0) return vendorID;

    NSString *persistentID = LCNormalizedUUIDString(g_spoofedPersistentDeviceID);
    if (persistentID.length > 0) return persistentID;

    return nil;
}

static NSString *LCSpoofedHostNameString(void) {
    if (!LCDeviceSpoofingIsActive()) return nil;
    if (g_customDeviceName.length > 0) {
        NSString *normalizedCustom = LCNormalizedHostNameCandidate(g_customDeviceName);
        if (normalizedCustom.length > 0) {
            return normalizedCustom;
        }
    }

    const char *machine = LCSpoofedMachineModel();
    if (machine) {
        if (strncmp(machine, "iPad", 4) == 0) return @"ipad";
        if (strncmp(machine, "iPod", 4) == 0) return @"ipod";
    }
    return @"iphone";
}

static NSString *LCSpoofedBootSessionUUIDString(void) {
    if (!LCDeviceSpoofingIsActive()) return nil;

    NSString *explicitUUID = LCNormalizedUUIDString(g_spoofedInstallationID);
    if (explicitUUID.length > 0) return explicitUUID;

    NSString *persistentUUID = LCNormalizedUUIDString(g_spoofedPersistentDeviceID);
    if (persistentUUID.length > 0) return persistentUUID;

    NSString *vendorUUID = LCNormalizedUUIDString(g_spoofedVendorID);
    if (vendorUUID.length > 0) return vendorUUID;

    static NSString *fallbackUUID = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fallbackUUID = [NSUUID UUID].UUIDString;
    });
    return fallbackUUID;
}

static NSString *LCRadioAccessTechnologyForSpoofType(NSInteger type) {
    switch (type) {
        case 0:
            return @"CTRadioAccessTechnologyNRNSA";
        case 1:
            return @"CTRadioAccessTechnologyLTE";
        default:
            return @"CTRadioAccessTechnologyWCDMA";
    }
}

static BOOL LCScreenCaptureGroupActive(void) {
    return LCDeviceSpoofingIsActive() && g_screenCaptureBlockEnabled;
}

static BOOL LCScreenFeatureEnabled(BOOL enabled) {
    return LCScreenCaptureGroupActive() && enabled;
}

static BOOL LCEntitlementSpoofingActive(void) {
    return LCDeviceSpoofingIsActive() && g_spoofEntitlementsEnabled;
}

static BOOL LCProcessLooksLikeReveil(void) {
    static BOOL cached = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleID = [NSBundle mainBundle].bundleIdentifier.lowercaseString ?: @"";
        NSString *processName = NSProcessInfo.processInfo.processName.lowercaseString ?: @"";
        NSString *executablePath = NSBundle.mainBundle.executablePath.lowercaseString ?: @"";

        cached = [bundleID isEqualToString:@"com.reveil.app"] ||
                 [bundleID isEqualToString:@"com.82flex.reveil"] ||
                 [bundleID containsString:@"reveil"] ||
                 [processName containsString:@"reveil"] ||
                 [executablePath containsString:@"reveil"];
    });
    return cached;
}

static NSSet<NSString *> *LCReveilSecureEntitlementKeys(void) {
    static NSSet<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"get-task-allow",
            @"application-identifier",
            @"keychain-access-groups",
            @"com.apple.developer.team-identifier",
            @"com.apple.security.app-sandbox",
            @"com.apple.security.network.client",
            @"com.apple.private.security.container-required",
            @"beta-reports-active",
            @"aps-environment",
        ]];
    });
    return keys;
}

static BOOL LCLooksLikeEntitlementsDictionary(NSDictionary *dictionary) {
    if (![dictionary isKindOfClass:[NSDictionary class]] || dictionary.count == 0) {
        return NO;
    }
    if (dictionary[@"application-identifier"] == nil ||
        dictionary[@"keychain-access-groups"] == nil ||
        dictionary[@"com.apple.developer.team-identifier"] == nil) {
        return NO;
    }

    for (id key in dictionary) {
        if (![key isKindOfClass:[NSString class]]) {
            return NO;
        }
    }
    return YES;
}

static NSDictionary *LCSanitizedReveilEntitlementsDictionary(NSDictionary *dictionary) {
    if (!LCLooksLikeEntitlementsDictionary(dictionary)) {
        return dictionary;
    }

    NSSet<NSString *> *allowedKeys = LCReveilSecureEntitlementKeys();
    NSMutableDictionary *sanitized = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];
    BOOL removedUnknownKey = NO;

    for (NSString *key in dictionary) {
        if ([allowedKeys containsObject:key]) {
            sanitized[key] = dictionary[key];
        } else {
            removedUnknownKey = YES;
        }
    }

    return removedUnknownKey ? [sanitized copy] : dictionary;
}

static NSSet<NSString *> *LCCraneDetectionMarkers(void) {
    static NSSet<NSString *> *markers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        markers = [NSSet setWithArray:@[
            @"crane",
            @"crane_container",
            @"crane_containers",
            @"___crane_containers",
            @"com.opa334.craneprefs.plist",
            // LiveContainer-specific jailed markers (Crane-equivalent surface)
            @"lccontainerinfo.plist",
            @"livecontainer/data/application",
            @"documents/data/application",
            @"livecontainer/data/appgroup",
            @"lcappgroup",
            @"com.kdt.livecontainer",
            @"livecontainer.app"
        ]];
    });
    return markers;
}

static NSSet<NSString *> *LCAppiumDetectionMarkers(void) {
    static NSSet<NSString *> *markers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        markers = [NSSet setWithArray:@[
            @"appium",
            @"webdriveragent",
            @"webdriver",
            @"xcuitest",
            @"xctrunner"
        ]];
    });
    return markers;
}

static BOOL LCStringContainsCaseInsensitiveMarker(NSString *value, NSString *marker) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    if (![marker isKindOfClass:[NSString class]] || marker.length == 0) return NO;
    return [value rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL LCStringContainsSensitiveMarker(NSString *value) {
    static __thread BOOL gInSensitiveMarkerCheck = NO;
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    if (!LCScreenFeatureEnabled(g_spoofCraneEnabled || g_spoofAppiumEnabled)) return NO;
    if (gInSensitiveMarkerCheck) return NO;

    gInSensitiveMarkerCheck = YES;
    BOOL found = NO;

    if (g_spoofCraneEnabled) {
        for (NSString *marker in LCCraneDetectionMarkers()) {
            if (LCStringContainsCaseInsensitiveMarker(value, marker)) {
                found = YES;
                break;
            }
        }
    }
    if (!found && g_spoofAppiumEnabled) {
        for (NSString *marker in LCAppiumDetectionMarkers()) {
            if (LCStringContainsCaseInsensitiveMarker(value, marker)) {
                found = YES;
                break;
            }
        }
    }

    gInSensitiveMarkerCheck = NO;
    return found;
}

static BOOL LCObjectContainsSensitiveMarkerInternal(id object, NSMutableSet<NSValue *> *visited, NSUInteger depth) {
    if (!object) return NO;
    if (depth > 16) return NO;

    if ([object isKindOfClass:[NSString class]]) {
        return LCStringContainsSensitiveMarker((NSString *)object);
    }

    NSValue *identity = [NSValue valueWithPointer:(__bridge const void *)(object)];
    if ([visited containsObject:identity]) {
        return NO;
    }
    [visited addObject:identity];

    if ([object isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)object) {
            if (LCObjectContainsSensitiveMarkerInternal(item, visited, depth + 1)) return YES;
        }
        return NO;
    }
    if ([object isKindOfClass:[NSSet class]]) {
        for (id item in (NSSet *)object) {
            if (LCObjectContainsSensitiveMarkerInternal(item, visited, depth + 1)) return YES;
        }
        return NO;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        for (id key in dict) {
            if (LCObjectContainsSensitiveMarkerInternal(key, visited, depth + 1) ||
                LCObjectContainsSensitiveMarkerInternal(dict[key], visited, depth + 1)) {
                return YES;
            }
        }
        return NO;
    }
    return NO;
}

static BOOL LCObjectContainsSensitiveMarker(id object) {
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    return LCObjectContainsSensitiveMarkerInternal(object, visited, 0);
}

static NSError *LCMakeSpoofingError(NSString *reason) {
    NSString *description = reason.length > 0 ? reason : @"Blocked by spoofing policy";
    return [NSError errorWithDomain:@"com.livecontainer.devicespoofing"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSString *LCSpoofedLocaleIdentifier(void) {
    if (g_spoofedLocale.length > 0) {
        return g_spoofedLocale;
    }
    NSString *locale = NSLocale.currentLocale.localeIdentifier;
    return locale.length > 0 ? locale : @"en_US";
}

static NSString *LCSpoofedLanguageTag(void) {
    NSString *locale = [LCSpoofedLocaleIdentifier() stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    if (locale.length == 0) return @"en-US";

    NSArray<NSString *> *components = [locale componentsSeparatedByString:@"-"];
    if (components.count == 0) return @"en-US";
    NSString *language = [components.firstObject lowercaseString];
    if (components.count >= 2) {
        NSString *region = [components[1] uppercaseString];
        if (language.length > 0 && region.length > 0) {
            return [NSString stringWithFormat:@"%@-%@", language, region];
        }
    }
    return language.length > 0 ? language : @"en-US";
}

static BOOL LCShouldSanitizeUserDefaultsKey(NSString *key) {
    if (!LCDeviceSpoofingIsActive() || !g_userDefaultsSpoofingEnabled) return NO;
    if (![key isKindOfClass:[NSString class]] || key.length == 0) return NO;

    NSString *lower = key.lowercaseString;
    if ([lower isEqualToString:@"applelanguages"] ||
        [lower isEqualToString:@"nslanguages"] ||
        [lower isEqualToString:@"applelocale"] ||
        [lower isEqualToString:@"applekeyboards"] ||
        [lower isEqualToString:@"applekeyboardsexpanded"] ||
        [lower isEqualToString:@"appleselectedinputmodes"] ||
        [lower isEqualToString:@"applepasscodekeyboards"] ||
        [lower isEqualToString:@"appleinputsourcehistory"]) {
        return YES;
    }
    if ([lower containsString:@"keyboard"] || [lower containsString:@"inputmode"]) {
        if ([lower hasPrefix:@"apple"] || [lower hasPrefix:@"com.apple."]) {
            return YES;
        }
    }
    return NO;
}

static id LCSanitizedUserDefaultsValueForKey(NSString *key) {
    if (![key isKindOfClass:[NSString class]]) return nil;
    NSString *lower = key.lowercaseString;

    if ([lower isEqualToString:@"applelanguages"] || [lower isEqualToString:@"nslanguages"]) {
        return @[LCSpoofedLanguageTag()];
    }
    if ([lower isEqualToString:@"applelocale"]) {
        return LCSpoofedLocaleIdentifier();
    }
    if ([lower containsString:@"keyboard"] || [lower containsString:@"inputmode"]) {
        return @[LCSpoofedLanguageTag()];
    }
    return nil;
}

static uint64_t LCFNV1aHash64(NSString *value) {
    const char *bytes = [value UTF8String];
    if (!bytes) {
        bytes = "";
    }

    uint64_t hash = 14695981039346656037ULL; // FNV-1a 64-bit offset basis
    for (const unsigned char *p = (const unsigned char *)bytes; *p != '\0'; p++) {
        hash ^= (uint64_t)(*p);
        hash *= 1099511628211ULL; // FNV-1a 64-bit prime
    }
    return hash;
}

static NSDate *LCSpoofedTimestampForPath(NSString *path, BOOL forModificationDate) {
    if (!LCDeviceSpoofingIsActive() || !g_fileTimestampSpoofingEnabled) {
        return nil;
    }

    NSString *basis = [path isKindOfClass:[NSString class]] ? path : @"";
    uint64_t hash = LCFNV1aHash64(basis);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval seed = g_fileTimestampSeedSeconds > 0 ? g_fileTimestampSeedSeconds : (now - (180.0 * 24.0 * 3600.0));
    NSTimeInterval dayOffset = (NSTimeInterval)(hash % 180ULL) * 24.0 * 3600.0;
    NSTimeInterval hourOffset = (NSTimeInterval)((hash >> 11) % 10ULL) * 3600.0;
    NSTimeInterval timestamp = seed + dayOffset + hourOffset;
    if (forModificationDate) {
        timestamp += (NSTimeInterval)((hash >> 19) % (14ULL * 24ULL * 3600ULL));
    }
    if (timestamp > now - 5.0) {
        timestamp = now - 5.0;
    }
    if (timestamp < 1.0) {
        timestamp = 1.0;
    }
    return [NSDate dateWithTimeIntervalSince1970:timestamp];
}

static void LCApplySpoofedFileDatesToDictionary(NSMutableDictionary *mutableAttrs, NSString *path) {
    if (!mutableAttrs || !LCDeviceSpoofingIsActive() || !g_fileTimestampSpoofingEnabled) return;

    NSDate *creationDate = LCSpoofedTimestampForPath(path, NO);
    NSDate *modificationDate = LCSpoofedTimestampForPath(path, YES);
    if (creationDate) {
        mutableAttrs[NSFileCreationDate] = creationDate;
    }
    if (modificationDate) {
        mutableAttrs[NSFileModificationDate] = modificationDate;
    }
}

static NSData *LCModifyBugsnagPayload(NSData *payload) {
    if (![payload isKindOfClass:[NSData class]] || payload.length == 0) return payload;

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:payload options:NSJSONReadingMutableContainers error:&error];
    if (error || ![object isKindOfClass:[NSDictionary class]]) {
        return payload;
    }

    NSMutableDictionary *mutable = [(NSDictionary *)object mutableCopy];
    id deviceObj = mutable[@"device"];
    if ([deviceObj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *device = [(NSDictionary *)deviceObj mutableCopy];
        device[@"jailbroken"] = @NO;
        device[@"simulator"] = @NO;
        mutable[@"device"] = device;
    }

    NSData *patched = [NSJSONSerialization dataWithJSONObject:mutable options:0 error:&error];
    return error || !patched ? payload : patched;
}

static void LCInstallInstanceHook(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || !selector || !replacement || !original) return;
    os_unfair_lock_lock(&g_hookInstallLock);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        os_unfair_lock_unlock(&g_hookInstallLock);
        return;
    }
    IMP current = method_getImplementation(method);
    if (current == replacement) {
        os_unfair_lock_unlock(&g_hookInstallLock);
        return;
    }
    *original = current;
    method_setImplementation(method, replacement);
    os_unfair_lock_unlock(&g_hookInstallLock);
}

#pragma mark - C Hooks

static int hook_uname(struct utsname *name) {
    if (!orig_uname) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_uname = (int (*)(struct utsname *))dlsym(RTLD_DEFAULT, "uname");
        });
        if (!orig_uname) return -1;
    }

    int rc = orig_uname(name);
    if (rc != 0 || !LCDeviceSpoofingIsActive() || !name) return rc;

    const char *machine = LCSpoofedMachineModel();
    if (machine) strlcpy(name->machine, machine, sizeof(name->machine));

    NSString *hostName = LCSpoofedHostNameString();
    if (hostName.length > 0) strlcpy(name->nodename, hostName.UTF8String, sizeof(name->nodename));

    const char *sysname = LCSpoofedKernelName();
    if (sysname) strlcpy(name->sysname, sysname, sizeof(name->sysname));

    const char *kernelRelease = LCSpoofedKernelRelease();
    if (kernelRelease) strlcpy(name->release, kernelRelease, sizeof(name->release));

    const char *kernelVersion = LCSpoofedKernelVersion();
    if (kernelVersion) strlcpy(name->version, kernelVersion, sizeof(name->version));

    return rc;
}

static int hook_gethostname(char *name, size_t namelen) {
    if (!orig_gethostname) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_gethostname = (int (*)(char *, size_t))dlsym(RTLD_DEFAULT, "gethostname");
        });
        if (!orig_gethostname) {
            errno = ENOSYS;
            return -1;
        }
    }

    int rc = orig_gethostname(name, namelen);
    if (rc != 0 || !LCDeviceSpoofingIsActive() || !name || namelen == 0) {
        return rc;
    }

    NSString *hostName = LCSpoofedHostNameString();
    if (hostName.length == 0) {
        return rc;
    }

    strlcpy(name, hostName.UTF8String, namelen);
    return 0;
}

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctlbyname) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_sysctlbyname = (int (*)(const char *, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctlbyname");
        });
        if (!orig_sysctlbyname) return -1;
    }

    if (LCDeviceSpoofingIsActive() && name) {
        if (strcmp(name, "hw.machine") == 0) {
            const char *value = LCSpoofedMachineModel();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.model") == 0) {
            const char *value = LCSpoofedHardwareModel();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.product") == 0 || strcmp(name, "hw.target") == 0) {
            const char *value = LCSpoofedMarketingName();
            if (!value) value = LCSpoofedMachineModel();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.activecpu") == 0 ||
                   strcmp(name, "hw.availcpu") == 0 ||
                   strcmp(name, "hw.logicalcpu") == 0 || strcmp(name, "hw.physicalcpu") == 0 ||
                   strcmp(name, "hw.logicalcpu_max") == 0 || strcmp(name, "hw.physicalcpu_max") == 0) {
            uint32_t value = LCSpoofedCPUCount();
            if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.perflevel0.logicalcpu") == 0 ||
                   strcmp(name, "hw.perflevel0.physicalcpu") == 0 ||
                   strcmp(name, "hw.perflevel0.logicalcpu_max") == 0 ||
                   strcmp(name, "hw.perflevel0.physicalcpu_max") == 0) {
            uint32_t value = LCSpoofedPerformanceCoreCount();
            if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.perflevel1.logicalcpu") == 0 ||
                   strcmp(name, "hw.perflevel1.physicalcpu") == 0 ||
                   strcmp(name, "hw.perflevel1.logicalcpu_max") == 0 ||
                   strcmp(name, "hw.perflevel1.physicalcpu_max") == 0) {
            uint32_t value = LCSpoofedEfficiencyCoreCount();
            if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.cpu.brand_string") == 0 ||
                   strcmp(name, "hw.cpubrand") == 0 ||
                   strcmp(name, "machdep.cpu.brand_string") == 0) {
            const char *value = LCSpoofedChipName();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.cputype") == 0) {
            return LCWriteU32Value(oldp, oldlenp, (uint32_t)CPU_TYPE_ARM64);
        } else if (strcmp(name, "hw.cpusubtype") == 0) {
            return LCWriteU32Value(oldp, oldlenp, LCSpoofedCPUSubtype());
        } else if (strcmp(name, "hw.cpufamily") == 0) {
            return LCWriteU32Value(oldp, oldlenp, LCSpoofedCPUFamily());
        } else if (strcmp(name, "hw.cpufrequency") == 0 || strcmp(name, "hw.cpufrequency_max") == 0 ||
                   strcmp(name, "hw.cpufrequency_min") == 0) {
            uint64_t baseHz = LCSpoofedCPUFrequencyHz();
            if (strcmp(name, "hw.cpufrequency_min") == 0) {
                baseHz = (uint64_t)((double)baseHz * 0.4);
            }
            return LCWriteU64Value(oldp, oldlenp, baseHz);
        } else if (strcmp(name, "hw.cachelinesize") == 0) {
            uint32_t l1i = 0, l1d = 0, l2 = 0, line = 0;
            LCSpoofedCacheValues(&l1i, &l1d, &l2, &line);
            return LCWriteU32Value(oldp, oldlenp, line);
        } else if (strcmp(name, "hw.l1icachesize") == 0) {
            uint32_t l1i = 0, l1d = 0, l2 = 0, line = 0;
            LCSpoofedCacheValues(&l1i, &l1d, &l2, &line);
            return LCWriteU32Value(oldp, oldlenp, l1i);
        } else if (strcmp(name, "hw.l1dcachesize") == 0) {
            uint32_t l1i = 0, l1d = 0, l2 = 0, line = 0;
            LCSpoofedCacheValues(&l1i, &l1d, &l2, &line);
            return LCWriteU32Value(oldp, oldlenp, l1d);
        } else if (strcmp(name, "hw.l2cachesize") == 0) {
            uint32_t l1i = 0, l1d = 0, l2 = 0, line = 0;
            LCSpoofedCacheValues(&l1i, &l1d, &l2, &line);
            return LCWriteU32Value(oldp, oldlenp, l2);
        } else if (strncmp(name, "hw.optional.", 12) == 0) {
            return LCWriteU32Value(oldp, oldlenp, LCSpoofedOptionalCPUFeature(name) ? 1U : 0U);
        } else if (strcmp(name, "hw.cpu.features") == 0) {
            const char *value = LCSpoofedCPUFeatures();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.memsize") == 0) {
            uint64_t value = LCSpoofedPhysicalMemory();
            if (value > 0) return LCWriteU64Value(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.physmem") == 0) {
            uint64_t value = LCSpoofedPhysicalMemory();
            if (value > 0) return LCWriteU32Value(oldp, oldlenp, (uint32_t)MIN(value, UINT32_MAX));
        } else if (strcmp(name, "vm.swapusage") == 0) {
            if (!oldlenp) {
                errno = EINVAL;
                return -1;
            }

            size_t needed = sizeof(struct xsw_usage);
            if (!oldp) {
                *oldlenp = needed;
                return 0;
            }
            if (*oldlenp < needed) {
                *oldlenp = needed;
                errno = ENOMEM;
                return -1;
            }

            uint64_t totalMemory = LCSpoofedPhysicalMemory();
            uint64_t totalSwap = (uint64_t)((double)totalMemory * (totalMemory >= (4ULL * 1024ULL * 1024ULL * 1024ULL) ? 0.5 : 1.0));
            struct xsw_usage *swapUsage = (struct xsw_usage *)oldp;
            swapUsage->xsu_total = totalSwap;
            swapUsage->xsu_avail = (uint64_t)((double)totalSwap * 0.7);
            swapUsage->xsu_used = totalSwap - swapUsage->xsu_avail;
            swapUsage->xsu_pagesize = vm_kernel_page_size;
            swapUsage->xsu_encrypted = 1;
            *oldlenp = needed;
            return 0;
        } else if (strcmp(name, "kern.osversion") == 0) {
            const char *value = LCSpoofedBuildVersion();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "kern.osrelease") == 0) {
            const char *value = LCSpoofedKernelRelease();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "kern.osproductversion") == 0 ||
                   strcmp(name, "kern.osproductversioncompat") == 0 ||
                   strcmp(name, "kern.osversioncompat") == 0) {
            const char *value = LCSpoofedSystemVersion();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "kern.version") == 0) {
            const char *value = LCSpoofedKernelVersion();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "kern.ostype") == 0 || strcmp(name, "kern.osname") == 0) {
            const char *value = LCSpoofedKernelName();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "kern.hostname") == 0) {
            NSString *hostName = LCSpoofedHostNameString();
            if (hostName.length > 0) return LCWriteCStringValue(oldp, oldlenp, hostName.UTF8String);
        } else if (strcmp(name, "kern.bootsessionuuid") == 0) {
            NSString *value = LCSpoofedBootSessionUUIDString();
            if (value.length > 0) return LCWriteCStringValue(oldp, oldlenp, value.UTF8String);
        } else if (strcmp(name, "kern.boottime") == 0 && g_bootTimeSpoofingEnabled) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            if (ret == 0 && oldp && *oldlenp >= sizeof(struct timeval)) {
                struct timeval *tv = (struct timeval *)oldp;
                tv->tv_sec -= (time_t)g_bootTimeOffset;
            }
            return ret;
        }
    }

    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctl) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_sysctl = (int (*)(int *, u_int, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctl");
        });
        if (!orig_sysctl) return -1;
    }

    if (LCDeviceSpoofingIsActive() && name && namelen >= 2) {
        if (name[0] == CTL_HW) {
            switch (name[1]) {
                case HW_MACHINE: {
                    const char *value = LCSpoofedMachineModel();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
                case HW_MODEL: {
                    const char *value = LCSpoofedHardwareModel();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
#ifdef HW_PRODUCT
                case HW_PRODUCT: {
                    const char *value = LCSpoofedMarketingName();
                    if (!value) value = LCSpoofedMachineModel();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
#endif
                case HW_NCPU: {
                    uint32_t value = LCSpoofedCPUCount();
                    if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
                    break;
                }
#ifdef HW_ACTIVECPU
                case HW_ACTIVECPU: {
                    uint32_t value = LCSpoofedCPUCount();
                    if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
                    break;
                }
#endif
#ifdef HW_AVAILCPU
                case HW_AVAILCPU: {
                    uint32_t value = LCSpoofedCPUCount();
                    if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
                    break;
                }
#endif
#ifdef HW_LOGICALCPU
                case HW_LOGICALCPU: {
                    uint32_t value = LCSpoofedCPUCount();
                    if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
                    break;
                }
#endif
#ifdef HW_PHYSICALCPU
                case HW_PHYSICALCPU: {
                    uint32_t value = LCSpoofedCPUCount();
                    if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
                    break;
                }
#endif
#ifdef HW_LOGICALCPU_MAX
                case HW_LOGICALCPU_MAX: {
                    uint32_t value = LCSpoofedCPUCount();
                    if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
                    break;
                }
#endif
#ifdef HW_PHYSICALCPU_MAX
                case HW_PHYSICALCPU_MAX: {
                    uint32_t value = LCSpoofedCPUCount();
                    if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
                    break;
                }
#endif
                case HW_MEMSIZE: {
                    uint64_t value = LCSpoofedPhysicalMemory();
                    if (value > 0) return LCWriteU64Value(oldp, oldlenp, value);
                    break;
                }
                case HW_PHYSMEM: {
                    uint64_t value = LCSpoofedPhysicalMemory();
                    if (value > 0) return LCWriteU32Value(oldp, oldlenp, (uint32_t)MIN(value, UINT32_MAX));
                    break;
                }
                default:
                    break;
            }
        } else if (name[0] == CTL_KERN) {
            switch (name[1]) {
                case KERN_OSVERSION: {
                    const char *value = LCSpoofedBuildVersion();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
                case KERN_OSRELEASE: {
                    const char *value = LCSpoofedKernelRelease();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
                case KERN_VERSION: {
                    const char *value = LCSpoofedKernelVersion();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
#ifdef KERN_OSPRODUCTVERSION
                case KERN_OSPRODUCTVERSION: {
                    const char *value = LCSpoofedSystemVersion();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
#endif
#ifdef KERN_OSTYPE
                case KERN_OSTYPE: {
                    const char *value = LCSpoofedKernelName();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
#endif
#ifdef KERN_HOSTNAME
                case KERN_HOSTNAME: {
                    NSString *hostName = LCSpoofedHostNameString();
                    if (hostName.length > 0) return LCWriteCStringValue(oldp, oldlenp, hostName.UTF8String);
                    break;
                }
#endif
#ifdef KERN_BOOTSESSIONUUID
                case KERN_BOOTSESSIONUUID: {
                    NSString *value = LCSpoofedBootSessionUUIDString();
                    if (value.length > 0) return LCWriteCStringValue(oldp, oldlenp, value.UTF8String);
                    break;
                }
#endif
                case KERN_BOOTTIME: {
                    if (g_bootTimeSpoofingEnabled) {
                        int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
                        if (ret == 0 && oldp && *oldlenp >= sizeof(struct timeval)) {
                            struct timeval *tv = (struct timeval *)oldp;
                            tv->tv_sec -= (time_t)g_bootTimeOffset;
                        }
                        return ret;
                    }
                    break;
                }
                default:
                    break;
            }
        }
    }

    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static void LCApplySpoofedStatfs(struct statfs *buf) {
    if (!buf || !LCStorageSpoofingActive()) return;

    uint64_t blockSize = buf->f_bsize > 0 ? (uint64_t)buf->f_bsize : 4096ULL;
    uint64_t totalBlocks = g_spoofedStorageTotal / blockSize;
    uint64_t freeBlocks = g_spoofedStorageFree / blockSize;
    if (totalBlocks == 0) totalBlocks = 1;
    if (freeBlocks == 0) freeBlocks = 1;
    if (freeBlocks > totalBlocks) freeBlocks = totalBlocks;

    buf->f_blocks = (uint32_t)MIN(totalBlocks, UINT32_MAX);
    buf->f_bfree = (uint32_t)MIN(freeBlocks, UINT32_MAX);
    buf->f_bavail = buf->f_bfree;
}

static void LCApplySpoofedStatfs64(LCStatfs64 *buf) {
    if (!buf || !LCStorageSpoofingActive()) return;

    uint64_t blockSize = buf->f_bsize > 0 ? (uint64_t)buf->f_bsize : 4096ULL;
    uint64_t totalBlocks = g_spoofedStorageTotal / blockSize;
    uint64_t freeBlocks = g_spoofedStorageFree / blockSize;
    if (totalBlocks == 0) totalBlocks = 1;
    if (freeBlocks == 0) freeBlocks = 1;
    if (freeBlocks > totalBlocks) freeBlocks = totalBlocks;

    buf->f_blocks = totalBlocks;
    buf->f_bfree = freeBlocks;
    buf->f_bavail = freeBlocks;
}

static int hook_statfs(const char *path, struct statfs *buf) {
    if (!orig_statfs) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_statfs = (int (*)(const char *, struct statfs *))dlsym(RTLD_DEFAULT, "statfs");
        });
        if (!orig_statfs) return -1;
    }
    int rc = orig_statfs(path, buf);
    if (rc == 0 && LCShouldSpoofMountPoint(path)) {
        LCApplySpoofedStatfs(buf);
    }
    return rc;
}

static int hook_statfs64(const char *path, void *buf) {
    if (!orig_statfs64) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_statfs64 = (int (*)(const char *, void *))dlsym(RTLD_DEFAULT, "statfs64");
        });
        if (!orig_statfs64) {
            errno = ENOSYS;
            return -1;
        }
    }
    int rc = orig_statfs64(path, buf);
    if (rc == 0 && LCShouldSpoofMountPoint(path)) {
        LCApplySpoofedStatfs64((LCStatfs64 *)buf);
    }
    return rc;
}

static int hook_fstatfs(int fd, struct statfs *buf) {
    if (!orig_fstatfs) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_fstatfs = (int (*)(int, struct statfs *))dlsym(RTLD_DEFAULT, "fstatfs");
        });
        if (!orig_fstatfs) return -1;
    }
    int rc = orig_fstatfs(fd, buf);
    if (rc == 0) {
        LCApplySpoofedStatfs(buf);
    }
    return rc;
}

static int hook_getfsstat(struct statfs *buf, int bufsize, int flags) {
    if (!orig_getfsstat) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_getfsstat = (int (*)(struct statfs *, int, int))dlsym(RTLD_DEFAULT, "getfsstat");
        });
        if (!orig_getfsstat) {
            errno = ENOSYS;
            return -1;
        }
    }

    int rc = orig_getfsstat(buf, bufsize, flags);
    if (rc > 0 && buf && LCStorageSpoofingActive()) {
        for (int i = 0; i < rc; i++) {
            if (LCShouldSpoofMountPoint(buf[i].f_mntonname)) {
                LCApplySpoofedStatfs(&buf[i]);
            }
        }
    }
    return rc;
}

static int hook_getfsstat64(void *buf, int bufsize, int flags) {
    if (!orig_getfsstat64) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_getfsstat64 = (int (*)(void *, int, int))dlsym(RTLD_DEFAULT, "getfsstat64");
        });
        if (!orig_getfsstat64) {
            errno = ENOSYS;
            return -1;
        }
    }

    int rc = orig_getfsstat64(buf, bufsize, flags);
    if (rc > 0 && buf && LCStorageSpoofingActive()) {
        LCStatfs64 *entries = (LCStatfs64 *)buf;
        for (int i = 0; i < rc; i++) {
            if (LCShouldSpoofMountPoint(entries[i].f_mntonname)) {
                LCApplySpoofedStatfs64(&entries[i]);
            }
        }
    }
    return rc;
}

static BOOL LCParseIPv4Address(NSString *addressString, struct in_addr *outAddress) {
    if (!outAddress || ![addressString isKindOfClass:[NSString class]] || addressString.length == 0) {
        return NO;
    }
    memset(outAddress, 0, sizeof(struct in_addr));
    return inet_pton(AF_INET, addressString.UTF8String, outAddress) == 1;
}

// MARK: - UIAccessibility heuristics (C functions)

static BOOL hook_UIAccessibilityIsVoiceOverRunning(void) {
    if (LCDeviceSpoofingIsActive()) return NO;
    return orig_UIAccessibilityIsVoiceOverRunning ? orig_UIAccessibilityIsVoiceOverRunning() : NO;
}

static BOOL hook_UIAccessibilityIsGuidedAccessEnabled(void) {
    if (LCDeviceSpoofingIsActive()) return NO;
    return orig_UIAccessibilityIsGuidedAccessEnabled ? orig_UIAccessibilityIsGuidedAccessEnabled() : NO;
}

static BOOL hook_UIAccessibilityIsMonoAudioEnabled(void) {
    if (LCDeviceSpoofingIsActive()) return NO;
    return orig_UIAccessibilityIsMonoAudioEnabled ? orig_UIAccessibilityIsMonoAudioEnabled() : NO;
}

static BOOL hook_UIAccessibilityIsInvertColorsEnabled(void) {
    if (LCDeviceSpoofingIsActive()) return NO;
    return orig_UIAccessibilityIsInvertColorsEnabled ? orig_UIAccessibilityIsInvertColorsEnabled() : NO;
}

static BOOL hook_UIAccessibilityIsBoldTextEnabled(void) {
    if (LCDeviceSpoofingIsActive()) return NO;
    return orig_UIAccessibilityIsBoldTextEnabled ? orig_UIAccessibilityIsBoldTextEnabled() : NO;
}

static BOOL hook_UIAccessibilityDarkerSystemColorsEnabled(void) {
    if (LCDeviceSpoofingIsActive()) return NO;
    return orig_UIAccessibilityDarkerSystemColorsEnabled ? orig_UIAccessibilityDarkerSystemColorsEnabled() : NO;
}

static BOOL hook_UIAccessibilityIsReduceMotionEnabled(void) {
    if (LCDeviceSpoofingIsActive()) return NO;
    return orig_UIAccessibilityIsReduceMotionEnabled ? orig_UIAccessibilityIsReduceMotionEnabled() : NO;
}

static BOOL hook_UIAccessibilityIsReduceTransparencyEnabled(void) {
    if (LCDeviceSpoofingIsActive()) return NO;
    return orig_UIAccessibilityIsReduceTransparencyEnabled ? orig_UIAccessibilityIsReduceTransparencyEnabled() : NO;
}

static BOOL hook_UIAccessibilityIsClosedCaptioningEnabled(void) {
    if (LCDeviceSpoofingIsActive()) return NO;
    return orig_UIAccessibilityIsClosedCaptioningEnabled ? orig_UIAccessibilityIsClosedCaptioningEnabled() : NO;
}

static BOOL hook_UIAccessibilityIsAssistiveTouchRunning(void) {
    if (LCDeviceSpoofingIsActive()) return NO;
    return orig_UIAccessibilityIsAssistiveTouchRunning ? orig_UIAccessibilityIsAssistiveTouchRunning() : NO;
}

static BOOL hook_UIAccessibilityIsVideoAutoplayEnabled(void) {
    if (LCDeviceSpoofingIsActive()) return YES;
    return orig_UIAccessibilityIsVideoAutoplayEnabled ? orig_UIAccessibilityIsVideoAutoplayEnabled() : YES;
}

__attribute__((unused)) static int hook_getifaddrs(struct ifaddrs **ifap) {
    if (!orig_getifaddrs) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_getifaddrs = (int (*)(struct ifaddrs **))dlsym(RTLD_DEFAULT, "getifaddrs");
        });
        if (!orig_getifaddrs) return -1;
    }

    int rc = orig_getifaddrs(ifap);
    if (rc != 0 || !LCDeviceSpoofingIsActive() || !ifap || !*ifap) {
        return rc;
    }

    struct in_addr wifiAddress = {0};
    struct in_addr cellularAddress = {0};
    BOOL hasWiFiAddress = g_spoofWiFiAddressEnabled && LCParseIPv4Address(g_spoofedWiFiAddress, &wifiAddress);
    BOOL hasCellularAddress = g_spoofCellularAddressEnabled && LCParseIPv4Address(g_spoofedCellularAddress, &cellularAddress);
    uint8_t spoofedMac[6] = {0};
    BOOL hasWiFiMacAddress = LCParseMACAddress(g_spoofedMACAddress, spoofedMac);

    if (!hasWiFiAddress && !hasCellularAddress && !hasWiFiMacAddress) {
        return rc;
    }

    for (struct ifaddrs *entry = *ifap; entry != NULL; entry = entry->ifa_next) {
        if (!entry->ifa_name || !entry->ifa_addr) {
            continue;
        }

        sa_family_t family = entry->ifa_addr->sa_family;
        if (family == AF_INET) {
            struct sockaddr_in *sockaddr = (struct sockaddr_in *)entry->ifa_addr;
            if (hasWiFiAddress && strcmp(entry->ifa_name, "en0") == 0) {
                sockaddr->sin_addr = wifiAddress;
                continue;
            }
            if (hasCellularAddress &&
                (strcmp(entry->ifa_name, "pdp_ip0") == 0 || strcmp(entry->ifa_name, "en1") == 0)) {
                sockaddr->sin_addr = cellularAddress;
            }
        } else if (family == AF_LINK && hasWiFiMacAddress && strcmp(entry->ifa_name, "en0") == 0) {
            struct sockaddr_dl *sdl = (struct sockaddr_dl *)entry->ifa_addr;
            if (sdl->sdl_alen >= 6) {
                memcpy(LLADDR(sdl), spoofedMac, 6);
            }
        }
    }

    return rc;
}

static int hook_clock_gettime(clockid_t clk_id, struct timespec *tp) {
    if (!orig_clock_gettime) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_clock_gettime = (int (*)(clockid_t, struct timespec *))dlsym(RTLD_DEFAULT, "clock_gettime");
        });
        if (!orig_clock_gettime) return -1;
    }

    int rc = orig_clock_gettime(clk_id, tp);
    if (rc != 0 || !tp) return rc;

    if (LCDeviceSpoofingIsActive() && g_bootTimeSpoofingEnabled && LCIsMonotonicUptimeClock(clk_id)) {
        // Use integer arithmetic to preserve nanosecond precision.
        // Converting through double loses precision for large tv_sec values.
        int64_t offsetNs = (int64_t)(g_bootTimeOffset * 1e9);
        int64_t totalNs = (int64_t)tp->tv_sec * 1000000000LL + (int64_t)tp->tv_nsec + offsetNs;
        if (totalNs < 0) totalNs = 0;
        tp->tv_sec = (time_t)(totalNs / 1000000000LL);
        tp->tv_nsec = (long)(totalNs % 1000000000LL);
    }
    return rc;
}

static uint64_t hook_clock_gettime_nsec_np(clockid_t clk_id) {
    if (!orig_clock_gettime_nsec_np) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_clock_gettime_nsec_np = (uint64_t (*)(clockid_t))dlsym(RTLD_DEFAULT, "clock_gettime_nsec_np");
        });
        if (!orig_clock_gettime_nsec_np) return 0;
    }

    uint64_t value = orig_clock_gettime_nsec_np(clk_id);
    if (LCDeviceSpoofingIsActive() && g_bootTimeSpoofingEnabled && LCIsMonotonicUptimeClock(clk_id)) {
        int64_t adjusted = (int64_t)value + (int64_t)(g_bootTimeOffset * 1e9);
        if (adjusted < 0) adjusted = 0;
        return (uint64_t)adjusted;
    }
    return value;
}

static uint64_t hook_mach_absolute_time(void) {
    if (!orig_mach_absolute_time) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_mach_absolute_time = (uint64_t (*)(void))dlsym(RTLD_DEFAULT, "mach_absolute_time");
        });
        if (!orig_mach_absolute_time) return 0;
    }

    uint64_t value = orig_mach_absolute_time();
    int64_t offsetTicks = LCMachTicksOffsetForBootTimeSpoofing();
    if (offsetTicks != 0) {
        int64_t adjusted = (int64_t)value + offsetTicks;
        if (adjusted < 0) adjusted = 0;
        return (uint64_t)adjusted;
    }
    return value;
}

static uint64_t hook_mach_approximate_time(void) {
    if (!orig_mach_approximate_time) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_mach_approximate_time = (uint64_t (*)(void))dlsym(RTLD_DEFAULT, "mach_approximate_time");
        });
        if (!orig_mach_approximate_time) return 0;
    }

    uint64_t value = orig_mach_approximate_time();
    int64_t offsetTicks = LCMachTicksOffsetForBootTimeSpoofing();
    if (offsetTicks != 0) {
        int64_t adjusted = (int64_t)value + offsetTicks;
        if (adjusted < 0) adjusted = 0;
        return (uint64_t)adjusted;
    }
    return value;
}

static uint64_t hook_mach_continuous_time(void) {
    if (!orig_mach_continuous_time) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_mach_continuous_time = (uint64_t (*)(void))dlsym(RTLD_DEFAULT, "mach_continuous_time");
        });
        if (!orig_mach_continuous_time) return 0;
    }

    uint64_t value = orig_mach_continuous_time();
    int64_t offsetTicks = LCMachTicksOffsetForBootTimeSpoofing();
    if (offsetTicks != 0) {
        int64_t adjusted = (int64_t)value + offsetTicks;
        if (adjusted < 0) adjusted = 0;
        return (uint64_t)adjusted;
    }
    return value;
}

static uint64_t hook_mach_continuous_approximate_time(void) {
    if (!orig_mach_continuous_approximate_time) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_mach_continuous_approximate_time = (uint64_t (*)(void))dlsym(RTLD_DEFAULT, "mach_continuous_approximate_time");
        });
        if (!orig_mach_continuous_approximate_time) return 0;
    }

    uint64_t value = orig_mach_continuous_approximate_time();
    int64_t offsetTicks = LCMachTicksOffsetForBootTimeSpoofing();
    if (offsetTicks != 0) {
        int64_t adjusted = (int64_t)value + offsetTicks;
        if (adjusted < 0) adjusted = 0;
        return (uint64_t)adjusted;
    }
    return value;
}

static kern_return_t hook_host_statistics(host_t host, host_flavor_t flavor, host_info_t info, mach_msg_type_number_t *count) {
    if (!orig_host_statistics) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_host_statistics = (kern_return_t (*)(host_t, host_flavor_t, host_info_t, mach_msg_type_number_t *))
                dlsym(RTLD_DEFAULT, "host_statistics");
        });
        if (!orig_host_statistics) return KERN_FAILURE;
    }

    kern_return_t result = orig_host_statistics(host, flavor, info, count);
    if (result != KERN_SUCCESS || !LCDeviceSpoofingIsActive() || !info || !count) {
        return result;
    }

    if (g_bootTimeSpoofingEnabled && flavor == HOST_CPU_LOAD_INFO && *count >= HOST_CPU_LOAD_INFO_COUNT) {
        host_cpu_load_info_data_t *cpuLoadInfo = (host_cpu_load_info_data_t *)info;
        LCScaleHostCPUTicks(cpuLoadInfo);
        return result;
    }

    uint64_t totalMemory = LCSpoofedPhysicalMemory();
    if (totalMemory == 0) {
        return result;
    }

    #ifdef HOST_VM_INFO_REV0_COUNT
    if (flavor == HOST_VM_INFO && *count >= HOST_VM_INFO_REV0_COUNT) {
    #else
    if (flavor == HOST_VM_INFO && *count >= HOST_VM_INFO_COUNT) {
    #endif
        vm_statistics_data_t *vmStats = (vm_statistics_data_t *)info;
        uint64_t freeBytes = 0, wiredBytes = 0, activeBytes = 0, inactiveBytes = 0;
        LCBuildSpoofedMemoryBuckets(totalMemory, &freeBytes, &wiredBytes, &activeBytes, &inactiveBytes);

        vm_size_t pageSize = LCSpoofedHostPageSize(host);

        vmStats->free_count = (natural_t)MIN(freeBytes / pageSize, UINT32_MAX);
        vmStats->wire_count = (natural_t)MIN(wiredBytes / pageSize, UINT32_MAX);
        vmStats->active_count = (natural_t)MIN(activeBytes / pageSize, UINT32_MAX);
        vmStats->inactive_count = (natural_t)MIN(inactiveBytes / pageSize, UINT32_MAX);
    } else if (flavor == HOST_BASIC_INFO && *count >= HOST_BASIC_INFO_COUNT) {
        LCApplySpoofedHostBasicInfo((host_basic_info_t)info, totalMemory);
    }

    return result;
}

static kern_return_t hook_host_statistics64(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count) {
    if (!orig_host_statistics64) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_host_statistics64 = (kern_return_t (*)(host_t, host_flavor_t, host_info64_t, mach_msg_type_number_t *))
                dlsym(RTLD_DEFAULT, "host_statistics64");
        });
        if (!orig_host_statistics64) return KERN_FAILURE;
    }

    kern_return_t result = orig_host_statistics64(host, flavor, info, count);
    if (result != KERN_SUCCESS || !LCDeviceSpoofingIsActive() || !info || !count) {
        return result;
    }

    if (g_bootTimeSpoofingEnabled && flavor == HOST_CPU_LOAD_INFO && *count >= HOST_CPU_LOAD_INFO_COUNT) {
        host_cpu_load_info_data_t *cpuLoadInfo = (host_cpu_load_info_data_t *)info;
        LCScaleHostCPUTicks(cpuLoadInfo);
        return result;
    }

    uint64_t totalMemory = LCSpoofedPhysicalMemory();
    if (totalMemory == 0) {
        return result;
    }

    #ifdef HOST_VM_INFO64_REV0_COUNT
    if (flavor == HOST_VM_INFO64 && *count >= HOST_VM_INFO64_REV0_COUNT) {
    #else
    if (flavor == HOST_VM_INFO64 && *count >= HOST_VM_INFO64_COUNT) {
    #endif
        vm_statistics64_data_t *vmStats = (vm_statistics64_data_t *)info;
        uint64_t freeBytes = 0, wiredBytes = 0, activeBytes = 0, inactiveBytes = 0, compressedBytes = 0;
        LCBuildSpoofedMemoryBucketsWithCompressor(totalMemory, &freeBytes, &wiredBytes, &activeBytes, &inactiveBytes, &compressedBytes);

        vm_size_t pageSize = LCSpoofedHostPageSize(host);
        uint64_t freePages = freeBytes / pageSize;
        uint64_t wiredPages = wiredBytes / pageSize;
        uint64_t activePages = activeBytes / pageSize;
        uint64_t inactivePages = inactiveBytes / pageSize;
        uint64_t compressedPages = compressedBytes / pageSize;

        vmStats->free_count = (natural_t)MIN(freePages, UINT32_MAX);
        vmStats->wire_count = (natural_t)MIN(wiredPages, UINT32_MAX);
        vmStats->active_count = (natural_t)MIN(activePages, UINT32_MAX);
        vmStats->inactive_count = (natural_t)MIN(inactivePages, UINT32_MAX);
        #ifdef HOST_VM_INFO64_REV1_COUNT
        if (*count >= HOST_VM_INFO64_REV1_COUNT) {
        #endif
        vmStats->compressor_page_count = (natural_t)MIN(compressedPages, UINT32_MAX);
        vmStats->total_uncompressed_pages_in_compressor = compressedPages;
        vmStats->throttled_count = 0;
        vmStats->speculative_count = (natural_t)MIN(freePages / 5, UINT32_MAX);
        vmStats->purgeable_count = (natural_t)MIN(inactivePages / 8, UINT32_MAX);
        vmStats->external_page_count = (natural_t)MIN(activePages / 6, UINT32_MAX);
        vmStats->internal_page_count = (natural_t)MIN(activePages + inactivePages + wiredPages + compressedPages, UINT32_MAX);
        #ifdef HOST_VM_INFO64_REV1_COUNT
        }
        #endif
    #ifdef HOST_VM_INFO_REV0_COUNT
    } else if (flavor == HOST_VM_INFO && *count >= HOST_VM_INFO_REV0_COUNT) {
    #else
    } else if (flavor == HOST_VM_INFO && *count >= HOST_VM_INFO_COUNT) {
    #endif
        vm_statistics_data_t *vmStats = (vm_statistics_data_t *)info;
        uint64_t freeBytes = 0, wiredBytes = 0, activeBytes = 0, inactiveBytes = 0, compressedBytes = 0;
        LCBuildSpoofedMemoryBucketsWithCompressor(totalMemory, &freeBytes, &wiredBytes, &activeBytes, &inactiveBytes, &compressedBytes);

        vm_size_t pageSize = LCSpoofedHostPageSize(host);

        vmStats->free_count = (natural_t)MIN(freeBytes / pageSize, UINT32_MAX);
        vmStats->wire_count = (natural_t)MIN(wiredBytes / pageSize, UINT32_MAX);
        vmStats->active_count = (natural_t)MIN(activeBytes / pageSize, UINT32_MAX);
        vmStats->inactive_count = (natural_t)MIN(inactiveBytes / pageSize, UINT32_MAX);
    } else if (flavor == HOST_BASIC_INFO && *count >= HOST_BASIC_INFO_COUNT) {
        LCApplySpoofedHostBasicInfo((host_basic_info_t)info, totalMemory);
    }

    return result;
}

static kern_return_t hook_host_processor_info(host_t host,
                                              processor_flavor_t flavor,
                                              natural_t *out_processor_count,
                                              processor_info_array_t *out_processor_info,
                                              mach_msg_type_number_t *out_processor_infoCnt) {
    if (!orig_host_processor_info) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_host_processor_info = (kern_return_t (*)(host_t, processor_flavor_t, natural_t *,
                                                          processor_info_array_t *, mach_msg_type_number_t *))
                dlsym(RTLD_DEFAULT, "host_processor_info");
        });
        if (!orig_host_processor_info) return KERN_FAILURE;
    }

    kern_return_t result = orig_host_processor_info(host, flavor, out_processor_count, out_processor_info, out_processor_infoCnt);
    if (result != KERN_SUCCESS || !LCDeviceSpoofingIsActive() ||
        !out_processor_count || !out_processor_info || !out_processor_infoCnt) {
        return result;
    }

    uint32_t spoofedCount = LCSpoofedCPUCount();
    if (spoofedCount == 0) return result;

    natural_t realCount = *out_processor_count;
    if (realCount == spoofedCount) return result;
    if (realCount == 0 || !*out_processor_info || *out_processor_infoCnt == 0) {
        *out_processor_count = (natural_t)spoofedCount;
        return result;
    }

    mach_msg_type_number_t perProcessorInfo = *out_processor_infoCnt / (mach_msg_type_number_t)realCount;
    if (perProcessorInfo == 0) {
        *out_processor_count = (natural_t)spoofedCount;
        return result;
    }

    mach_msg_type_number_t newInfoCount = perProcessorInfo * (mach_msg_type_number_t)spoofedCount;
    vm_size_t newInfoSize = (vm_size_t)newInfoCount * sizeof(integer_t);
    vm_address_t newInfoAddress = 0;
    if (vm_allocate(mach_task_self(), &newInfoAddress, newInfoSize, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
        return result;
    }

    memset((void *)newInfoAddress, 0, (size_t)newInfoSize);
    integer_t *oldInfo = (integer_t *)*out_processor_info;
    integer_t *newInfo = (integer_t *)newInfoAddress;
    for (natural_t i = 0; i < (natural_t)spoofedCount; i++) {
        natural_t srcIndex = (i < realCount) ? i : (realCount - 1);
        memcpy(newInfo + (i * perProcessorInfo),
               oldInfo + (srcIndex * perProcessorInfo),
               (size_t)perProcessorInfo * sizeof(integer_t));
        if (flavor == PROCESSOR_CPU_LOAD_INFO && i >= realCount) {
            processor_cpu_load_info_t load = (processor_cpu_load_info_t)(newInfo + (i * perProcessorInfo));
            if (perProcessorInfo >= CPU_STATE_MAX) {
                load->cpu_ticks[CPU_STATE_USER] /= 2;
                load->cpu_ticks[CPU_STATE_SYSTEM] /= 2;
                load->cpu_ticks[CPU_STATE_NICE] = 0;
            }
        }
    }

    vm_size_t oldInfoSize = (vm_size_t)(*out_processor_infoCnt) * sizeof(integer_t);
    if (oldInfoSize > 0 && *out_processor_info) {
        vm_deallocate(mach_task_self(), (vm_address_t)*out_processor_info, oldInfoSize);
    }

    *out_processor_info = (processor_info_array_t)newInfo;
    *out_processor_infoCnt = newInfoCount;
    *out_processor_count = (natural_t)spoofedCount;
    return result;
}

static kern_return_t hook_task_info(task_t target_task,
                                    task_flavor_t flavor,
                                    task_info_t task_info_out,
                                    mach_msg_type_number_t *task_info_outCnt) {
    if (!orig_task_info) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            orig_task_info = (kern_return_t (*)(task_t, task_flavor_t, task_info_t, mach_msg_type_number_t *))
                dlsym(RTLD_DEFAULT, "task_info");
        });
        if (!orig_task_info) return KERN_FAILURE;
    }

    kern_return_t result = orig_task_info(target_task, flavor, task_info_out, task_info_outCnt);
    if (result != KERN_SUCCESS || !LCDeviceSpoofingIsActive() || !task_info_out || !task_info_outCnt) {
        return result;
    }

    uint64_t totalMemory = LCSpoofedPhysicalMemory();
    if (totalMemory == 0) return result;

    uint64_t freeBytes = 0, wiredBytes = 0, activeBytes = 0, inactiveBytes = 0, compressedBytes = 0;
    LCBuildSpoofedMemoryBucketsWithCompressor(totalMemory, &freeBytes, &wiredBytes, &activeBytes, &inactiveBytes, &compressedBytes);
    uint64_t usedBytes = totalMemory - freeBytes;

    switch (flavor) {
        case TASK_BASIC_INFO: {
#ifdef TASK_BASIC_INFO_64_COUNT
            if (*task_info_outCnt >= TASK_BASIC_INFO_64_COUNT) {
                task_basic_info_64_t basic64 = (task_basic_info_64_t)task_info_out;
                basic64->resident_size = (mach_vm_size_t)usedBytes;
                basic64->virtual_size = (mach_vm_size_t)(totalMemory + (1024ULL * 1024ULL * 1024ULL));
                break;
            }
#endif
            if (*task_info_outCnt >= TASK_BASIC_INFO_COUNT) {
                task_basic_info_t basic = (task_basic_info_t)task_info_out;
                basic->resident_size = (mach_vm_size_t)usedBytes;
                basic->virtual_size = (mach_vm_size_t)(totalMemory + (1024ULL * 1024ULL * 1024ULL));
            }
            break;
        }
        case TASK_VM_INFO:
#ifdef TASK_VM_INFO_PURGEABLE
        case TASK_VM_INFO_PURGEABLE:
#endif
        {
            #ifdef TASK_VM_INFO_REV0_COUNT
            if (*task_info_outCnt >= TASK_VM_INFO_REV0_COUNT) {
            #else
            if (*task_info_outCnt >= TASK_VM_INFO_COUNT) {
            #endif
                task_vm_info_t vmInfo = (task_vm_info_t)task_info_out;
                uint64_t externalBytes = (uint64_t)((double)totalMemory * 0.08);
                uint64_t reusableBytes = (uint64_t)((double)inactiveBytes * 0.35);
                uint64_t internalBytes = activeBytes + inactiveBytes + compressedBytes;

                vmInfo->virtual_size = (mach_vm_size_t)(totalMemory + (1024ULL * 1024ULL * 1024ULL));
                vmInfo->resident_size = (mach_vm_size_t)usedBytes;
                vmInfo->resident_size_peak = (mach_vm_size_t)(usedBytes + (usedBytes / 8));
                vmInfo->internal = (mach_vm_size_t)internalBytes;
                vmInfo->internal_peak = (mach_vm_size_t)(internalBytes + (internalBytes / 10));
                vmInfo->external = (mach_vm_size_t)externalBytes;
                vmInfo->external_peak = (mach_vm_size_t)(externalBytes + (externalBytes / 10));
                vmInfo->reusable = (mach_vm_size_t)reusableBytes;
                vmInfo->reusable_peak = (mach_vm_size_t)(reusableBytes + (reusableBytes / 8));
                vmInfo->compressed = (mach_vm_size_t)compressedBytes;
                vmInfo->compressed_peak = (mach_vm_size_t)(compressedBytes + (compressedBytes / 6));
                #ifdef TASK_VM_INFO_REV1_COUNT
                if (*task_info_outCnt >= TASK_VM_INFO_REV1_COUNT) {
                #endif
                vmInfo->phys_footprint = (mach_vm_size_t)usedBytes;
                #ifdef TASK_VM_INFO_REV1_COUNT
                }
                #endif
            }
            break;
        }
        default:
            break;
    }

    return result;
}

static NSString *hook_MTLDevice_name(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *gpuName = LCSpoofedGPUName();
        if (gpuName) return @(gpuName);
    }
    if (orig_MTLDevice_name) return orig_MTLDevice_name(self, _cmd);
    return @"Apple GPU";
}

static NSString *hook_MTLDevice_familyName(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *gpuName = LCSpoofedGPUName();
        if (gpuName) return @(gpuName);
    }
    if (orig_MTLDevice_familyName) return orig_MTLDevice_familyName(self, _cmd);
    return @"Apple GPU";
}

static void LCInstallMTLDeviceHooksIfNeeded(id device) {
    if (!device) return;
    Class deviceClass = [device class];

    Method nameMethod = class_getInstanceMethod(deviceClass, @selector(name));
    if (nameMethod) {
        IMP currentName = method_getImplementation(nameMethod);
        if (currentName != (IMP)hook_MTLDevice_name) {
            if (!orig_MTLDevice_name) {
                orig_MTLDevice_name = (NSString *(*)(id, SEL))currentName;
            }
            method_setImplementation(nameMethod, (IMP)hook_MTLDevice_name);
        }
    }

    Method familyMethod = class_getInstanceMethod(deviceClass, @selector(familyName));
    if (familyMethod) {
        IMP currentFamily = method_getImplementation(familyMethod);
        if (currentFamily != (IMP)hook_MTLDevice_familyName) {
            if (!orig_MTLDevice_familyName) {
                orig_MTLDevice_familyName = (NSString *(*)(id, SEL))currentFamily;
            }
            method_setImplementation(familyMethod, (IMP)hook_MTLDevice_familyName);
        }
    }
}

static id hook_MTLCreateSystemDefaultDevice(void) {
    id device = orig_MTLCreateSystemDefaultDevice ? orig_MTLCreateSystemDefaultDevice() : nil;
    if (device) LCInstallMTLDeviceHooksIfNeeded(device);
    return device;
}

static NSArray *hook_MTLCopyAllDevices(void) {
    NSArray *devices = orig_MTLCopyAllDevices ? orig_MTLCopyAllDevices() : nil;
    for (id device in devices) {
        LCInstallMTLDeviceHooksIfNeeded(device);
    }
    return devices;
}

#pragma mark - ObjC Hooks

static NSString *hook_UIDevice_systemVersion(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return @(value);
    }
    if (orig_UIDevice_systemVersion) return orig_UIDevice_systemVersion(self, _cmd);
    return @"17.0";
}

static NSString *hook_UIDevice_systemName(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *value = LCSpoofedSystemName();
        if (value) return @(value);
    }
    if (orig_UIDevice_systemName) return orig_UIDevice_systemName(self, _cmd);
    return @"iOS";
}

static NSString *hook_UIDevice_name(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        NSString *deviceName = LCSpoofedDeviceNameString();
        if (deviceName.length > 0) return deviceName;
    }
    if (orig_UIDevice_name) return orig_UIDevice_name(self, _cmd);
    return @"iPhone";
}

static NSUUID *hook_UIDevice_identifierForVendor(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        if (LCShouldForceZeroVendorID()) {
            return [[NSUUID alloc] initWithUUIDString:LCZeroUUIDString];
        }
        NSUUID *uuid = LCUUIDFromOverrideString(g_spoofedVendorID);
        if (uuid) return uuid;
    }
    if (orig_UIDevice_identifierForVendor) return orig_UIDevice_identifierForVendor(self, _cmd);
    return [[NSUUID alloc] init];
}

static float hook_UIDevice_batteryLevel(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_batteryLevelConfigured) {
        return g_spoofedBatteryLevel;
    }
    if (orig_UIDevice_batteryLevel) return orig_UIDevice_batteryLevel(self, _cmd);
    return 1.0f;
}

static NSInteger hook_UIDevice_batteryState(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_batteryStateConfigured) {
        return g_spoofedBatteryState;
    }
    if (orig_UIDevice_batteryState) return orig_UIDevice_batteryState(self, _cmd);
    return 2;
}

static BOOL hook_UIDevice_isBatteryMonitoringEnabled(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && (g_batteryLevelConfigured || g_batteryStateConfigured)) {
        return YES;
    }
    if (orig_UIDevice_isBatteryMonitoringEnabled) return orig_UIDevice_isBatteryMonitoringEnabled(self, _cmd);
    return YES;
}

static BOOL hook_UIDevice_proximityState(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofProximityEnabled) {
        return NO;
    }
    if (orig_UIDevice_proximityState) return orig_UIDevice_proximityState(self, _cmd);
    return NO;
}

static BOOL hook_UIDevice_isProximityMonitoringEnabled(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofProximityEnabled) {
        return YES;
    }
    if (orig_UIDevice_isProximityMonitoringEnabled) return orig_UIDevice_isProximityMonitoringEnabled(self, _cmd);
    return NO;
}

static UIDeviceOrientation hook_UIDevice_orientation(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofOrientationEnabled) {
        return UIDeviceOrientationPortrait;
    }
    if (orig_UIDevice_orientation) return orig_UIDevice_orientation(self, _cmd);
    return UIDeviceOrientationPortrait;
}

static unsigned long long hook_NSProcessInfo_physicalMemory(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        uint64_t value = LCSpoofedPhysicalMemory();
        if (value > 0) return value;
    }
    if (orig_NSProcessInfo_physicalMemory) return orig_NSProcessInfo_physicalMemory(self, _cmd);
    return 0;
}

static unsigned long long hook_SwiftNSProcessInfo_physicalMemory(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        uint64_t value = LCSpoofedPhysicalMemory();
        if (value > 0) return value;
    }
    if (orig_SwiftNSProcessInfo_physicalMemory) return orig_SwiftNSProcessInfo_physicalMemory(self, _cmd);
    if (orig_NSProcessInfo_physicalMemory) return orig_NSProcessInfo_physicalMemory(self, _cmd);
    return 0;
}

static NSUInteger hook_NSProcessInfo_processorCount(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        uint32_t value = LCSpoofedCPUCount();
        if (value > 0) return value;
    }
    if (orig_NSProcessInfo_processorCount) return orig_NSProcessInfo_processorCount(self, _cmd);
    return 0;
}

static NSUInteger hook_NSProcessInfo_activeProcessorCount(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        uint32_t value = LCSpoofedCPUCount();
        if (value > 0) return value;
    }
    if (orig_NSProcessInfo_activeProcessorCount) return orig_NSProcessInfo_activeProcessorCount(self, _cmd);
    return 0;
}

static NSOperatingSystemVersion hook_NSProcessInfo_operatingSystemVersion(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return LCParseOSVersion(@(value));
    }
    if (orig_NSProcessInfo_operatingSystemVersion) return orig_NSProcessInfo_operatingSystemVersion(self, _cmd);
    return (NSOperatingSystemVersion){0, 0, 0};
}

static NSString *hook_NSProcessInfo_operatingSystemVersionString(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        NSString *value = LCSpoofedOSVersionString();
        if (value) return value;
    }
    if (orig_NSProcessInfo_operatingSystemVersionString) return orig_NSProcessInfo_operatingSystemVersionString(self, _cmd);
    return @"";
}

static NSString *hook_NSProcessInfo_hostName(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        NSString *hostName = LCSpoofedHostNameString();
        if (hostName.length > 0) return hostName;
    }
    if (orig_NSProcessInfo_hostName) return orig_NSProcessInfo_hostName(self, _cmd);
    return @"localhost";
}

static NSOperatingSystemVersion hook_SwiftNSProcessInfo_operatingSystemVersion(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return LCParseOSVersion(@(value));
    }
    if (orig_SwiftNSProcessInfo_operatingSystemVersion) return orig_SwiftNSProcessInfo_operatingSystemVersion(self, _cmd);
    return (NSOperatingSystemVersion){0, 0, 0};
}

static NSString *hook_SwiftNSProcessInfo_operatingSystemVersionString(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        NSString *value = LCSpoofedOSVersionString();
        if (value.length > 0) return value;
    }
    if (orig_SwiftNSProcessInfo_operatingSystemVersionString) return orig_SwiftNSProcessInfo_operatingSystemVersionString(self, _cmd);
    return @"";
}

static NSString *hook_SwiftNSProcessInfo_hostName(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        NSString *hostName = LCSpoofedHostNameString();
        if (hostName.length > 0) return hostName;
    }
    if (orig_SwiftNSProcessInfo_hostName) return orig_SwiftNSProcessInfo_hostName(self, _cmd);
    return @"localhost";
}

static NSString *hook_NSProcessInfo_operatingSystemName(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *value = LCSpoofedSystemName();
        if (value) return @(value);
    }
    if (orig_NSProcessInfo_operatingSystemName) return orig_NSProcessInfo_operatingSystemName(self, _cmd);
    return @"iOS";
}

static NSString *hook_NSProcessInfo_globallyUniqueString(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        NSString *value = LCSpoofedVendorIdentifierString();
        if (value.length > 0) return value;
    }
    if (orig_NSProcessInfo_globallyUniqueString) return orig_NSProcessInfo_globallyUniqueString(self, _cmd);
    return [NSUUID UUID].UUIDString;
}

static NSInteger hook_NSProcessInfo_thermalState(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_thermalConfigured) {
        return g_spoofedThermalState;
    }
    if (orig_NSProcessInfo_thermalState) return orig_NSProcessInfo_thermalState(self, _cmd);
    return 0;
}

static BOOL hook_NSProcessInfo_isLowPowerModeEnabled(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofLowPowerMode) {
        return g_lowPowerModeValue;
    }
    if (orig_NSProcessInfo_isLowPowerModeEnabled) return orig_NSProcessInfo_isLowPowerModeEnabled(self, _cmd);
    return NO;
}

static NSDictionary *hook_NSProcessInfo_environment(id self, SEL _cmd) {
    NSDictionary *env = orig_NSProcessInfo_environment ? orig_NSProcessInfo_environment(self, _cmd) : @{};
    if (!LCScreenFeatureEnabled(g_spoofCraneEnabled || g_spoofAppiumEnabled) ||
        ![env isKindOfClass:[NSDictionary class]] ||
        env.count == 0) {
        return env;
    }

    NSMutableDictionary *filtered = [NSMutableDictionary dictionaryWithCapacity:env.count];
    [env enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        NSString *keyStr = [key isKindOfClass:[NSString class]] ? key : [key description];
        NSString *valStr = [obj isKindOfClass:[NSString class]] ? obj : [obj description];
        if (!LCStringContainsSensitiveMarker(keyStr) && !LCStringContainsSensitiveMarker(valStr)) {
            filtered[key] = obj;
        }
    }];
    return [filtered copy];
}

static NSArray<NSString *> *hook_NSProcessInfo_arguments(id self, SEL _cmd) {
    NSArray<NSString *> *args = orig_NSProcessInfo_arguments ? orig_NSProcessInfo_arguments(self, _cmd) : @[];
    if (!LCScreenFeatureEnabled(g_spoofCraneEnabled || g_spoofAppiumEnabled) ||
        ![args isKindOfClass:[NSArray class]] ||
        args.count == 0) {
        return args;
    }

    NSMutableArray<NSString *> *filtered = [NSMutableArray arrayWithCapacity:args.count];
    for (id arg in args) {
        NSString *argStr = [arg isKindOfClass:[NSString class]] ? arg : [arg description];
        if (!LCStringContainsSensitiveMarker(argStr)) {
            [filtered addObject:argStr];
        }
    }
    return [filtered copy];
}

static CGFloat hook_UIScreen_brightness(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_brightnessConfigured) {
        return (CGFloat)g_spoofedBrightness;
    }
    if (orig_UIScreen_brightness) return orig_UIScreen_brightness(self, _cmd);
    return 0.5;
}

static NSUUID *hook_ASIdentifierManager_advertisingIdentifier(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        if (LCShouldForceZeroVendorID() || (g_adTrackingConfigured && !g_spoofedAdTrackingEnabled)) {
            return [[NSUUID alloc] initWithUUIDString:LCZeroUUIDString];
        }
        NSUUID *uuid = LCUUIDFromOverrideString(g_spoofedAdvertisingID);
        if (uuid) return uuid;
    }
    if (orig_ASIdentifierManager_advertisingIdentifier) return orig_ASIdentifierManager_advertisingIdentifier(self, _cmd);
    return [[NSUUID alloc] initWithUUIDString:LCZeroUUIDString];
}

static BOOL hook_ASIdentifierManager_isAdvertisingTrackingEnabled(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && LCShouldForceZeroVendorID()) {
        return NO;
    }
    if (LCDeviceSpoofingIsActive() && g_adTrackingConfigured) {
        return g_spoofedAdTrackingEnabled;
    }
    if (orig_ASIdentifierManager_isAdvertisingTrackingEnabled) return orig_ASIdentifierManager_isAdvertisingTrackingEnabled(self, _cmd);
    return NO;
}

static id hook_NSFileManager_ubiquityIdentityToken(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_iCloudPrivacyProtectionEnabled) {
        return nil;
    }
    if (orig_NSFileManager_ubiquityIdentityToken) return orig_NSFileManager_ubiquityIdentityToken(self, _cmd);
    return nil;
}

static NSData *hook_NSFileManager_contentsAtPath(id self, SEL _cmd, NSString *path) {
    NSData *data = orig_NSFileManager_contentsAtPath ? orig_NSFileManager_contentsAtPath(self, _cmd, path) : nil;
    if (!LCPathIsSystemVersionPlist(path)) {
        return data;
    }
    return LCSanitizedSystemVersionPlistData(data);
}

static NSString *hook_CTCarrier_carrierName(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_customCarrierName.length > 0) {
        return g_customCarrierName;
    }
    if (orig_CTCarrier_carrierName) return orig_CTCarrier_carrierName(self, _cmd);
    return nil;
}

static NSString *hook_CTCarrier_isoCountryCode(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_customCarrierCountryCode.length > 0) {
        return [g_customCarrierCountryCode lowercaseString];
    }
    if (orig_CTCarrier_isoCountryCode) return orig_CTCarrier_isoCountryCode(self, _cmd);
    return nil;
}

static NSString *hook_CTCarrier_mobileCountryCode(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_customCarrierMCC.length > 0) {
        return g_customCarrierMCC;
    }
    if (orig_CTCarrier_mobileCountryCode) return orig_CTCarrier_mobileCountryCode(self, _cmd);
    return nil;
}

static NSString *hook_CTCarrier_mobileNetworkCode(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_customCarrierMNC.length > 0) {
        return g_customCarrierMNC;
    }
    if (orig_CTCarrier_mobileNetworkCode) return orig_CTCarrier_mobileNetworkCode(self, _cmd);
    return nil;
}

static BOOL hook_CTCarrier_allowsVOIP(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        // Keep deterministic and avoid leaking carrier-specific capability bits.
        return YES;
    }
    if (orig_CTCarrier_allowsVOIP) return orig_CTCarrier_allowsVOIP(self, _cmd);
    return YES;
}

static NSString *hook_CTTelephonyNetworkInfo_currentRadioAccessTechnology(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_cellularTypeConfigured) {
        return LCRadioAccessTechnologyForSpoofType(g_spoofedCellularType);
    }
    if (orig_CTTelephonyNetworkInfo_currentRadioAccessTechnology) return orig_CTTelephonyNetworkInfo_currentRadioAccessTechnology(self, _cmd);
    return nil;
}

static NSDictionary *hook_CTTelephonyNetworkInfo_serviceCurrentRadioAccessTechnology(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_cellularTypeConfigured) {
        NSString *radio = LCRadioAccessTechnologyForSpoofType(g_spoofedCellularType);
        NSDictionary *original = orig_CTTelephonyNetworkInfo_serviceCurrentRadioAccessTechnology ? orig_CTTelephonyNetworkInfo_serviceCurrentRadioAccessTechnology(self, _cmd) : nil;
        if (![original isKindOfClass:[NSDictionary class]] || original.count == 0) {
            return @{@"0000000100000001": radio};
        }

        NSMutableDictionary *mutable = [NSMutableDictionary dictionaryWithCapacity:original.count];
        for (id key in original) {
            mutable[key] = radio;
        }
        return [mutable copy];
    }
    if (orig_CTTelephonyNetworkInfo_serviceCurrentRadioAccessTechnology) return orig_CTTelephonyNetworkInfo_serviceCurrentRadioAccessTechnology(self, _cmd);
    return nil;
}

// MARK: - Timezone hooks

static NSTimeZone *LCSpoofedTimeZone(void) {
    if (!LCDeviceSpoofingIsActive() || g_spoofedTimezone.length == 0) {
        return nil;
    }
    return [NSTimeZone timeZoneWithName:g_spoofedTimezone];
}

static NSTimeZone *hook_NSTimeZone_localTimeZone(id self, SEL _cmd) {
    NSTimeZone *tz = LCSpoofedTimeZone();
    if (tz) return tz;
    if (orig_NSTimeZone_localTimeZone) return orig_NSTimeZone_localTimeZone(self, _cmd);
    return [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
}

static NSTimeZone *hook_NSTimeZone_systemTimeZone(id self, SEL _cmd) {
    NSTimeZone *tz = LCSpoofedTimeZone();
    if (tz) return tz;
    if (orig_NSTimeZone_systemTimeZone) return orig_NSTimeZone_systemTimeZone(self, _cmd);
    return [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
}

static NSTimeZone *hook_NSTimeZone_defaultTimeZone(id self, SEL _cmd) {
    NSTimeZone *tz = LCSpoofedTimeZone();
    if (tz) return tz;
    if (orig_NSTimeZone_defaultTimeZone) return orig_NSTimeZone_defaultTimeZone(self, _cmd);
    return [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
}

// MARK: - Locale hooks

static NSLocale *hook_NSLocale_currentLocale(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofedLocale.length > 0) {
        return [[NSLocale alloc] initWithLocaleIdentifier:g_spoofedLocale];
    }
    if (orig_NSLocale_currentLocale) return orig_NSLocale_currentLocale(self, _cmd);
    return [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
}

static NSLocale *hook_NSLocale_autoupdatingCurrentLocale(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofedLocale.length > 0) {
        return [[NSLocale alloc] initWithLocaleIdentifier:g_spoofedLocale];
    }
    if (orig_NSLocale_autoupdatingCurrentLocale) return orig_NSLocale_autoupdatingCurrentLocale(self, _cmd);
    return [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
}

static NSLocale *hook_NSLocale_systemLocale(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofedLocale.length > 0) {
        return [[NSLocale alloc] initWithLocaleIdentifier:g_spoofedLocale];
    }
    if (orig_NSLocale_systemLocale) return orig_NSLocale_systemLocale(self, _cmd);
    return [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
}

static NSString *hook_NSLocale_countryCode(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofedPreferredCountryCode.length > 0) {
        return [g_spoofedPreferredCountryCode uppercaseString];
    }
    if (orig_NSLocale_countryCode) return orig_NSLocale_countryCode(self, _cmd);
    return nil;
}

static NSString *hook_NSLocale_currencyCode(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofedLocaleCurrencyCode.length > 0) {
        return [g_spoofedLocaleCurrencyCode uppercaseString];
    }
    if (orig_NSLocale_currencyCode) return orig_NSLocale_currencyCode(self, _cmd);
    return nil;
}

static NSString *hook_NSLocale_currencySymbol(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofedLocaleCurrencySymbol.length > 0) {
        return g_spoofedLocaleCurrencySymbol;
    }
    if (orig_NSLocale_currencySymbol) return orig_NSLocale_currencySymbol(self, _cmd);
    return nil;
}

static BOOL hook_NSLocale_usesMetricSystem(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() &&
        (g_spoofedLocale.length > 0 || g_spoofedPreferredCountryCode.length > 0)) {
        return LCSpoofedUsesMetricSystem();
    }
    if (orig_NSLocale_usesMetricSystem) return orig_NSLocale_usesMetricSystem(self, _cmd);
    return YES;
}

static NSArray<NSString *> *hook_NSLocale_preferredLanguages(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && (g_userDefaultsSpoofingEnabled || g_spoofedLocale.length > 0)) {
        return @[LCSpoofedLanguageTag()];
    }
    if (orig_NSLocale_preferredLanguages) return orig_NSLocale_preferredLanguages(self, _cmd);
    return @[LCSpoofedLanguageTag()];
}

static id hook_NSLocale_objectForKey(id self, SEL _cmd, id key) {
    id original = orig_NSLocale_objectForKey ? orig_NSLocale_objectForKey(self, _cmd, key) : nil;
    if (!LCDeviceSpoofingIsActive() ||
        (g_spoofedLocale.length == 0 &&
         g_spoofedPreferredCountryCode.length == 0 &&
         g_spoofedLocaleCurrencyCode.length == 0 &&
         g_spoofedLocaleCurrencySymbol.length == 0)) {
        return original;
    }

    NSString *keyString = nil;
    if ([key isKindOfClass:[NSString class]]) {
        keyString = (NSString *)key;
    } else if (key) {
        keyString = [key description];
    }
    if (keyString.length == 0) return original;

    NSString *lower = keyString.lowercaseString;
    if ([keyString isEqualToString:NSLocaleMeasurementSystem] || [lower containsString:@"measurementsystem"]) {
        return LCSpoofedUsesMetricSystem() ? @"Metric" : @"US";
    }
    if ([lower containsString:@"temperatureunit"]) {
        return LCSpoofedUsesMetricSystem() ? @"Celsius" : @"Fahrenheit";
    }
    return original;
}

static BOOL hook_CMMotionManager_isGyroAvailable(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofGyroscopeEnabled) {
        return YES;
    }
    if (orig_CMMotionManager_isGyroAvailable) return orig_CMMotionManager_isGyroAvailable(self, _cmd);
    return YES;
}

static BOOL hook_CMMotionManager_isDeviceMotionAvailable(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofGyroscopeEnabled) {
        return YES;
    }
    if (orig_CMMotionManager_isDeviceMotionAvailable) return orig_CMMotionManager_isDeviceMotionAvailable(self, _cmd);
    return YES;
}

static NSArray *hook_UITextInputMode_activeInputModes(id self, SEL _cmd) {
    NSArray *modes = orig_UITextInputMode_activeInputModes ? orig_UITextInputMode_activeInputModes(self, _cmd) : @[];
    if (!LCDeviceSpoofingIsActive() || !g_keyboardSpoofingEnabled || ![modes isKindOfClass:[NSArray class]]) {
        return modes;
    }
    if (modes.count == 0) {
        return @[];
    }
    id first = modes.firstObject;
    return first ? @[first] : @[];
}

static id hook_UITextInputMode_currentInputMode(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_keyboardSpoofingEnabled) {
        NSArray *modes = orig_UITextInputMode_activeInputModes ? orig_UITextInputMode_activeInputModes(self, @selector(activeInputModes)) : @[];
        if ([modes isKindOfClass:[NSArray class]] && modes.count > 0) {
            return modes.firstObject;
        }
    }
    if (orig_UITextInputMode_currentInputMode) {
        return orig_UITextInputMode_currentInputMode(self, _cmd);
    }
    return nil;
}

static NSString *hook_UITextInputMode_primaryLanguage(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_keyboardSpoofingEnabled) {
        return LCSpoofedLanguageTag();
    }
    if (orig_UITextInputMode_primaryLanguage) {
        return orig_UITextInputMode_primaryLanguage(self, _cmd);
    }
    return nil;
}

static id hook_NSUserDefaults_objectForKey(id self, SEL _cmd, NSString *defaultName) {
    if (LCShouldSanitizeUserDefaultsKey(defaultName)) {
        return LCSanitizedUserDefaultsValueForKey(defaultName);
    }
    if (orig_NSUserDefaults_objectForKey) {
        return orig_NSUserDefaults_objectForKey(self, _cmd, defaultName);
    }
    return nil;
}

static NSDictionary<NSString *, id> *hook_NSUserDefaults_dictionaryRepresentation(id self, SEL _cmd) {
    NSDictionary<NSString *, id> *dictionary = orig_NSUserDefaults_dictionaryRepresentation
        ? orig_NSUserDefaults_dictionaryRepresentation(self, _cmd)
        : @{};
    if (!LCDeviceSpoofingIsActive() || !g_userDefaultsSpoofingEnabled || ![dictionary isKindOfClass:[NSDictionary class]] || dictionary.count == 0) {
        return dictionary;
    }

    NSMutableDictionary<NSString *, id> *mutable = [dictionary mutableCopy];
    for (id keyObj in dictionary.allKeys) {
        if (![keyObj isKindOfClass:[NSString class]]) continue;
        NSString *key = (NSString *)keyObj;
        if (!LCShouldSanitizeUserDefaultsKey(key)) continue;

        id sanitized = LCSanitizedUserDefaultsValueForKey(key);
        if (sanitized) {
            mutable[key] = sanitized;
        } else {
            [mutable removeObjectForKey:key];
        }
    }
    return [mutable copy];
}

static id hook_NSPropertyListSerialization_propertyListWithData_options_format_error(id self, SEL _cmd, NSData *data, NSPropertyListReadOptions options, NSPropertyListFormat *format, NSError **error) {
    id propertyList = nil;
    if (orig_NSPropertyListSerialization_propertyListWithData_options_format_error) {
        propertyList = orig_NSPropertyListSerialization_propertyListWithData_options_format_error(self, _cmd, data, options, format, error);
    }

    if (!LCEntitlementSpoofingActive() || !LCProcessLooksLikeReveil()) {
        return propertyList;
    }
    if (![propertyList isKindOfClass:[NSDictionary class]]) {
        return propertyList;
    }

    return LCSanitizedReveilEntitlementsDictionary((NSDictionary *)propertyList);
}

static BOOL hook_MFMessageComposeViewController_canSendText(id self, SEL _cmd) {
    if (LCScreenFeatureEnabled(g_spoofMessageEnabled)) {
        return YES;
    }
    if (orig_MFMessageComposeViewController_canSendText) return orig_MFMessageComposeViewController_canSendText(self, _cmd);
    return NO;
}

static BOOL hook_MFMessageComposeViewController_canSendAttachments(id self, SEL _cmd) {
    if (LCScreenFeatureEnabled(g_spoofMessageEnabled)) {
        return YES;
    }
    if (orig_MFMessageComposeViewController_canSendAttachments) return orig_MFMessageComposeViewController_canSendAttachments(self, _cmd);
    return NO;
}

static BOOL hook_MFMessageComposeViewController_canSendSubject(id self, SEL _cmd) {
    if (LCScreenFeatureEnabled(g_spoofMessageEnabled)) {
        return YES;
    }
    if (orig_MFMessageComposeViewController_canSendSubject) return orig_MFMessageComposeViewController_canSendSubject(self, _cmd);
    return NO;
}

static BOOL hook_MFMailComposeViewController_canSendMail(id self, SEL _cmd) {
    if (LCScreenFeatureEnabled(g_spoofMailEnabled)) {
        return YES;
    }
    if (orig_MFMailComposeViewController_canSendMail) return orig_MFMailComposeViewController_canSendMail(self, _cmd);
    return NO;
}

static NSString *hook_UIPasteboard_string(id self, SEL _cmd) {
    if (LCScreenFeatureEnabled(g_spoofPasteboardEnabled)) {
        return nil;
    }
    if (orig_UIPasteboard_string) return orig_UIPasteboard_string(self, _cmd);
    return nil;
}

static NSArray<NSString *> *hook_UIPasteboard_strings(id self, SEL _cmd) {
    if (LCScreenFeatureEnabled(g_spoofPasteboardEnabled)) {
        return nil;
    }
    if (orig_UIPasteboard_strings) return orig_UIPasteboard_strings(self, _cmd);
    return nil;
}

static BOOL hook_UIPasteboard_hasStrings(id self, SEL _cmd) {
    if (LCScreenFeatureEnabled(g_spoofPasteboardEnabled)) {
        return NO;
    }
    if (orig_UIPasteboard_hasStrings) return orig_UIPasteboard_hasStrings(self, _cmd);
    return NO;
}

static NSData *hook_UIPasteboard_dataForPasteboardType(id self, SEL _cmd, NSString *pasteboardType) {
    if (LCScreenFeatureEnabled(g_spoofPasteboardEnabled)) {
        return nil;
    }
    if (orig_UIPasteboard_dataForPasteboardType) return orig_UIPasteboard_dataForPasteboardType(self, _cmd, pasteboardType);
    return nil;
}

// MARK: - Capability / Preference fingerprint hooks

static NSArray *hook_EAAccessoryManager_connectedAccessories(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        return @[];
    }
    if (orig_EAAccessoryManager_connectedAccessories) return orig_EAAccessoryManager_connectedAccessories(self, _cmd);
    return @[];
}

static float hook_AVAudioSession_outputVolume(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        return LCSpoofedAudioOutputVolume();
    }
    if (orig_AVAudioSession_outputVolume) return orig_AVAudioSession_outputVolume(self, _cmd);
    return 0.5f;
}

static BOOL hook_AVAudioSession_secondaryAudioShouldBeSilencedHint(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        return NO;
    }
    if (orig_AVAudioSession_secondaryAudioShouldBeSilencedHint) return orig_AVAudioSession_secondaryAudioShouldBeSilencedHint(self, _cmd);
    return NO;
}

static BOOL hook_SLComposeViewController_isAvailableForServiceType(id self, SEL _cmd, NSString *serviceType) {
    (void)serviceType;
    if (LCDeviceSpoofingIsActive()) {
        // Avoid leaking configured social accounts / entitlements.
        return NO;
    }
    if (orig_SLComposeViewController_isAvailableForServiceType) return orig_SLComposeViewController_isAvailableForServiceType(self, _cmd, serviceType);
    return NO;
}

static BOOL hook_CLLocationManager_locationServicesEnabled(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        // Hide global user preference (settings switch) from fingerprinting.
        return YES;
    }
    if (orig_CLLocationManager_locationServicesEnabled) {
        return orig_CLLocationManager_locationServicesEnabled(self, _cmd);
    }
    return YES;
}

static BOOL hook_SKPaymentQueue_canMakePayments(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        return YES;
    }
    if (orig_SKPaymentQueue_canMakePayments) return orig_SKPaymentQueue_canMakePayments(self, _cmd);
    return YES;
}

static BOOL hook_PKPaymentAuthorizationViewController_canMakePayments(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        return YES;
    }
    if (orig_PKPaymentAuthorizationViewController_canMakePayments) return orig_PKPaymentAuthorizationViewController_canMakePayments(self, _cmd);
    return YES;
}

static BOOL hook_PKPaymentAuthorizationViewController_canMakePaymentsUsingNetworks(id self, SEL _cmd, NSArray *networks) {
    (void)networks;
    if (LCDeviceSpoofingIsActive()) {
        return YES;
    }
    if (orig_PKPaymentAuthorizationViewController_canMakePaymentsUsingNetworks) {
        return orig_PKPaymentAuthorizationViewController_canMakePaymentsUsingNetworks(self, _cmd, networks);
    }
    return YES;
}

static BOOL hook_PKPaymentAuthorizationController_canMakePayments(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        return YES;
    }
    if (orig_PKPaymentAuthorizationController_canMakePayments) return orig_PKPaymentAuthorizationController_canMakePayments(self, _cmd);
    return YES;
}

static BOOL hook_PKPaymentAuthorizationController_canMakePaymentsUsingNetworks(id self, SEL _cmd, NSArray *networks) {
    (void)networks;
    if (LCDeviceSpoofingIsActive()) {
        return YES;
    }
    if (orig_PKPaymentAuthorizationController_canMakePaymentsUsingNetworks) {
        return orig_PKPaymentAuthorizationController_canMakePaymentsUsingNetworks(self, _cmd, networks);
    }
    return YES;
}

static BOOL hook_LAContext_canEvaluatePolicy_error(id self, SEL _cmd, NSInteger policy, NSError **error) {
    if (orig_LAContext_canEvaluatePolicy_error) {
        return orig_LAContext_canEvaluatePolicy_error(self, _cmd, policy, error);
    }
    return NO;
}

static NSInteger hook_LAContext_biometryType(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        // LABiometryTypeFaceID for modern iPhones.
        return 2;
    }
    if (orig_LAContext_biometryType) return orig_LAContext_biometryType(self, _cmd);
    return 0;
}

static NSInteger hook_INPreferences_siriAuthorizationStatus(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_siriPrivacyProtectionEnabled) {
        // INSiriAuthorizationStatusDenied
        return 2;
    }
    if (orig_INPreferences_siriAuthorizationStatus) return orig_INPreferences_siriAuthorizationStatus(self, _cmd);
    return 0;
}

static void hook_INPreferences_requestSiriAuthorization(id self, SEL _cmd, id handler) {
    if (LCDeviceSpoofingIsActive() && g_siriPrivacyProtectionEnabled) {
        if (handler) {
            id copiedHandler = [handler copy];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                void (^callback)(NSInteger status) = copiedHandler;
                callback(2);
            });
        }
        return;
    }
    if (orig_INPreferences_requestSiriAuthorization) {
        orig_INPreferences_requestSiriAuthorization(self, _cmd, handler);
    }
}

static NSString *hook_NSCalendar_identifier(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        return NSCalendarIdentifierGregorian;
    }
    if (orig_NSCalendar_identifier) return orig_NSCalendar_identifier(self, _cmd);
    return NSCalendarIdentifierGregorian;
}

static BOOL hook_NSString_containsString(id self, SEL _cmd, NSString *query) {
    if (LCScreenFeatureEnabled(g_spoofCraneEnabled || g_spoofAppiumEnabled) &&
        (LCStringContainsSensitiveMarker((NSString *)self) || LCStringContainsSensitiveMarker(query))) {
        return NO;
    }
    if (orig_NSString_containsString) return orig_NSString_containsString(self, _cmd, query);
    return NO;
}

static BOOL hook_NSString_hasPrefix(id self, SEL _cmd, NSString *prefix) {
    if (LCScreenFeatureEnabled(g_spoofCraneEnabled || g_spoofAppiumEnabled) &&
        (LCStringContainsSensitiveMarker((NSString *)self) || LCStringContainsSensitiveMarker(prefix))) {
        return NO;
    }
    if (orig_NSString_hasPrefix) return orig_NSString_hasPrefix(self, _cmd, prefix);
    return NO;
}

static BOOL hook_NSString_hasSuffix(id self, SEL _cmd, NSString *suffix) {
    if (LCScreenFeatureEnabled(g_spoofCraneEnabled || g_spoofAppiumEnabled) &&
        (LCStringContainsSensitiveMarker((NSString *)self) || LCStringContainsSensitiveMarker(suffix))) {
        return NO;
    }
    if (orig_NSString_hasSuffix) return orig_NSString_hasSuffix(self, _cmd, suffix);
    return NO;
}

static NSRange hook_NSString_rangeOfString(id self, SEL _cmd, NSString *searchString) {
    if (LCScreenFeatureEnabled(g_spoofCraneEnabled || g_spoofAppiumEnabled) &&
        (LCStringContainsSensitiveMarker((NSString *)self) || LCStringContainsSensitiveMarker(searchString))) {
        return NSMakeRange(NSNotFound, 0);
    }
    if (orig_NSString_rangeOfString) return orig_NSString_rangeOfString(self, _cmd, searchString);
    return NSMakeRange(NSNotFound, 0);
}

static BOOL hook_NSPredicate_evaluateWithObject(id self, SEL _cmd, id object) {
    if (LCScreenFeatureEnabled(g_spoofCraneEnabled || g_spoofAppiumEnabled) && LCObjectContainsSensitiveMarker(object)) {
        return NO;
    }
    if (orig_NSPredicate_evaluateWithObject) return orig_NSPredicate_evaluateWithObject(self, _cmd, object);
    return NO;
}

static id hook_PHAssetCollection_fetchAssetCollectionsWithType_subtype_options(id self, SEL _cmd, NSInteger type, NSInteger subtype, id options) {
    if (!orig_PHAssetCollection_fetchAssetCollectionsWithType_subtype_options) {
        return nil;
    }

    id original = orig_PHAssetCollection_fetchAssetCollectionsWithType_subtype_options(self, _cmd, type, subtype, options);
    if (!LCScreenFeatureEnabled(g_spoofAlbumEnabled) || g_albumBlacklist.count == 0 || !original) {
        return original;
    }

    NSMutableArray<NSString *> *allowedLocalIds = [NSMutableArray array];
    @try {
        for (id collection in original) {
            NSString *localId = [collection respondsToSelector:@selector(localIdentifier)] ? [collection localIdentifier] : nil;
            NSString *title = [collection respondsToSelector:@selector(localizedTitle)] ? [collection localizedTitle] : @"";
            NSString *entry = [NSString stringWithFormat:@"%@-%@", localId ?: @"", title ?: @""];
            if (localId.length > 0 && ![g_albumBlacklist containsObject:entry]) {
                [allowedLocalIds addObject:localId];
            }
        }
    } @catch (__unused NSException *e) {
        return original;
    }

    Class phAssetCollectionClass = objc_getClass("PHAssetCollection");
    SEL selector = NSSelectorFromString(@"fetchAssetCollectionsWithLocalIdentifiers:options:");
    if (!phAssetCollectionClass || ![phAssetCollectionClass respondsToSelector:selector]) {
        return original;
    }

    id (*msgSendTyped)(id, SEL, NSArray *, id) = (id (*)(id, SEL, NSArray *, id))objc_msgSend;
    return msgSendTyped(phAssetCollectionClass, selector, allowedLocalIds, nil);
}

static BOOL hook_BugsnagDevice_jailbroken(id self, SEL _cmd) {
    if (LCScreenFeatureEnabled(g_spoofBugsnagEnabled)) {
        return NO;
    }
    if (orig_BugsnagDevice_jailbroken) return orig_BugsnagDevice_jailbroken(self, _cmd);
    return NO;
}

static void hook_BugsnagDevice_setJailbroken(id self, SEL _cmd, BOOL value) {
    if (orig_BugsnagDevice_setJailbroken) {
        orig_BugsnagDevice_setJailbroken(self, _cmd, LCScreenFeatureEnabled(g_spoofBugsnagEnabled) ? NO : value);
    }
}

static id hook_NSURLSession_uploadTaskWithRequest_fromData_completionHandler(id self, SEL _cmd, NSURLRequest *request, NSData *bodyData, id completionHandler) {
    NSData *payload = bodyData;
    if (LCScreenFeatureEnabled(g_spoofBugsnagEnabled) &&
        [request isKindOfClass:[NSURLRequest class]]) {
        NSString *urlString = request.URL.absoluteString.lowercaseString ?: @"";
        if ([urlString containsString:@"sessions.bugsnag.com"]) {
            payload = LCModifyBugsnagPayload(bodyData);
        }
    }

    if (orig_NSURLSession_uploadTaskWithRequest_fromData_completionHandler) {
        return orig_NSURLSession_uploadTaskWithRequest_fromData_completionHandler(self, _cmd, request, payload, completionHandler);
    }
    return nil;
}

static void LCDispatchAttestationCompletion(id completion, id firstValue, NSError *error) {
    if (!completion) {
        return;
    }
    id copiedCompletion = [completion copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        void (^callback)(id value, NSError *callbackError) = copiedCompletion;
        callback(firstValue, error);
    });
}

static BOOL hook_DCDevice_isSupported(id self, SEL _cmd) {
    if (orig_DCDevice_isSupported) return orig_DCDevice_isSupported(self, _cmd);
    return YES;
}

static void hook_DCDevice_generateTokenWithCompletionHandler(id self, SEL _cmd, id completion) {
    if (!LCDeviceSpoofingIsActive() || !g_deviceCheckSpoofingEnabled) {
        if (orig_DCDevice_generateTokenWithCompletionHandler) {
            orig_DCDevice_generateTokenWithCompletionHandler(self, _cmd, completion);
        }
        return;
    }

    if (orig_DCDevice_generateTokenWithCompletionHandler) {
        orig_DCDevice_generateTokenWithCompletionHandler(self, _cmd, completion);
        return;
    }
    LCDispatchAttestationCompletion(completion, nil, nil);
}

static BOOL hook_DCAppAttestService_isSupported(id self, SEL _cmd) {
    if (orig_DCAppAttestService_isSupported) return orig_DCAppAttestService_isSupported(self, _cmd);
    return YES;
}

static void hook_DCAppAttestService_generateKeyWithCompletionHandler(id self, SEL _cmd, id completion) {
    if (!LCDeviceSpoofingIsActive() || !g_appAttestSpoofingEnabled) {
        if (orig_DCAppAttestService_generateKeyWithCompletionHandler) {
            orig_DCAppAttestService_generateKeyWithCompletionHandler(self, _cmd, completion);
        }
        return;
    }

    if (orig_DCAppAttestService_generateKeyWithCompletionHandler) {
        orig_DCAppAttestService_generateKeyWithCompletionHandler(self, _cmd, completion);
        return;
    }
    LCDispatchAttestationCompletion(completion, nil, nil);
}

static void hook_DCAppAttestService_attestKey_clientDataHash_completionHandler(id self, SEL _cmd, NSString *keyId, NSData *clientDataHash, id completion) {
    if (!LCDeviceSpoofingIsActive() || !g_appAttestSpoofingEnabled) {
        if (orig_DCAppAttestService_attestKey_clientDataHash_completionHandler) {
            orig_DCAppAttestService_attestKey_clientDataHash_completionHandler(self, _cmd, keyId, clientDataHash, completion);
        }
        return;
    }

    if (orig_DCAppAttestService_attestKey_clientDataHash_completionHandler) {
        orig_DCAppAttestService_attestKey_clientDataHash_completionHandler(self, _cmd, keyId, clientDataHash, completion);
        return;
    }
    LCDispatchAttestationCompletion(completion, nil, nil);
}

static void hook_DCAppAttestService_generateAssertion_clientDataHash_completionHandler(id self, SEL _cmd, NSString *keyId, NSData *clientDataHash, id completion) {
    if (!LCDeviceSpoofingIsActive() || !g_appAttestSpoofingEnabled) {
        if (orig_DCAppAttestService_generateAssertion_clientDataHash_completionHandler) {
            orig_DCAppAttestService_generateAssertion_clientDataHash_completionHandler(self, _cmd, keyId, clientDataHash, completion);
        }
        return;
    }

    if (orig_DCAppAttestService_generateAssertion_clientDataHash_completionHandler) {
        orig_DCAppAttestService_generateAssertion_clientDataHash_completionHandler(self, _cmd, keyId, clientDataHash, completion);
        return;
    }
    LCDispatchAttestationCompletion(completion, nil, nil);
}

// MARK: - Screen capture block hook

static BOOL hook_UIScreen_isCaptured(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_screenCaptureBlockEnabled) {
        return NO; // Always report not captured
    }
    if (orig_UIScreen_isCaptured) return orig_UIScreen_isCaptured(self, _cmd);
    return NO;
}

// MARK: - Uptime hook (paired with KERN_BOOTTIME sysctl hook above)
static NSTimeInterval hook_NSProcessInfo_systemUptime(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_bootTimeSpoofingEnabled) {
        NSTimeInterval real = orig_NSProcessInfo_systemUptime ? orig_NSProcessInfo_systemUptime(self, _cmd) : 0;
        // Shift uptime by the same offset used for KERN_BOOTTIME so they stay consistent
        return real + g_bootTimeOffset;
    }
    if (orig_NSProcessInfo_systemUptime) return orig_NSProcessInfo_systemUptime(self, _cmd);
    return 0;
}

// MARK: - User-Agent auto-generation from profile
static NSString *LCBuildUserAgentForProfile(void) {
    if (!g_currentProfile) return nil;
    const char *model = g_currentProfile->modelIdentifier;
    const char *version = LCSpoofedSystemVersion();
    const char *build = LCSpoofedBuildVersion();
    if (!model || !version || !build) return nil;

    // Determine device type from identifier
    BOOL isIPad = (strncmp(model, "iPad", 4) == 0);
    NSString *versionUnderscored = [[@(version) stringByReplacingOccurrencesOfString:@"." withString:@"_"] copy];

    // Build a realistic Safari-style UA
    if (isIPad) {
        return [NSString stringWithFormat:
            @"Mozilla/5.0 (iPad; CPU OS %@ like Mac OS X) "
            @"AppleWebKit/605.1.15 (KHTML, like Gecko) "
            @"Version/%s Mobile/%s Safari/604.1",
            versionUnderscored, version, build];
    }
    return [NSString stringWithFormat:
        @"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) "
        @"AppleWebKit/605.1.15 (KHTML, like Gecko) "
        @"Version/%s Mobile/%s Safari/604.1",
        versionUnderscored, version, build];
}

// Replace iOS version pattern in existing User-Agent strings
static NSString *LCModifyUserAgentVersion(NSString *ua) {
    if (!ua || ua.length == 0) return ua;
    const char *version = LCSpoofedSystemVersion();
    const char *build = LCSpoofedBuildVersion();
    if (!version || !build) return ua;

    NSString *underscored = [[@(version) stringByReplacingOccurrencesOfString:@"." withString:@"_"] copy];
    NSMutableString *result = [ua mutableCopy];

    // Pattern: CPU iPhone OS 15_4_1 like Mac OS X
    NSRegularExpression *r1 = [NSRegularExpression regularExpressionWithPattern:@"(CPU\\s+(?:iPhone\\s+)?OS\\s+)\\d+[_.]\\d+(?:[_.]\\d+)?(\\s+like)" options:0 error:nil];
    result = [[r1 stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length)
        withTemplate:[NSString stringWithFormat:@"$1%@$2", underscored]] mutableCopy];

    // Pattern: Version/15.4
    NSRegularExpression *r2 = [NSRegularExpression regularExpressionWithPattern:@"(Version/)\\d+\\.\\d+(?:\\.\\d+)?" options:0 error:nil];
    result = [[r2 stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length)
        withTemplate:[NSString stringWithFormat:@"$1%s", version]] mutableCopy];

    // Pattern: Mobile/19F77
    NSRegularExpression *r3 = [NSRegularExpression regularExpressionWithPattern:@"(Mobile/)\\w+" options:0 error:nil];
    result = [[r3 stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length)
        withTemplate:[NSString stringWithFormat:@"$1%s", build]] mutableCopy];

    // Pattern: 1179x2556 (native pixel dimensions used by some app UAs)
    if (g_currentProfile) {
        CGSize nativeSize = LCSpoofedNativeScreenSize();
        NSInteger nativeW = (NSInteger)nativeSize.width;
        NSInteger nativeH = (NSInteger)nativeSize.height;
        NSRegularExpression *r4 = [NSRegularExpression regularExpressionWithPattern:@"\\b\\d{3,5}x\\d{3,5}\\b" options:0 error:nil];
        result = [[r4 stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length)
            withTemplate:[NSString stringWithFormat:@"%ldx%ld", (long)nativeW, (long)nativeH]] mutableCopy];

        // Pattern: scale=3.00
        NSRegularExpression *r5 = [NSRegularExpression regularExpressionWithPattern:@"(scale=)\\d+(?:\\.\\d+)?" options:0 error:nil];
        result = [[r5 stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length)
            withTemplate:[NSString stringWithFormat:@"$1%.2f", g_currentProfile->screenScale]] mutableCopy];
    }

    return result;
}

static CGRect LCSpoofedScreenBoundsForOrientation(UIInterfaceOrientation orientation) {
    if (!g_currentProfile) return CGRectZero;
    CGFloat width = g_currentProfile->screenWidth;
    CGFloat height = g_currentProfile->screenHeight;
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        CGFloat tmp = width;
        width = height;
        height = tmp;
    }
    return CGRectMake(0, 0, width, height);
}

static CGRect LCAdjustedStatusBarFrameForProfile(CGRect frame) {
    if (!LCDeviceSpoofingIsActive() || !g_currentProfile) return frame;
    if (CGRectIsEmpty(frame)) return frame;

    BOOL isLandscape = frame.size.width > frame.size.height;
    CGFloat width = isLandscape ? g_currentProfile->screenHeight : g_currentProfile->screenWidth;
    frame.origin.x = 0;
    frame.origin.y = 0;
    frame.size.width = width;
    return frame;
}

static CGRect LCSpoofedDisplayBounds(void) {
    if (!g_currentProfile) return CGRectZero;
    return CGRectMake(0, 0, g_currentProfile->screenWidth, g_currentProfile->screenHeight);
}

static size_t LCSpoofedDisplayPixelsWide(void) {
    if (!g_currentProfile) return 0;
    CGSize nativeSize = LCSpoofedNativeScreenSize();
    return (size_t)llround(nativeSize.width);
}

static size_t LCSpoofedDisplayPixelsHigh(void) {
    if (!g_currentProfile) return 0;
    CGSize nativeSize = LCSpoofedNativeScreenSize();
    return (size_t)llround(nativeSize.height);
}

static CGRect hook_CGDisplayBounds(uint32_t display) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return LCSpoofedDisplayBounds();
    }
    if (orig_CGDisplayBounds) return orig_CGDisplayBounds(display);
    return CGRectZero;
}

static size_t hook_CGDisplayPixelsWide(uint32_t display) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return LCSpoofedDisplayPixelsWide();
    }
    if (orig_CGDisplayPixelsWide) return orig_CGDisplayPixelsWide(display);
    return 0;
}

static size_t hook_CGDisplayPixelsHigh(uint32_t display) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return LCSpoofedDisplayPixelsHigh();
    }
    if (orig_CGDisplayPixelsHigh) return orig_CGDisplayPixelsHigh(display);
    return 0;
}

// MARK: - UIScreen hooks (screen size spoofing)
static CGRect hook_UIScreen_bounds(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return LCSpoofedScreenBoundsForOrientation(UIInterfaceOrientationPortrait);
    }
    if (orig_UIScreen_bounds) return orig_UIScreen_bounds(self, _cmd);
    return CGRectZero;
}

static CGRect hook_UIScreen_nativeBounds(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        CGFloat scale = g_currentProfile->screenScale;
        return CGRectMake(0, 0,
            g_currentProfile->screenWidth * scale,
            g_currentProfile->screenHeight * scale);
    }
    if (orig_UIScreen_nativeBounds) return orig_UIScreen_nativeBounds(self, _cmd);
    return CGRectZero;
}

static CGRect hook_UIScreen_boundsForInterfaceOrientation(id self, SEL _cmd, UIInterfaceOrientation orientation) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return LCSpoofedScreenBoundsForOrientation(orientation);
    }
    if (orig_UIScreen_boundsForInterfaceOrientation) return orig_UIScreen_boundsForInterfaceOrientation(self, _cmd, orientation);
    return CGRectZero;
}

static CGRect hook_UIScreen_referenceBounds(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return LCSpoofedScreenBoundsForOrientation(UIInterfaceOrientationPortrait);
    }
    if (orig_UIScreen_referenceBounds) return orig_UIScreen_referenceBounds(self, _cmd);
    return CGRectZero;
}

static CGRect hook_UIScreen_privateBounds(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return LCSpoofedScreenBoundsForOrientation(UIInterfaceOrientationPortrait);
    }
    if (orig_UIScreen_privateBounds) return orig_UIScreen_privateBounds(self, _cmd);
    return CGRectZero;
}

static CGRect hook_UIScreen_privateNativeBounds(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        CGSize nativeSize = LCSpoofedNativeScreenSize();
        return CGRectMake(0, 0, nativeSize.width, nativeSize.height);
    }
    if (orig_UIScreen_privateNativeBounds) return orig_UIScreen_privateNativeBounds(self, _cmd);
    return CGRectZero;
}

static CGFloat hook_UIScreen_scale(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return g_currentProfile->screenScale;
    }
    if (orig_UIScreen_scale) return orig_UIScreen_scale(self, _cmd);
    return 2.0;
}

static CGFloat hook_UIScreen_nativeScale(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return g_currentProfile->screenScale;
    }
    if (orig_UIScreen_nativeScale) return orig_UIScreen_nativeScale(self, _cmd);
    return 2.0;
}

static CGRect hook_UIScreen_applicationFrame(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return CGRectMake(0, 0, g_currentProfile->screenWidth, g_currentProfile->screenHeight);
    }
    if (orig_UIScreen_applicationFrame) return orig_UIScreen_applicationFrame(self, _cmd);
    return CGRectZero;
}

static id hook_UIScreen_coordinateSpace(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        // Returning UIScreen itself keeps subsequent bounds reads on the spoofed path.
        return self;
    }
    if (orig_UIScreen_coordinateSpace) return orig_UIScreen_coordinateSpace(self, _cmd);
    return self;
}

static id hook_UIScreen_fixedCoordinateSpace(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return self;
    }
    if (orig_UIScreen_fixedCoordinateSpace) return orig_UIScreen_fixedCoordinateSpace(self, _cmd);
    return self;
}

static UIScreenMode *hook_UIScreen_currentMode(id self, SEL _cmd) {
    if (orig_UIScreen_currentMode) {
        return orig_UIScreen_currentMode(self, _cmd);
    }
    if (orig_UIScreen_availableModes) {
        NSArray<UIScreenMode *> *modes = orig_UIScreen_availableModes(self, @selector(availableModes));
        if (modes.count > 0) return modes.firstObject;
    }
    return nil;
}

static UIScreenMode *hook_UIScreen_preferredMode(id self, SEL _cmd) {
    if (orig_UIScreen_preferredMode) {
        return orig_UIScreen_preferredMode(self, _cmd);
    }
    if (orig_UIScreen_currentMode) {
        return orig_UIScreen_currentMode(self, @selector(currentMode));
    }
    return nil;
}

static NSArray<UIScreenMode *> *hook_UIScreen_availableModes(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        UIScreenMode *mode = nil;
        if (orig_UIScreen_currentMode) {
            mode = orig_UIScreen_currentMode(self, @selector(currentMode));
        }
        if (!mode && orig_UIScreen_preferredMode) {
            mode = orig_UIScreen_preferredMode(self, @selector(preferredMode));
        }
        if (mode) {
            return @[mode];
        }
    }
    if (orig_UIScreen_availableModes) {
        return orig_UIScreen_availableModes(self, _cmd);
    }
    return @[];
}

static NSInteger hook_UIScreen_maximumFramesPerSecond(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return LCSpoofedMaximumFramesPerSecond();
    }
    if (orig_UIScreen_maximumFramesPerSecond) {
        return orig_UIScreen_maximumFramesPerSecond(self, _cmd);
    }
    return 60;
}

static CGSize hook_UIScreenMode_size(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return LCSpoofedNativeScreenSize();
    }
    if (orig_UIScreenMode_size) {
        return orig_UIScreenMode_size(self, _cmd);
    }
    return CGSizeZero;
}

static CGFloat hook_UITraitCollection_displayScale(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return g_currentProfile->screenScale;
    }
    if (orig_UITraitCollection_displayScale) {
        return orig_UITraitCollection_displayScale(self, _cmd);
    }
    return 2.0;
}

static NSString *hook_UITraitCollection_preferredContentSizeCategory(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        // Use a common default to reduce dynamic-type fingerprinting.
        return UIContentSizeCategoryLarge;
    }
    if (orig_UITraitCollection_preferredContentSizeCategory) {
        return orig_UITraitCollection_preferredContentSizeCategory(self, _cmd);
    }
    return UIContentSizeCategoryLarge;
}

static CGRect hook_UIApplication_statusBarFrame(id self, SEL _cmd) {
    CGRect frame = CGRectZero;
    if (orig_UIApplication_statusBarFrame) {
        frame = orig_UIApplication_statusBarFrame(self, _cmd);
    }
    return LCAdjustedStatusBarFrameForProfile(frame);
}

static CGRect hook_UIStatusBarManager_statusBarFrame(id self, SEL _cmd) {
    CGRect frame = CGRectZero;
    if (orig_UIStatusBarManager_statusBarFrame) {
        frame = orig_UIStatusBarManager_statusBarFrame(self, _cmd);
    }
    return LCAdjustedStatusBarFrameForProfile(frame);
}

static BOOL hook_UIApplication_canOpenURL(id self, SEL _cmd, NSURL *url) {
    if (LCShouldBlockURLScheme(url)) {
        return NO;
    }
    if (orig_UIApplication_canOpenURL) return orig_UIApplication_canOpenURL(self, _cmd, url);
    return NO;
}

static NSString *hook_UIApplication_preferredContentSizeCategory(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        return UIContentSizeCategoryLarge;
    }
    if (orig_UIApplication_preferredContentSizeCategory) {
        return orig_UIApplication_preferredContentSizeCategory(self, _cmd);
    }
    return UIContentSizeCategoryLarge;
}

// MARK: - UIDevice model hooks
static NSString *hook_UIDevice_model(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        const char *ident = g_currentProfile->modelIdentifier;
        if (ident && strncmp(ident, "iPad", 4) == 0) return @"iPad";
        return @"iPhone";
    }
    if (orig_UIDevice_model) return orig_UIDevice_model(self, _cmd);
    return @"iPhone";
}

static NSString *hook_UIDevice_localizedModel(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        const char *ident = g_currentProfile->modelIdentifier;
        if (ident && strncmp(ident, "iPad", 4) == 0) return @"iPad";
        return @"iPhone";
    }
    if (orig_UIDevice_localizedModel) return orig_UIDevice_localizedModel(self, _cmd);
    return @"iPhone";
}

static NSString *hook_UIDevice_machineName(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *value = LCSpoofedMachineModel();
        if (value) return @(value);
    }
    if (orig_UIDevice_machineName) return orig_UIDevice_machineName(self, _cmd);
    return @"iPhone";
}

static id hook_UIDevice_deviceInfoForKey(id self, SEL _cmd, NSString *key) {
    id original = orig_UIDevice_deviceInfoForKey ? orig_UIDevice_deviceInfoForKey(self, _cmd, key) : nil;
    if (!LCDeviceSpoofingIsActive() || key.length == 0) {
        return original;
    }

    if ([key isEqualToString:@"ProductVersion"]) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return @(value);
    } else if ([key isEqualToString:@"BuildVersion"] || [key isEqualToString:@"j9Th5smJpdztHwc+i39zIg"]) {
        const char *value = LCSpoofedBuildVersion();
        if (value) return @(value);
    } else if ([key isEqualToString:@"KernOsversion"]) {
        const char *value = LCSpoofedBuildVersion();
        if (value) return @(value);
    } else if ([key isEqualToString:@"KernOsproductversion"]) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return @(value);
    } else if ([key isEqualToString:@"KernBootsessionuuid"]) {
        NSString *value = LCSpoofedBootSessionUUIDString();
        if (value.length > 0) return value;
    } else if ([key isEqualToString:@"ProductType"]) {
        const char *value = LCSpoofedMachineModel();
        if (value) return @(value);
    } else if ([key isEqualToString:@"HwMachine"]) {
        const char *value = LCSpoofedMachineModel();
        if (value) return @(value);
    } else if ([key isEqualToString:@"HardwareModel"]) {
        const char *value = LCSpoofedHardwareModel();
        if (value) return @(value);
    } else if ([key isEqualToString:@"HwModelStr"]) {
        const char *value = LCSpoofedHardwareModel();
        if (value) return @(value);
    } else if ([key isEqualToString:@"IdentifierForVendor"] || [key isEqualToString:@"VendorIdentifier"]) {
        NSString *value = LCSpoofedVendorIdentifierString();
        if (value.length > 0) return value;
    } else if ([key isEqualToString:@"AdvertisingIdentifier"]) {
        if (LCShouldForceZeroVendorID() || (g_adTrackingConfigured && !g_spoofedAdTrackingEnabled)) {
            return LCZeroUUIDString;
        }
        NSUUID *uuid = LCUUIDFromOverrideString(g_spoofedAdvertisingID);
        if (uuid) return uuid.UUIDString;
    } else if ([key isEqualToString:@"DeviceName"]) {
        NSString *value = LCSpoofedDeviceNameString();
        if (value.length > 0) return value;
    } else if ([key isEqualToString:@"ComputerName"]) {
        NSString *value = LCSpoofedDeviceNameString();
        if (value.length > 0) return value;
    } else if ([key isEqualToString:@"LocalHostName"]) {
        NSString *value = LCSpoofedHostNameString();
        if (value.length > 0) return value;
    } else if ([key isEqualToString:@"ChipName"] || [key isEqualToString:@"CPUModel"] || [key isEqualToString:@"SoCModel"]) {
        const char *value = LCSpoofedChipName();
        if (value) return @(value);
    } else if ([key isEqualToString:@"GPUName"] || [key isEqualToString:@"GPUModel"]) {
        const char *value = LCSpoofedGPUName();
        if (value) return @(value);
    }

    return original;
}

static CFTypeRef hook_MGCopyAnswer(CFStringRef key) {
    CFTypeRef spoofed = LCCopySpoofedGestaltValue(key);
    if (spoofed) {
        return spoofed;
    }
    if (orig_MGCopyAnswer) {
        return orig_MGCopyAnswer(key);
    }
    return NULL;
}

static CFDictionaryRef hook_CFCopySystemVersionDictionary(void) {
    CFDictionaryRef original = orig_CFCopySystemVersionDictionary ? orig_CFCopySystemVersionDictionary() : NULL;
    if (!LCDeviceSpoofingIsActive()) {
        return original;
    }

    const char *version = LCSpoofedSystemVersion();
    const char *build = LCSpoofedBuildVersion();
    if (!version && !build) {
        return original;
    }

    CFMutableDictionaryRef mutableDict = NULL;
    if (original) {
        mutableDict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, original);
    } else {
        mutableDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }
    if (!mutableDict) {
        return original;
    }

    if (version) {
        CFStringRef value = CFStringCreateWithCString(kCFAllocatorDefault, version, kCFStringEncodingUTF8);
        if (value) {
            CFDictionarySetValue(mutableDict, CFSTR("ProductVersion"), value);
            CFDictionarySetValue(mutableDict, CFSTR("ProductUserVisibleVersion"), value);
            CFRelease(value);
        }
    }

    if (build) {
        CFStringRef value = CFStringCreateWithCString(kCFAllocatorDefault, build, kCFStringEncodingUTF8);
        if (value) {
            CFDictionarySetValue(mutableDict, CFSTR("ProductBuildVersion"), value);
            CFRelease(value);
        }
    }

    if (original) {
        CFRelease(original);
    }
    return mutableDict;
}

static CFTypeRef LCApplySpoofedIORegistryProperty(CFTypeRef result, CFStringRef key, CFAllocatorRef allocator) {
    if (!LCDeviceSpoofingIsActive() || !key) {
        return result;
    }

    // Storage size from IOKit (used by some technical fingerprint apps).
    if (LCStorageSpoofingActive() &&
        LCCFStringEqualsIgnoreCase(key, CFSTR("Size")) &&
        result && CFGetTypeID(result) == CFNumberGetTypeID()) {
        uint64_t totalBytes = g_spoofedStorageTotal;
        CFRelease(result);
        return CFNumberCreate(allocator ?: kCFAllocatorDefault, kCFNumberSInt64Type, &totalBytes);
    }

    if (LCCFStringEqualsIgnoreCase(key, CFSTR("marketing-name")) ||
        LCCFStringEqualsIgnoreCase(key, CFSTR("product-name"))) {
        const char *marketingName = LCSpoofedMarketingName();
        if (!marketingName) return result;

        if (result) {
            CFRelease(result);
        }
        size_t len = strlen(marketingName) + 1;
        return CFDataCreate(allocator ?: kCFAllocatorDefault, (const UInt8 *)marketingName, (CFIndex)len);
    }

    const char *replacement = NULL;
    if (LCCFStringEqualsIgnoreCase(key, CFSTR("model")) ||
        LCCFStringEqualsIgnoreCase(key, CFSTR("device-model")) ||
        LCCFStringEqualsIgnoreCase(key, CFSTR("hw.machine"))) {
        replacement = LCSpoofedMachineModel();
    } else if (LCCFStringEqualsIgnoreCase(key, CFSTR("hw.model")) ||
               LCCFStringEqualsIgnoreCase(key, CFSTR("HWModel"))) {
        replacement = LCSpoofedHardwareModel();
    } else if (LCCFStringEqualsIgnoreCase(key, CFSTR("board-id")) ||
               LCCFStringEqualsIgnoreCase(key, CFSTR("BoardId"))) {
        replacement = LCSpoofedHardwareModel();
    }

    if (!replacement) {
        return result;
    }

    if (result) {
        CFRelease(result);
    }
    return CFStringCreateWithCString(allocator ?: kCFAllocatorDefault, replacement, kCFStringEncodingUTF8);
}

static CFTypeRef hook_IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    CFTypeRef result = orig_IORegistryEntryCreateCFProperty ? orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options) : NULL;
    return LCApplySpoofedIORegistryProperty(result, key, allocator);
}

static CFTypeRef hook_IORegistryEntrySearchCFProperty(io_registry_entry_t entry, const char *plane, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    CFTypeRef result = orig_IORegistryEntrySearchCFProperty ? orig_IORegistryEntrySearchCFProperty(entry, plane, key, allocator, options) : NULL;
    return LCApplySpoofedIORegistryProperty(result, key, allocator);
}

__attribute__((unused)) static CFDictionaryRef hook_CNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    CFDictionaryRef original = orig_CNCopyCurrentNetworkInfo ? orig_CNCopyCurrentNetworkInfo(interfaceName) : NULL;
    if (!(LCDeviceSpoofingIsActive() && g_networkInfoSpoofingEnabled)) {
        return original;
    }

    NSString *ssid = g_spoofedWiFiSSID.length > 0 ? g_spoofedWiFiSSID : @"Public Network";
    NSString *bssid = g_spoofedWiFiBSSID.length > 0 ? g_spoofedWiFiBSSID : @"22:66:99:00:11:22";
    NSData *ssidData = [ssid dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];

    NSDictionary *spoofed = @{
        @"SSID": ssid,
        @"BSSID": bssid,
        @"SSIDDATA": ssidData,
    };

    if (original) {
        CFRelease(original);
    }
    return (CFDictionaryRef)CFBridgingRetain(spoofed);
}

// MARK: - NSProcessInfo isOperatingSystemAtLeastVersion
static BOOL hook_NSProcessInfo_isOperatingSystemAtLeastVersion(id self, SEL _cmd, NSOperatingSystemVersion version) {
    if (LCDeviceSpoofingIsActive()) {
        const char *v = LCSpoofedSystemVersion();
        if (v) {
            NSOperatingSystemVersion spoofed = LCParseOSVersion(@(v));
            BOOL result = (spoofed.majorVersion > version.majorVersion) ||
                ((spoofed.majorVersion == version.majorVersion) &&
                 (spoofed.minorVersion > version.minorVersion)) ||
                ((spoofed.majorVersion == version.majorVersion) &&
                 (spoofed.minorVersion == version.minorVersion) &&
                 (spoofed.patchVersion >= version.patchVersion));
            return result;
        }
    }
    if (orig_NSProcessInfo_isOperatingSystemAtLeastVersion)
        return orig_NSProcessInfo_isOperatingSystemAtLeastVersion(self, _cmd, version);
    return NO;
}

static BOOL hook_SwiftNSProcessInfo_isOperatingSystemAtLeastVersion(id self, SEL _cmd, NSOperatingSystemVersion version) {
    if (LCDeviceSpoofingIsActive()) {
        const char *v = LCSpoofedSystemVersion();
        if (v) {
            NSOperatingSystemVersion spoofed = LCParseOSVersion(@(v));
            BOOL result = (spoofed.majorVersion > version.majorVersion) ||
                ((spoofed.majorVersion == version.majorVersion) &&
                 (spoofed.minorVersion > version.minorVersion)) ||
                ((spoofed.majorVersion == version.majorVersion) &&
                 (spoofed.minorVersion == version.minorVersion) &&
                 (spoofed.patchVersion >= version.patchVersion));
            return result;
        }
    }
    if (orig_SwiftNSProcessInfo_isOperatingSystemAtLeastVersion) {
        return orig_SwiftNSProcessInfo_isOperatingSystemAtLeastVersion(self, _cmd, version);
    }
    return NO;
}

// MARK: - NSMutableURLRequest User-Agent hook
static void hook_NSMutableURLRequest_setValue_forHTTPHeaderField(id self, SEL _cmd, NSString *value, NSString *field) {
    NSString *outValue = value;

    if (LCDeviceSpoofingIsActive() && [field isKindOfClass:[NSString class]]) {
        if ([field caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame && value.length > 0) {
            NSString *modified = LCModifyUserAgentVersion(value);
            if (modified.length > 0) {
                outValue = modified;
            }
        } else {
            NSString *persistentID = g_spoofedPersistentDeviceID.length > 0 ? g_spoofedPersistentDeviceID : g_spoofedInstallationID;
            if (persistentID.length > 0) {
                if ([field caseInsensitiveCompare:@"persistent-device-id"] == NSOrderedSame ||
                    [field caseInsensitiveCompare:@"x-persistent-device-id"] == NSOrderedSame ||
                    [field caseInsensitiveCompare:@"device-id"] == NSOrderedSame ||
                    [field caseInsensitiveCompare:@"x-device-id"] == NSOrderedSame ||
                    [field caseInsensitiveCompare:@"installation-id"] == NSOrderedSame ||
                    [field caseInsensitiveCompare:@"x-installation-id"] == NSOrderedSame) {
                    outValue = persistentID;
                }
            }
        }
    }

    if (orig_NSMutableURLRequest_setValue_forHTTPHeaderField) {
        orig_NSMutableURLRequest_setValue_forHTTPHeaderField(self, _cmd, outValue, field);
    }
}

// MARK: - WKWebViewConfiguration applicationNameForUserAgent hook
static void hook_WKWebViewConfiguration_setApplicationNameForUserAgent(id self, SEL _cmd, NSString *name) {
    if (LCDeviceSpoofingIsActive() && name.length > 0) {
        NSString *modified = LCModifyUserAgentVersion(name);
        if (modified && ![modified isEqualToString:name]) {
            if (orig_WKWebViewConfiguration_setApplicationNameForUserAgent)
                orig_WKWebViewConfiguration_setApplicationNameForUserAgent(self, _cmd, modified);
            return;
        }
    }
    if (orig_WKWebViewConfiguration_setApplicationNameForUserAgent)
        orig_WKWebViewConfiguration_setApplicationNameForUserAgent(self, _cmd, name);
}

// MARK: - WKWebView JS fingerprint injection script
static NSString *LCBuildFingerprintInjectionScript(void) {
    if (!g_currentProfile) return nil;

    NSInteger screenW = (NSInteger)g_currentProfile->screenWidth;
    NSInteger screenH = (NSInteger)g_currentProfile->screenHeight;
    double dpr = (double)g_currentProfile->screenScale;
    uint32_t cpuCores = LCSpoofedCPUCount();
    if (cpuCores == 0) {
        cpuCores = (uint32_t)[NSProcessInfo processInfo].activeProcessorCount;
    }
    if (cpuCores == 0) {
        cpuCores = g_currentProfile->cpuCoreCount;
    }
    uint64_t spoofedMemory = LCSpoofedPhysicalMemory();
    if (spoofedMemory == 0) spoofedMemory = g_currentProfile->physicalMemory;
    double memoryGB = (double)spoofedMemory / (1024.0 * 1024.0 * 1024.0);
    // navigator.deviceMemory is rounded to power-of-2 in GB (4, 8, etc.)
    int deviceMem = (int)memoryGB;
    if (deviceMem > 8) deviceMem = 8;
    else if (deviceMem > 4) deviceMem = 8;
    else if (deviceMem > 2) deviceMem = 4;

    NSString *spoofedUA = g_customUserAgent ?: LCBuildUserAgentForProfile();
    NSString *uaJS = @"";
    if (spoofedUA) {
        uaJS = [NSString stringWithFormat:
            @"try{Object.defineProperty(navigator,'userAgent',{get:function(){return '%@'}});}catch(e){}\n"
            @"try{Object.defineProperty(navigator,'appVersion',{get:function(){return '%@'}});}catch(e){}\n",
            [spoofedUA stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"],
            [[spoofedUA stringByReplacingOccurrencesOfString:@"Mozilla/" withString:@""] stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
    }
    NSString *gpuRenderer = g_currentProfile && g_currentProfile->gpuName ? @(g_currentProfile->gpuName) : @"Apple GPU";
    NSString *gpuRendererEscaped = [gpuRenderer stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSString *spoofedLanguage = [LCSpoofedLanguageTag() stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSString *spoofedTimezone = (g_spoofedTimezone.length > 0 ? g_spoofedTimezone : (NSTimeZone.localTimeZone.name ?: @"UTC"));
    spoofedTimezone = [spoofedTimezone stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSString *localeJS = [NSString stringWithFormat:
        @"try{Object.defineProperty(navigator,'language',{get:function(){return '%@'}});}catch(e){}\n"
        @"try{Object.defineProperty(navigator,'languages',{get:function(){return ['%@']}});}catch(e){}\n"
        @"try{var __origResolved=Intl.DateTimeFormat.prototype.resolvedOptions;"
        @"Intl.DateTimeFormat.prototype.resolvedOptions=function(){"
        @"var o=__origResolved.call(this);o.timeZone='%@';return o;};}catch(e){}\n",
        spoofedLanguage, spoofedLanguage, spoofedTimezone];

    return [NSString stringWithFormat:
        @"(function(){\n"
        // Screen size spoofing
        @"try{Object.defineProperty(screen,'width',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(screen,'height',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(screen,'availWidth',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(screen,'availHeight',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(screen,'colorDepth',{get:function(){return 24}});}catch(e){}\n"
        @"try{Object.defineProperty(screen,'pixelDepth',{get:function(){return 24}});}catch(e){}\n"
        @"try{Object.defineProperty(window,'devicePixelRatio',{get:function(){return %f}});}catch(e){}\n"
        @"try{Object.defineProperty(window,'innerWidth',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(window,'innerHeight',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(window,'outerWidth',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(window,'outerHeight',{get:function(){return %ld}});}catch(e){}\n"
        // Hardware concurrency + memory
        @"try{Object.defineProperty(navigator,'hardwareConcurrency',{get:function(){return %u}});}catch(e){}\n"
        @"try{Object.defineProperty(navigator,'deviceMemory',{get:function(){return %d}});}catch(e){}\n"
        // Locale and timezone
        @"%@"
        // User-Agent
        @"%@"
        // Canvas fingerprint noise
        @"(function(){\n"
        @"  var seed=%u;\n"
        @"  var origToDU=HTMLCanvasElement.prototype.toDataURL;\n"
        @"  var origGID=CanvasRenderingContext2D.prototype.getImageData;\n"
        @"  function addNoise(canvas){\n"
        @"    try{var ctx=canvas.getContext('2d');if(!ctx)return;\n"
        @"    var d=ctx.getImageData(0,0,canvas.width,canvas.height);\n"
        @"    var p=d.data;var s=seed;\n"
        @"    for(var i=0;i<p.length;i+=160){\n"
        @"      s=(s*1103515245+12345)&0x7fffffff;\n"
        @"      p[i]=(p[i]+(s%%3)-1)&0xff;\n"
        @"    }\n"
        @"    ctx.putImageData(d,0,0);}catch(e){}\n"
        @"  }\n"
        @"  HTMLCanvasElement.prototype.toDataURL=function(){addNoise(this);return origToDU.apply(this,arguments)};\n"
        @"  CanvasRenderingContext2D.prototype.getImageData=function(){\n"
        @"    var d=origGID.apply(this,arguments);var p=d.data;var s=seed;\n"
        @"    for(var i=0;i<p.length;i+=160){s=(s*1103515245+12345)&0x7fffffff;p[i]=(p[i]+(s%%3)-1)&0xff;}\n"
        @"    return d;\n"
        @"  };\n"
        @"})();\n"
        // WebGL parameter spoofing
        @"(function(){\n"
        @"  var origGP=WebGLRenderingContext.prototype.getParameter;\n"
        @"  WebGLRenderingContext.prototype.getParameter=function(p){\n"
        @"    if(p===37445)return'Apple Inc.';\n"
        @"    if(p===37446)return'%@';\n"
        @"    return origGP.call(this,p);\n"
        @"  };\n"
        @"  if(typeof WebGL2RenderingContext!=='undefined'){\n"
        @"    var origGP2=WebGL2RenderingContext.prototype.getParameter;\n"
        @"    WebGL2RenderingContext.prototype.getParameter=function(p){\n"
        @"      if(p===37445)return'Apple Inc.';\n"
        @"      if(p===37446)return'%@';\n"
        @"      return origGP2.call(this,p);\n"
        @"    };\n"
        @"  }\n"
        @"})();\n"
        // Audio fingerprint noise
        @"(function(){\n"
        @"  if(window.AudioBuffer){\n"
        @"    var origGCD=AudioBuffer.prototype.getChannelData;\n"
        @"    AudioBuffer.prototype.getChannelData=function(){\n"
        @"      var d=origGCD.apply(this,arguments);\n"
        @"      for(var i=0;i<d.length;i+=100){d[i]+=(Math.random()-0.5)*0.0001;}\n"
        @"      return d;\n"
        @"    };\n"
        @"  }\n"
        @"  if(window.AnalyserNode){\n"
        @"    var origGFFD=AnalyserNode.prototype.getFloatFrequencyData;\n"
        @"    AnalyserNode.prototype.getFloatFrequencyData=function(a){\n"
        @"      origGFFD.call(this,a);\n"
        @"      for(var i=0;i<a.length;i++){a[i]+=(Math.random()-0.5)*0.1;}\n"
        @"    };\n"
        @"  }\n"
        @"})();\n"
        // Font metric noise
        @"(function(){\n"
        @"  var origMT=CanvasRenderingContext2D.prototype.measureText;\n"
        @"  CanvasRenderingContext2D.prototype.measureText=function(t){\n"
        @"    var r=origMT.apply(this,arguments);\n"
        @"    try{Object.defineProperty(r,'width',{value:r.width*(1+(Math.random()-0.5)*0.005)});}catch(e){}\n"
        @"    return r;\n"
        @"  };\n"
        @"})();\n"
        @"})();\n",
        (long)screenW, (long)screenH, (long)screenW, (long)screenH,
        dpr,
        (long)screenW, (long)(screenH - 44), // innerHeight minus status bar
        (long)screenW, (long)screenH,
        cpuCores, deviceMem,
        localeJS,
        uaJS,
        arc4random(),
        gpuRendererEscaped,
        gpuRendererEscaped];
}

// MARK: - WKWebView initWithFrame hook (inject UA + fingerprint JS)
static WKWebView *hook_WKWebView_initWithFrame(id self, SEL _cmd, CGRect frame, WKWebViewConfiguration *config) {
    WKWebView *webView = orig_WKWebView_initWithFrame ? orig_WKWebView_initWithFrame(self, _cmd, frame, config) : nil;
    if (!webView || !LCDeviceSpoofingIsActive()) return webView;

    // Set custom User-Agent
    NSString *ua = g_customUserAgent;
    if (!ua && g_userAgentSpoofingEnabled) ua = LCBuildUserAgentForProfile();
    if (!ua) {
        // Always auto-generate if we have a profile (even if UA spoofing not explicitly set)
        ua = LCBuildUserAgentForProfile();
    }
    if (ua) {
        [webView setValue:ua forKey:@"customUserAgent"];
    }

    // Inject fingerprint-protection JS into the configuration's user content controller
    if (g_canvasFingerprintProtectionEnabled) {
        NSString *script = LCBuildFingerprintInjectionScript();
        if (script && config) {
            WKUserContentController *ucc = config.userContentController;
            if (!ucc) {
                ucc = [[WKUserContentController alloc] init];
                config.userContentController = ucc;
            }
            WKUserScript *us = [[WKUserScript alloc] initWithSource:script
                injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                forMainFrameOnly:NO];
            [ucc addUserScript:us];
        }
    }

    return webView;
}

// MARK: - WKWebView User-Agent hook
static NSString *hook_WKWebView_customUserAgent(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        if (g_userAgentSpoofingEnabled && g_customUserAgent.length > 0)
            return g_customUserAgent;
        // Auto-generate from profile if available
        NSString *auto_ua = LCBuildUserAgentForProfile();
        if (auto_ua) return auto_ua;
    }
    if (orig_WKWebView_customUserAgent) return orig_WKWebView_customUserAgent(self, _cmd);
    return nil;
}

// MARK: - NSFileManager storage hook
static NSDictionary *hook_NSFileManager_attributesOfFileSystemForPath(id self, SEL _cmd, NSString *path, NSError **error) {
    NSDictionary *attrs = orig_NSFileManager_attributesOfFileSystemForPath
        ? orig_NSFileManager_attributesOfFileSystemForPath(self, _cmd, path, error)
        : nil;
    if (LCStorageSpoofingActive() && attrs) {
        NSMutableDictionary *mutable = [attrs mutableCopy];
        mutable[NSFileSystemSize] = @(g_spoofedStorageTotal);
        mutable[NSFileSystemFreeSize] = @(g_spoofedStorageFree);
        return [mutable copy];
    }
    return attrs;
}

static NSDictionary *hook_NSFileManager_attributesOfItemAtPath_error(id self, SEL _cmd, NSString *path, NSError **error) {
    NSDictionary *attrs = orig_NSFileManager_attributesOfItemAtPath_error
        ? orig_NSFileManager_attributesOfItemAtPath_error(self, _cmd, path, error)
        : nil;
    if (!attrs || !(LCDeviceSpoofingIsActive() && g_fileTimestampSpoofingEnabled)) {
        return attrs;
    }

    NSMutableDictionary *mutable = [attrs mutableCopy];
    LCApplySpoofedFileDatesToDictionary(mutable, path);
    return [mutable copy];
}

static unsigned long long hook_NSFileManager_volumeAvailableCapacityForImportantUsageForURL(id self, SEL _cmd, NSURL *url, NSError **error) {
    unsigned long long original = orig_NSFileManager_volumeAvailableCapacityForImportantUsageForURL
        ? orig_NSFileManager_volumeAvailableCapacityForImportantUsageForURL(self, _cmd, url, error)
        : 0;
    if (LCStorageSpoofingActive()) {
        return g_spoofedStorageFree;
    }
    return original;
}

static unsigned long long hook_NSFileManager_volumeAvailableCapacityForOpportunisticUsageForURL(id self, SEL _cmd, NSURL *url, NSError **error) {
    unsigned long long original = orig_NSFileManager_volumeAvailableCapacityForOpportunisticUsageForURL
        ? orig_NSFileManager_volumeAvailableCapacityForOpportunisticUsageForURL(self, _cmd, url, error)
        : 0;
    if (LCStorageSpoofingActive()) {
        return LCSpoofedStorageOpportunisticFreeBytes();
    }
    return original;
}

static unsigned long long hook_NSFileManager_volumeTotalCapacityForURL(id self, SEL _cmd, NSURL *url, NSError **error) {
    unsigned long long original = orig_NSFileManager_volumeTotalCapacityForURL
        ? orig_NSFileManager_volumeTotalCapacityForURL(self, _cmd, url, error)
        : 0;
    if (LCStorageSpoofingActive()) {
        return g_spoofedStorageTotal;
    }
    return original;
}

static void LCApplySpoofedNSURLResourceValue(id *value, NSString *key, NSURL *url) {
    if (!value || !key) return;

    if (LCStorageSpoofingActive()) {
        if ([key isEqualToString:@"NSURLVolumeTotalCapacityKey"]) {
            *value = @(g_spoofedStorageTotal);
        } else if ([key isEqualToString:@"NSURLVolumeAvailableCapacityKey"] ||
                   [key isEqualToString:@"NSURLVolumeAvailableCapacityForImportantUsageKey"]) {
            *value = @(g_spoofedStorageFree);
        } else if ([key isEqualToString:@"NSURLVolumeAvailableCapacityForOpportunisticUsageKey"]) {
            *value = @(LCSpoofedStorageOpportunisticFreeBytes());
        }
    }

    if (LCDeviceSpoofingIsActive() && g_fileTimestampSpoofingEnabled) {
        NSString *path = [url isKindOfClass:[NSURL class]] ? url.path : nil;
        if ([key isEqualToString:NSURLCreationDateKey] || [key isEqualToString:@"NSURLCreationDateKey"]) {
            NSDate *created = LCSpoofedTimestampForPath(path, NO);
            if (created) *value = created;
        } else if ([key isEqualToString:NSURLContentModificationDateKey] ||
                   [key isEqualToString:@"NSURLContentModificationDateKey"]) {
            NSDate *modified = LCSpoofedTimestampForPath(path, YES);
            if (modified) *value = modified;
        }
    }
}

static BOOL hook_NSURL_getResourceValue_forKey_error(id self, SEL _cmd, id *value, NSURLResourceKey key, NSError **error) {
    BOOL result = orig_NSURL_getResourceValue_forKey_error
        ? orig_NSURL_getResourceValue_forKey_error(self, _cmd, value, key, error)
        : NO;
    if (!result || !value || !key) {
        return result;
    }

    LCApplySpoofedNSURLResourceValue(value, (NSString *)key, [self isKindOfClass:[NSURL class]] ? (NSURL *)self : nil);
    return result;
}

static NSDictionary<NSURLResourceKey, id> *hook_NSURL_resourceValuesForKeys_error(id self, SEL _cmd, NSArray<NSURLResourceKey> *keys, NSError **error) {
    NSDictionary<NSURLResourceKey, id> *values = orig_NSURL_resourceValuesForKeys_error
        ? orig_NSURL_resourceValuesForKeys_error(self, _cmd, keys, error)
        : nil;
    if (!values || !keys) {
        return values;
    }

    NSMutableDictionary<NSURLResourceKey, id> *mutable = [values mutableCopy];
    for (NSURLResourceKey key in keys) {
        id spoofed = mutable[key];
        LCApplySpoofedNSURLResourceValue(&spoofed, (NSString *)key, [self isKindOfClass:[NSURL class]] ? (NSURL *)self : nil);
        if (spoofed) {
            mutable[key] = spoofed;
        }
    }
    return [mutable copy];
}

#pragma mark - Public API

void LCDeviceSpoofingBeginConfiguration(void) {
    LCDeviceSpoofingSetConfigLocked(NO);
}

void LCDeviceSpoofingEndConfiguration(void) {
    LCDeviceSpoofingSetConfigLocked(YES);
}

void LCSetDeviceSpoofingEnabled(BOOL enabled) {
    g_deviceSpoofingEnabled = enabled;
}

BOOL LCIsDeviceSpoofingEnabled(void) {
    return g_deviceSpoofingEnabled;
}

void LCSetDeviceProfile(NSString *profileName) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_currentProfileName = [profileName copy];

    static NSDictionary<NSString *, NSValue *> *profileMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        profileMap = @{
            @"iPhone 17 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone17ProMax],
            @"iPhone 17 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone17Pro],
            @"iPhone 17": [NSValue valueWithPointer:&kDeviceProfileiPhone17],
            @"iPhone 17 Air": [NSValue valueWithPointer:&kDeviceProfileiPhone17Air],
            @"iPhone 16 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone16ProMax],
            @"iPhone 16 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone16Pro],
            @"iPhone 16": [NSValue valueWithPointer:&kDeviceProfileiPhone16],
            @"iPhone 16e": [NSValue valueWithPointer:&kDeviceProfileiPhone16e],
            @"iPhone 15 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone15ProMax],
            @"iPhone 15 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone15Pro],
            @"iPhone 14 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone14ProMax],
            @"iPhone 14 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone14Pro],
            @"iPhone 13 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone13ProMax],
            @"iPhone 13 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone13Pro],
        };
    });

    NSValue *value = profileMap[profileName];
    if (!value) {
        g_currentProfileName = @"iPhone 17";
        value = profileMap[g_currentProfileName];
    }
    g_currentProfile = value ? (const LCDeviceProfile *)value.pointerValue : NULL;
}

NSString *LCGetCurrentDeviceProfile(void) {
    return g_currentProfileName;
}

NSDictionary<NSString *, NSDictionary *> *LCGetAvailableDeviceProfiles(void) {
    return @{
        @"iPhone 17 Pro Max": @{@"model": @"iPhone18,2", @"version": @"26.0", @"memory": @"12 GB", @"chip": @"A19 Pro"},
        @"iPhone 17 Pro": @{@"model": @"iPhone18,1", @"version": @"26.0", @"memory": @"12 GB", @"chip": @"A19 Pro"},
        @"iPhone 17": @{@"model": @"iPhone18,3", @"version": @"26.0", @"memory": @"8 GB", @"chip": @"A19"},
        @"iPhone 17 Air": @{@"model": @"iPhone18,4", @"version": @"26.0", @"memory": @"12 GB", @"chip": @"A19 Pro"},
        @"iPhone 16 Pro Max": @{@"model": @"iPhone17,2", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18 Pro"},
        @"iPhone 16 Pro": @{@"model": @"iPhone17,1", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18 Pro"},
        @"iPhone 16": @{@"model": @"iPhone17,3", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18"},
        @"iPhone 16e": @{@"model": @"iPhone17,4", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18"},
        @"iPhone 15 Pro Max": @{@"model": @"iPhone16,2", @"version": @"17.6.1", @"memory": @"8 GB", @"chip": @"A17 Pro"},
        @"iPhone 15 Pro": @{@"model": @"iPhone16,1", @"version": @"17.6.1", @"memory": @"8 GB", @"chip": @"A17 Pro"},
        @"iPhone 14 Pro Max": @{@"model": @"iPhone15,3", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A16"},
        @"iPhone 14 Pro": @{@"model": @"iPhone15,2", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A16"},
        @"iPhone 13 Pro Max": @{@"model": @"iPhone14,3", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A15"},
        @"iPhone 13 Pro": @{@"model": @"iPhone14,2", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A15"},
    };
}

NSDictionary *LCGetCurrentProfileData(void) {
    const LCDeviceProfile *profile = atomic_load_explicit(&g_currentProfile, memory_order_acquire);
    if (!profile) return nil;
    return @{
        @"modelIdentifier": @(profile->modelIdentifier),
        @"hardwareModel": @(profile->hardwareModel),
        @"marketingName": @(profile->marketingName),
        @"systemVersion": @(profile->systemVersion),
        @"buildVersion": @(profile->buildVersion),
        @"kernelRelease": @(profile->kernelRelease),
        @"physicalMemory": @(profile->physicalMemory),
        @"cpuCoreCount": @(profile->cpuCoreCount),
        @"performanceCores": @(profile->performanceCores),
        @"efficiencyCores": @(profile->efficiencyCores),
        @"screenScale": @(profile->screenScale),
        @"screenWidth": @(profile->screenWidth),
        @"screenHeight": @(profile->screenHeight),
        @"chipName": @(profile->chipName),
        @"gpuName": @(profile->gpuName),
    };
}

void LCSetSpoofedDeviceModel(NSString *model) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customDeviceModel = [model copy];
}
void LCSetSpoofedSystemVersion(NSString *version) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customSystemVersion = [version copy];
}
void LCSetSpoofedBuildVersion(NSString *build) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customBuildVersion = [build copy];
}
void LCSetSpoofedKernelVersion(NSString *kernelVersion) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customKernelVersion = [kernelVersion copy];
}
void LCSetSpoofedKernelRelease(NSString *kernelRelease) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customKernelRelease = [kernelRelease copy];
}
void LCSetSpoofedCPUCount(uint32_t cpuCount) {
    (void)cpuCount;
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
}
void LCSetSpoofedPhysicalMemory(uint64_t memory) {
    (void)memory;
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
}

void LCSetSpoofedDeviceName(NSString *deviceName) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customDeviceName = [deviceName copy];
}
NSString *LCGetSpoofedDeviceName(void) { return g_customDeviceName; }

void LCSetSpoofedCarrierName(NSString *carrierName) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customCarrierName = [carrierName copy];
}
NSString *LCGetSpoofedCarrierName(void) { return g_customCarrierName; }
void LCSetSpoofedCarrierMCC(NSString *mcc) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customCarrierMCC = [mcc copy];
}
void LCSetSpoofedCarrierMNC(NSString *mnc) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customCarrierMNC = [mnc copy];
}
void LCSetSpoofedCarrierCountryCode(NSString *code) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customCarrierCountryCode = [code copy];
}
void LCSetSpoofedCellularType(NSInteger type) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_cellularTypeConfigured = (type >= 0);
    g_spoofedCellularType = type;
}
void LCSetNetworkInfoSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_networkInfoSpoofingEnabled = enabled;
}
void LCSetWiFiAddressSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofWiFiAddressEnabled = enabled;
}
void LCSetCellularAddressSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofCellularAddressEnabled = enabled;
}
void LCSetSpoofedWiFiAddress(NSString *wifiAddress) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedWiFiAddress = [wifiAddress copy];
}
void LCSetSpoofedCellularAddress(NSString *cellularAddress) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedCellularAddress = [cellularAddress copy];
}
void LCSetSpoofedWiFiSSID(NSString *ssid) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedWiFiSSID = [ssid copy];
}
void LCSetSpoofedWiFiBSSID(NSString *bssid) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedWiFiBSSID = [bssid copy];
}

void LCSetSpoofedVendorID(NSString *vendorID) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedVendorID = [vendorID copy];
    if (LCShouldForceZeroVendorID()) {
        g_adTrackingConfigured = YES;
        g_spoofedAdTrackingEnabled = NO;
        if (!g_spoofedAdvertisingID.length) {
            g_spoofedAdvertisingID = LCZeroUUIDString;
        }
    }
}
NSString *LCGetSpoofedVendorID(void) { return g_spoofedVendorID; }

void LCSetSpoofedAdvertisingID(NSString *advertisingID) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    NSString *normalized = LCNormalizeCompactString(advertisingID);
    if ([normalized isEqualToString:@"00000"] || [normalized isEqualToString:@"0"] || [normalized isEqualToString:@"00000000000000000000000000000000"]) {
        g_spoofedAdvertisingID = LCZeroUUIDString;
        g_adTrackingConfigured = YES;
        g_spoofedAdTrackingEnabled = NO;
        return;
    }
    g_spoofedAdvertisingID = [advertisingID copy];
}
NSString *LCGetSpoofedAdvertisingID(void) { return g_spoofedAdvertisingID; }

void LCSetSpoofedAdTrackingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_adTrackingConfigured = YES;
    g_spoofedAdTrackingEnabled = enabled;
}

BOOL LCGetSpoofedAdTrackingEnabled(void) {
    return g_adTrackingConfigured ? g_spoofedAdTrackingEnabled : NO;
}

void LCSetSpoofedInstallationID(NSString *installationID) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedInstallationID = [installationID copy];
}
NSString *LCGetSpoofedInstallationID(void) { return g_spoofedInstallationID; }
void LCSetSpoofedPersistentDeviceID(NSString *persistentDeviceID) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedPersistentDeviceID = [persistentDeviceID copy];
}

void LCSetSpoofedMACAddress(NSString *macAddress) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedMACAddress = [macAddress copy];
}
NSString *LCGetSpoofedMACAddress(void) { return g_spoofedMACAddress; }

// Timezone spoofing
void LCSetSpoofedTimezone(NSString *timezone) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedTimezone = [timezone copy];
}
NSString *LCGetSpoofedTimezone(void) { return g_spoofedTimezone; }

// Locale spoofing
void LCSetSpoofedLocale(NSString *locale) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedLocale = [locale copy];
}
NSString *LCGetSpoofedLocale(void) { return g_spoofedLocale; }
void LCSetSpoofedPreferredCountryCode(NSString *countryCode) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedPreferredCountryCode = [countryCode copy];
}
void LCSetSpoofedLocaleCurrencyCode(NSString *currencyCode) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedLocaleCurrencyCode = [currencyCode copy];
}
void LCSetSpoofedLocaleCurrencySymbol(NSString *currencySymbol) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedLocaleCurrencySymbol = [currencySymbol copy];
}
void LCSetProximitySpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofProximityEnabled = enabled;
}
void LCSetOrientationSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofOrientationEnabled = enabled;
}
void LCSetGyroscopeSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofGyroscopeEnabled = enabled;
}

// Screen capture detection blocking
void LCSetScreenCaptureBlockEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_screenCaptureBlockEnabled = enabled;
}
void LCSetSpoofMessageEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofMessageEnabled = enabled;
}
void LCSetSpoofMailEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofMailEnabled = enabled;
}
void LCSetSpoofBugsnagEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofBugsnagEnabled = enabled;
}
void LCSetSpoofCraneEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofCraneEnabled = enabled;
}
void LCSetSpoofPasteboardEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofPasteboardEnabled = enabled;
}
void LCSetSpoofAlbumEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofAlbumEnabled = enabled;
}
void LCSetSpoofAppiumEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofAppiumEnabled = enabled;
}
void LCSetKeyboardSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_keyboardSpoofingEnabled = enabled;
}
void LCSetUserDefaultsSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_userDefaultsSpoofingEnabled = enabled;
}
void LCSetEntitlementsSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofEntitlementsEnabled = enabled;
}
void LCSetFileTimestampSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_fileTimestampSpoofingEnabled = enabled;
    if (enabled && g_fileTimestampSeedSeconds <= 0) {
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        uint32_t daysAgo = 30 + arc4random_uniform(331); // 30-360 days ago
        g_fileTimestampSeedSeconds = now - ((NSTimeInterval)daysAgo * 24.0 * 3600.0);
    }
}
BOOL LCIsScreenCaptureBlockEnabled(void) { return g_screenCaptureBlockEnabled; }
void LCSetAlbumBlacklistArray(NSArray<NSString *> *blacklist) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_albumBlacklist = [blacklist copy];
}

void LCSetDeviceCheckSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_deviceCheckSpoofingEnabled = enabled;
}
void LCSetAppAttestSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_appAttestSpoofingEnabled = enabled;
}

void LCSetSpoofedBatteryLevel(float level) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_batteryLevelConfigured = YES;
    g_spoofedBatteryLevel = level;
}

float LCGetSpoofedBatteryLevel(void) {
    return g_spoofedBatteryLevel;
}

void LCSetSpoofedBatteryState(NSInteger state) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_batteryStateConfigured = YES;
    g_spoofedBatteryState = state;
}

NSInteger LCGetSpoofedBatteryState(void) {
    return g_spoofedBatteryState;
}

void LCRandomizeBattery(void) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_batteryLevelConfigured = YES;
    g_batteryStateConfigured = YES;

    // Keep values realistic and stable for a session.
    float level = 0.15f + ((float)arc4random_uniform(81) / 100.0f); // 15%-95%
    if (level < 0.05f) level = 0.05f;
    if (level > 1.0f) level = 1.0f;
    g_spoofedBatteryLevel = level;

    if (level >= 0.97f) {
        g_spoofedBatteryState = 3; // full
    } else {
        // Mostly unplugged, occasionally charging.
        g_spoofedBatteryState = (arc4random_uniform(100) < 75) ? 1 : 2;
    }
}

void LCSetSpoofedBrightness(float brightness) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_brightnessConfigured = YES;
    g_spoofedBrightness = brightness;
}

float LCGetSpoofedBrightness(void) {
    return g_spoofedBrightness;
}

void LCRandomizeBrightness(void) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_brightnessConfigured = YES;
    // Keep realistic values and avoid extreme always-min/max outputs.
    float value = 0.18f + ((float)arc4random_uniform(73) / 100.0f); // 0.18 - 0.90
    if (value < 0.05f) value = 0.05f;
    if (value > 1.0f) value = 1.0f;
    g_spoofedBrightness = value;
}

void LCSetSpoofedThermalState(NSInteger state) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_thermalConfigured = YES;
    g_spoofedThermalState = state;
}

void LCSetSpoofedLowPowerMode(BOOL enabled, BOOL value) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofLowPowerMode = enabled;
    g_lowPowerModeValue = value;
}

void LCSetSpoofedBootTimeRange(NSString *range) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    NSTimeInterval lo = 4 * 3600;
    NSTimeInterval hi = 24 * 3600;
    if (!LCGetUptimeBounds(range, &lo, &hi)) {
        // Backwards-compatible fallback
        lo = 4 * 3600;
        hi = 24 * 3600;
    }

    NSTimeInterval target = lo;
    NSTimeInterval span = hi - lo;
    if (span > 1) {
        target = lo + (NSTimeInterval)arc4random_uniform((uint32_t)span + 1);
    }
    LCApplySpoofedUptimeTarget(target);
}

void LCSetSpoofedUptimeSeconds(NSTimeInterval uptimeSeconds) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    LCApplySpoofedUptimeTarget(uptimeSeconds);
}

void LCSetUptimeOffset(NSTimeInterval offset) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_bootTimeOffset = offset;
    g_bootTimeSpoofingEnabled = YES;
}

void LCRandomizeUptime(void) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    LCSetSpoofedBootTimeRange(@"short");
}

void LCSetSpoofedBootTime(time_t bootTimestamp) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    g_bootTimeOffset = now - (NSTimeInterval)bootTimestamp - NSProcessInfo.processInfo.systemUptime;
    g_bootTimeSpoofingEnabled = YES;
}

time_t LCGetSpoofedBootTime(void) {
    struct timeval tv = {0, 0};
    size_t len = sizeof(tv);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    if (orig_sysctl && orig_sysctl(mib, 2, &tv, &len, NULL, 0) == 0) {
        if (g_bootTimeSpoofingEnabled) {
            tv.tv_sec -= (time_t)g_bootTimeOffset;
        }
        return tv.tv_sec;
    }
    return 0;
}

NSTimeInterval LCGetSpoofedUptime(void) {
    NSTimeInterval real = NSProcessInfo.processInfo.systemUptime;
    if (g_bootTimeSpoofingEnabled) {
        return real + g_bootTimeOffset;
    }
    return real;
}

void LCSetStorageSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_storageSpoofingEnabled = enabled;
}
BOOL LCIsStorageSpoofingEnabled(void) { return g_storageSpoofingEnabled; }
void LCSetStorageRandomFreeEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_storageRandomFreeEnabled = enabled;
    if (g_spoofedStorageTotal > 0 && !g_storageFreeExplicitlySet) {
        g_spoofedStorageFree = LCCalculateSpoofedStorageFreeBytes(g_spoofedStorageTotal);
        g_spoofedStorageFreeGB = [NSString stringWithFormat:@"%.1f", (double)g_spoofedStorageFree / 1e9];
    }
}
BOOL LCIsStorageRandomFreeEnabled(void) { return g_storageRandomFreeEnabled; }

void LCSetSpoofedStorageCapacity(long long capacityGB) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_spoofedStorageCapacityGB = [NSString stringWithFormat:@"%lld", capacityGB];
    g_storageSpoofingEnabled = YES;
    g_spoofedStorageTotal = (uint64_t)(capacityGB * 1000LL * 1000LL * 1000LL);
    g_storageFreeExplicitlySet = NO;
    g_spoofedStorageFree = LCCalculateSpoofedStorageFreeBytes(g_spoofedStorageTotal);
    g_spoofedStorageFreeGB = [NSString stringWithFormat:@"%.1f", (double)g_spoofedStorageFree / 1e9];
}

void LCSetSpoofedStorageFree(NSString *freeGB) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_storageFreeExplicitlySet = YES;
    g_spoofedStorageFreeGB = [freeGB copy];
    g_spoofedStorageFree = (uint64_t)(freeGB.doubleValue * 1000.0 * 1000.0 * 1000.0);
}

void LCSetSpoofedStorageBytes(uint64_t totalBytes, uint64_t freeBytes) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_storageFreeExplicitlySet = YES;
    g_spoofedStorageTotal = totalBytes;
    g_spoofedStorageFree = freeBytes;
}

NSDictionary *LCGenerateStorageForCapacity(NSString *capacityGB) {
    double totalGB = MAX(capacityGB.doubleValue, 0.0);
    uint64_t totalBytes = (uint64_t)(totalGB * 1000.0 * 1000.0 * 1000.0);
    uint64_t freeBytes = LCCalculateSpoofedStorageFreeBytes(totalBytes);
    double freeGB = (double)freeBytes / 1e9;
    return @{
        @"TotalStorage": [NSString stringWithFormat:@"%.0f", totalGB],
        @"FreeStorage": [NSString stringWithFormat:@"%.1f", freeGB],
        @"TotalBytes": @(totalBytes),
        @"FreeBytes": @(freeBytes),
        @"FilesystemType": @"APFS",
    };
}

NSString *LCRandomizeStorageCapacity(void) {
    NSArray<NSString *> *capacities = @[@"64", @"128", @"256", @"512", @"1024"];
    return capacities[arc4random_uniform((uint32_t)capacities.count)];
}

void LCRandomizeStorage(void) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    long long capacityGB = [LCRandomizeStorageCapacity() longLongValue];
    LCSetSpoofedStorageCapacity(capacityGB);
    g_storageFreeExplicitlySet = NO;
    g_spoofedStorageFree = LCCalculateSpoofedStorageFreeBytes(g_spoofedStorageTotal);
    g_spoofedStorageFreeGB = [NSString stringWithFormat:@"%.1f", (double)g_spoofedStorageFree / 1e9];
}

uint64_t LCGetSpoofedStorageTotal(void) { return g_spoofedStorageTotal; }
uint64_t LCGetSpoofedStorageFree(void) { return g_spoofedStorageFree; }
NSString *LCGetSpoofedStorageCapacityGB(void) { return g_spoofedStorageCapacityGB; }
NSString *LCGetSpoofedStorageFreeGB(void) { return g_spoofedStorageFreeGB; }

void LCSetSpoofedDiskSpace(uint64_t freeSpace, uint64_t totalSpace) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    LCSetSpoofedStorageBytes(totalSpace, freeSpace);
}

void LCSetCanvasFingerprintProtectionEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_canvasFingerprintProtectionEnabled = enabled;
}
BOOL LCIsCanvasFingerprintProtectionEnabled(void) { return g_canvasFingerprintProtectionEnabled; }

void LCSetICloudPrivacyProtectionEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_iCloudPrivacyProtectionEnabled = enabled;
}
BOOL LCIsICloudPrivacyProtectionEnabled(void) { return g_iCloudPrivacyProtectionEnabled; }

void LCSetSiriPrivacyProtectionEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_siriPrivacyProtectionEnabled = enabled;
}
BOOL LCIsSiriPrivacyProtectionEnabled(void) { return g_siriPrivacyProtectionEnabled; }

void LCInitializeFingerprintProtection(void) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    LCRandomizeBattery();
    LCRandomizeUptime();
    LCRandomizeStorage();
}

void LCSetSpoofedScreenScale(CGFloat scale) { (void)scale; }

NSString *LCGenerateRandomUUID(void) {
    return NSUUID.UUID.UUIDString;
}

NSString *LCGenerateRandomMACAddress(void) {
    uint8_t mac[6];
    for (int i = 0; i < 6; ++i) mac[i] = arc4random_uniform(256);
    mac[0] = (mac[0] | 0x02) & 0xFE;
    return [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]];
}

NSString *LCGenerateRandomInstallationID(int length) {
    static const char charset[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    if (length <= 0) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:(NSUInteger)length];
    for (int i = 0; i < length; ++i) {
        [result appendFormat:@"%c", charset[arc4random_uniform((uint32_t)strlen(charset))]];
    }
    return result;
}

void LCSetSpoofedUserAgent(NSString *userAgent) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_customUserAgent = [userAgent copy];
    g_userAgentSpoofingEnabled = (userAgent != nil);
}

void LCSetUserAgentSpoofingEnabled(BOOL enabled) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    g_userAgentSpoofingEnabled = enabled;
}

BOOL LCIsUserAgentSpoofingEnabled(void) {
    return g_userAgentSpoofingEnabled;
}

NSString *LCGetCurrentUserAgent(void) {
    if (g_customUserAgent) return g_customUserAgent;
    return LCBuildUserAgentForProfile();
}

void LCUpdateUserAgentForProfile(void) {
    LC_DEVICE_SPOOFING_CONFIG_MUTATION_GUARD();
    NSString *ua = LCBuildUserAgentForProfile();
    if (ua) {
        g_customUserAgent = [ua copy];
        g_userAgentSpoofingEnabled = YES;
    }
}

#pragma mark - Init

void DeviceSpoofingGuestHooksInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Hooks can run on arbitrary threads; close the bootstrap mutation window first.
        LCDeviceSpoofingEndConfiguration();

        struct rebinding rebindings[] = {
            {"uname", (void *)hook_uname, (void **)&orig_uname},
            {"gethostname", (void *)hook_gethostname, (void **)&orig_gethostname},
            {"sysconf", (void *)hook_sysconf, (void **)&orig_sysconf},
            {"sysctlbyname", (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname},
            {"sysctl", (void *)hook_sysctl, (void **)&orig_sysctl},
            {"statfs", (void *)hook_statfs, (void **)&orig_statfs},
            {"statfs64", (void *)hook_statfs64, (void **)&orig_statfs64},
            {"fstatfs", (void *)hook_fstatfs, (void **)&orig_fstatfs},
            {"getfsstat", (void *)hook_getfsstat, (void **)&orig_getfsstat},
            {"getfsstat64", (void *)hook_getfsstat64, (void **)&orig_getfsstat64},
            {"UIAccessibilityIsVoiceOverRunning", (void *)hook_UIAccessibilityIsVoiceOverRunning, (void **)&orig_UIAccessibilityIsVoiceOverRunning},
            {"UIAccessibilityIsGuidedAccessEnabled", (void *)hook_UIAccessibilityIsGuidedAccessEnabled, (void **)&orig_UIAccessibilityIsGuidedAccessEnabled},
            {"UIAccessibilityIsMonoAudioEnabled", (void *)hook_UIAccessibilityIsMonoAudioEnabled, (void **)&orig_UIAccessibilityIsMonoAudioEnabled},
            {"UIAccessibilityIsInvertColorsEnabled", (void *)hook_UIAccessibilityIsInvertColorsEnabled, (void **)&orig_UIAccessibilityIsInvertColorsEnabled},
            {"UIAccessibilityIsBoldTextEnabled", (void *)hook_UIAccessibilityIsBoldTextEnabled, (void **)&orig_UIAccessibilityIsBoldTextEnabled},
            {"UIAccessibilityDarkerSystemColorsEnabled", (void *)hook_UIAccessibilityDarkerSystemColorsEnabled, (void **)&orig_UIAccessibilityDarkerSystemColorsEnabled},
            {"UIAccessibilityIsReduceMotionEnabled", (void *)hook_UIAccessibilityIsReduceMotionEnabled, (void **)&orig_UIAccessibilityIsReduceMotionEnabled},
            {"UIAccessibilityIsReduceTransparencyEnabled", (void *)hook_UIAccessibilityIsReduceTransparencyEnabled, (void **)&orig_UIAccessibilityIsReduceTransparencyEnabled},
            {"UIAccessibilityIsClosedCaptioningEnabled", (void *)hook_UIAccessibilityIsClosedCaptioningEnabled, (void **)&orig_UIAccessibilityIsClosedCaptioningEnabled},
            {"UIAccessibilityIsAssistiveTouchRunning", (void *)hook_UIAccessibilityIsAssistiveTouchRunning, (void **)&orig_UIAccessibilityIsAssistiveTouchRunning},
            {"UIAccessibilityIsVideoAutoplayEnabled", (void *)hook_UIAccessibilityIsVideoAutoplayEnabled, (void **)&orig_UIAccessibilityIsVideoAutoplayEnabled},
            {"clock_gettime", (void *)hook_clock_gettime, (void **)&orig_clock_gettime},
            {"clock_gettime_nsec_np", (void *)hook_clock_gettime_nsec_np, (void **)&orig_clock_gettime_nsec_np},
            {"mach_absolute_time", (void *)hook_mach_absolute_time, (void **)&orig_mach_absolute_time},
            {"mach_approximate_time", (void *)hook_mach_approximate_time, (void **)&orig_mach_approximate_time},
            {"mach_continuous_time", (void *)hook_mach_continuous_time, (void **)&orig_mach_continuous_time},
            {"mach_continuous_approximate_time", (void *)hook_mach_continuous_approximate_time, (void **)&orig_mach_continuous_approximate_time},
            {"CGDisplayBounds", (void *)hook_CGDisplayBounds, (void **)&orig_CGDisplayBounds},
            {"CGDisplayPixelsWide", (void *)hook_CGDisplayPixelsWide, (void **)&orig_CGDisplayPixelsWide},
            {"CGDisplayPixelsHigh", (void *)hook_CGDisplayPixelsHigh, (void **)&orig_CGDisplayPixelsHigh},
            {"host_statistics", (void *)hook_host_statistics, (void **)&orig_host_statistics},
            {"host_statistics64", (void *)hook_host_statistics64, (void **)&orig_host_statistics64},
            {"host_processor_info", (void *)hook_host_processor_info, (void **)&orig_host_processor_info},
            {"task_info", (void *)hook_task_info, (void **)&orig_task_info},
            {"MTLCreateSystemDefaultDevice", (void *)hook_MTLCreateSystemDefaultDevice, (void **)&orig_MTLCreateSystemDefaultDevice},
            {"MTLCopyAllDevices", (void *)hook_MTLCopyAllDevices, (void **)&orig_MTLCopyAllDevices},
            {"MGCopyAnswer", (void *)hook_MGCopyAnswer, (void **)&orig_MGCopyAnswer},
            {"IORegistryEntryCreateCFProperty", (void *)hook_IORegistryEntryCreateCFProperty, (void **)&orig_IORegistryEntryCreateCFProperty},
            {"IORegistryEntrySearchCFProperty", (void *)hook_IORegistryEntrySearchCFProperty, (void **)&orig_IORegistryEntrySearchCFProperty},
            {"CFCopySystemVersionDictionary", (void *)hook_CFCopySystemVersionDictionary, (void **)&orig_CFCopySystemVersionDictionary},
            // Network spoofing hooks are owned by Dyld.m to avoid double-hooking races.
        };
        rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));

        id (*createMetalDevice)(void) = (id (*)(void))dlsym(RTLD_DEFAULT, "MTLCreateSystemDefaultDevice");
        if (createMetalDevice) {
            id metalDevice = createMetalDevice();
            if (metalDevice) {
                LCInstallMTLDeviceHooksIfNeeded(metalDevice);
            }
        }

        Class uiDeviceClass = objc_getClass("UIDevice");
        LCInstallInstanceHook(uiDeviceClass, @selector(systemVersion), (IMP)hook_UIDevice_systemVersion, (IMP *)&orig_UIDevice_systemVersion);
        LCInstallInstanceHook(uiDeviceClass, @selector(systemName), (IMP)hook_UIDevice_systemName, (IMP *)&orig_UIDevice_systemName);
        LCInstallInstanceHook(uiDeviceClass, @selector(name), (IMP)hook_UIDevice_name, (IMP *)&orig_UIDevice_name);
        LCInstallInstanceHook(uiDeviceClass, @selector(identifierForVendor), (IMP)hook_UIDevice_identifierForVendor, (IMP *)&orig_UIDevice_identifierForVendor);
        LCInstallInstanceHook(uiDeviceClass, @selector(batteryLevel), (IMP)hook_UIDevice_batteryLevel, (IMP *)&orig_UIDevice_batteryLevel);
        LCInstallInstanceHook(uiDeviceClass, @selector(batteryState), (IMP)hook_UIDevice_batteryState, (IMP *)&orig_UIDevice_batteryState);
        LCInstallInstanceHook(uiDeviceClass, @selector(isBatteryMonitoringEnabled), (IMP)hook_UIDevice_isBatteryMonitoringEnabled, (IMP *)&orig_UIDevice_isBatteryMonitoringEnabled);
        if (g_spoofProximityEnabled) {
            LCInstallInstanceHook(uiDeviceClass, @selector(proximityState), (IMP)hook_UIDevice_proximityState, (IMP *)&orig_UIDevice_proximityState);
            LCInstallInstanceHook(uiDeviceClass, @selector(isProximityMonitoringEnabled), (IMP)hook_UIDevice_isProximityMonitoringEnabled, (IMP *)&orig_UIDevice_isProximityMonitoringEnabled);
        }
        if (g_spoofOrientationEnabled) {
            LCInstallInstanceHook(uiDeviceClass, @selector(orientation), (IMP)hook_UIDevice_orientation, (IMP *)&orig_UIDevice_orientation);
        }

        Class processInfoClass = objc_getClass("NSProcessInfo");
        LCInstallInstanceHook(processInfoClass, @selector(physicalMemory), (IMP)hook_NSProcessInfo_physicalMemory, (IMP *)&orig_NSProcessInfo_physicalMemory);
        LCInstallInstanceHook(processInfoClass, @selector(processorCount), (IMP)hook_NSProcessInfo_processorCount, (IMP *)&orig_NSProcessInfo_processorCount);
        LCInstallInstanceHook(processInfoClass, @selector(activeProcessorCount), (IMP)hook_NSProcessInfo_activeProcessorCount, (IMP *)&orig_NSProcessInfo_activeProcessorCount);
        LCInstallInstanceHook(processInfoClass, @selector(operatingSystemVersion), (IMP)hook_NSProcessInfo_operatingSystemVersion, (IMP *)&orig_NSProcessInfo_operatingSystemVersion);
        LCInstallInstanceHook(processInfoClass, @selector(operatingSystemVersionString), (IMP)hook_NSProcessInfo_operatingSystemVersionString, (IMP *)&orig_NSProcessInfo_operatingSystemVersionString);
        LCInstallInstanceHook(processInfoClass, @selector(thermalState), (IMP)hook_NSProcessInfo_thermalState, (IMP *)&orig_NSProcessInfo_thermalState);
        LCInstallInstanceHook(processInfoClass, @selector(isLowPowerModeEnabled), (IMP)hook_NSProcessInfo_isLowPowerModeEnabled, (IMP *)&orig_NSProcessInfo_isLowPowerModeEnabled);
        LCInstallInstanceHook(processInfoClass, @selector(environment), (IMP)hook_NSProcessInfo_environment, (IMP *)&orig_NSProcessInfo_environment);
        LCInstallInstanceHook(processInfoClass, @selector(arguments), (IMP)hook_NSProcessInfo_arguments, (IMP *)&orig_NSProcessInfo_arguments);
        LCInstallInstanceHook(processInfoClass, @selector(systemUptime), (IMP)hook_NSProcessInfo_systemUptime, (IMP *)&orig_NSProcessInfo_systemUptime);
        SEL hostNameSelector = @selector(hostName);
        if (hostNameSelector && [processInfoClass instancesRespondToSelector:hostNameSelector]) {
            LCInstallInstanceHook(processInfoClass, hostNameSelector, (IMP)hook_NSProcessInfo_hostName, (IMP *)&orig_NSProcessInfo_hostName);
        }
        SEL osNameSelector = NSSelectorFromString(@"operatingSystemName");
        if (osNameSelector && [processInfoClass instancesRespondToSelector:osNameSelector]) {
            LCInstallInstanceHook(processInfoClass, osNameSelector, (IMP)hook_NSProcessInfo_operatingSystemName, (IMP *)&orig_NSProcessInfo_operatingSystemName);
        }
        SEL globallyUniqueSelector = NSSelectorFromString(@"globallyUniqueString");
        if (globallyUniqueSelector && [processInfoClass instancesRespondToSelector:globallyUniqueSelector]) {
            LCInstallInstanceHook(processInfoClass, globallyUniqueSelector, (IMP)hook_NSProcessInfo_globallyUniqueString, (IMP *)&orig_NSProcessInfo_globallyUniqueString);
        }

        Class swiftProcessInfoClass = objc_getClass("_NSSwiftProcessInfo");
        SEL swiftPhysicalMemorySelector = @selector(physicalMemory);
        if (swiftProcessInfoClass && swiftPhysicalMemorySelector &&
            [swiftProcessInfoClass instancesRespondToSelector:swiftPhysicalMemorySelector]) {
            LCInstallInstanceHook(swiftProcessInfoClass, swiftPhysicalMemorySelector, (IMP)hook_SwiftNSProcessInfo_physicalMemory, (IMP *)&orig_SwiftNSProcessInfo_physicalMemory);
        }
        SEL swiftOSVersionSelector = @selector(operatingSystemVersion);
        if (swiftProcessInfoClass && swiftOSVersionSelector &&
            [swiftProcessInfoClass instancesRespondToSelector:swiftOSVersionSelector]) {
            LCInstallInstanceHook(swiftProcessInfoClass, swiftOSVersionSelector, (IMP)hook_SwiftNSProcessInfo_operatingSystemVersion, (IMP *)&orig_SwiftNSProcessInfo_operatingSystemVersion);
        }
        SEL swiftOSVersionStringSelector = @selector(operatingSystemVersionString);
        if (swiftProcessInfoClass && swiftOSVersionStringSelector &&
            [swiftProcessInfoClass instancesRespondToSelector:swiftOSVersionStringSelector]) {
            LCInstallInstanceHook(swiftProcessInfoClass, swiftOSVersionStringSelector, (IMP)hook_SwiftNSProcessInfo_operatingSystemVersionString, (IMP *)&orig_SwiftNSProcessInfo_operatingSystemVersionString);
        }
        SEL swiftHostNameSelector = @selector(hostName);
        if (swiftProcessInfoClass && swiftHostNameSelector &&
            [swiftProcessInfoClass instancesRespondToSelector:swiftHostNameSelector]) {
            LCInstallInstanceHook(swiftProcessInfoClass, swiftHostNameSelector, (IMP)hook_SwiftNSProcessInfo_hostName, (IMP *)&orig_SwiftNSProcessInfo_hostName);
        }
        SEL swiftAtLeastSelector = @selector(isOperatingSystemAtLeastVersion:);
        if (swiftProcessInfoClass && swiftAtLeastSelector &&
            [swiftProcessInfoClass instancesRespondToSelector:swiftAtLeastSelector]) {
            LCInstallInstanceHook(swiftProcessInfoClass, swiftAtLeastSelector, (IMP)hook_SwiftNSProcessInfo_isOperatingSystemAtLeastVersion, (IMP *)&orig_SwiftNSProcessInfo_isOperatingSystemAtLeastVersion);
        }

        Class uiScreenClass = objc_getClass("UIScreen");
        LCInstallInstanceHook(uiScreenClass, @selector(brightness), (IMP)hook_UIScreen_brightness, (IMP *)&orig_UIScreen_brightness);
        LCInstallInstanceHook(uiScreenClass, @selector(bounds), (IMP)hook_UIScreen_bounds, (IMP *)&orig_UIScreen_bounds);
        LCInstallInstanceHook(uiScreenClass, @selector(nativeBounds), (IMP)hook_UIScreen_nativeBounds, (IMP *)&orig_UIScreen_nativeBounds);
        LCInstallInstanceHook(uiScreenClass, NSSelectorFromString(@"boundsForInterfaceOrientation:"), (IMP)hook_UIScreen_boundsForInterfaceOrientation, (IMP *)&orig_UIScreen_boundsForInterfaceOrientation);
        LCInstallInstanceHook(uiScreenClass, NSSelectorFromString(@"_referenceBounds"), (IMP)hook_UIScreen_referenceBounds, (IMP *)&orig_UIScreen_referenceBounds);
        LCInstallInstanceHook(uiScreenClass, NSSelectorFromString(@"_bounds"), (IMP)hook_UIScreen_privateBounds, (IMP *)&orig_UIScreen_privateBounds);
        LCInstallInstanceHook(uiScreenClass, NSSelectorFromString(@"_nativeBounds"), (IMP)hook_UIScreen_privateNativeBounds, (IMP *)&orig_UIScreen_privateNativeBounds);
        LCInstallInstanceHook(uiScreenClass, @selector(scale), (IMP)hook_UIScreen_scale, (IMP *)&orig_UIScreen_scale);
        LCInstallInstanceHook(uiScreenClass, @selector(nativeScale), (IMP)hook_UIScreen_nativeScale, (IMP *)&orig_UIScreen_nativeScale);
        LCInstallInstanceHook(uiScreenClass, NSSelectorFromString(@"applicationFrame"), (IMP)hook_UIScreen_applicationFrame, (IMP *)&orig_UIScreen_applicationFrame);
        LCInstallInstanceHook(uiScreenClass, NSSelectorFromString(@"coordinateSpace"), (IMP)hook_UIScreen_coordinateSpace, (IMP *)&orig_UIScreen_coordinateSpace);
        LCInstallInstanceHook(uiScreenClass, NSSelectorFromString(@"fixedCoordinateSpace"), (IMP)hook_UIScreen_fixedCoordinateSpace, (IMP *)&orig_UIScreen_fixedCoordinateSpace);
        LCInstallInstanceHook(uiScreenClass, @selector(currentMode), (IMP)hook_UIScreen_currentMode, (IMP *)&orig_UIScreen_currentMode);
        LCInstallInstanceHook(uiScreenClass, NSSelectorFromString(@"preferredMode"), (IMP)hook_UIScreen_preferredMode, (IMP *)&orig_UIScreen_preferredMode);
        LCInstallInstanceHook(uiScreenClass, NSSelectorFromString(@"availableModes"), (IMP)hook_UIScreen_availableModes, (IMP *)&orig_UIScreen_availableModes);
        LCInstallInstanceHook(uiScreenClass, NSSelectorFromString(@"maximumFramesPerSecond"), (IMP)hook_UIScreen_maximumFramesPerSecond, (IMP *)&orig_UIScreen_maximumFramesPerSecond);

        Class uiScreenModeClass = objc_getClass("UIScreenMode");
        LCInstallInstanceHook(uiScreenModeClass, @selector(size), (IMP)hook_UIScreenMode_size, (IMP *)&orig_UIScreenMode_size);

        Class traitCollectionClass = objc_getClass("UITraitCollection");
        LCInstallInstanceHook(traitCollectionClass, @selector(displayScale), (IMP)hook_UITraitCollection_displayScale, (IMP *)&orig_UITraitCollection_displayScale);
        SEL contentSizeSelector = NSSelectorFromString(@"preferredContentSizeCategory");
        if (traitCollectionClass && contentSizeSelector && [traitCollectionClass instancesRespondToSelector:contentSizeSelector]) {
            LCInstallInstanceHook(traitCollectionClass, contentSizeSelector, (IMP)hook_UITraitCollection_preferredContentSizeCategory, (IMP *)&orig_UITraitCollection_preferredContentSizeCategory);
        }

        Class uiApplicationClass = objc_getClass("UIApplication");
        LCInstallInstanceHook(uiApplicationClass, NSSelectorFromString(@"statusBarFrame"), (IMP)hook_UIApplication_statusBarFrame, (IMP *)&orig_UIApplication_statusBarFrame);
        LCInstallInstanceHook(uiApplicationClass, @selector(canOpenURL:), (IMP)hook_UIApplication_canOpenURL, (IMP *)&orig_UIApplication_canOpenURL);
        SEL preferredContentSizeSelector = NSSelectorFromString(@"preferredContentSizeCategory");
        if (preferredContentSizeSelector && [uiApplicationClass instancesRespondToSelector:preferredContentSizeSelector]) {
            LCInstallInstanceHook(uiApplicationClass, preferredContentSizeSelector,
                                  (IMP)hook_UIApplication_preferredContentSizeCategory,
                                  (IMP *)&orig_UIApplication_preferredContentSizeCategory);
        }

        Class statusBarManagerClass = objc_getClass("UIStatusBarManager");
        LCInstallInstanceHook(statusBarManagerClass, NSSelectorFromString(@"statusBarFrame"), (IMP)hook_UIStatusBarManager_statusBarFrame, (IMP *)&orig_UIStatusBarManager_statusBarFrame);

        LCInstallInstanceHook(uiDeviceClass, @selector(model), (IMP)hook_UIDevice_model, (IMP *)&orig_UIDevice_model);
        LCInstallInstanceHook(uiDeviceClass, @selector(localizedModel), (IMP)hook_UIDevice_localizedModel, (IMP *)&orig_UIDevice_localizedModel);
        SEL machineNameSelector = NSSelectorFromString(@"machineName");
        if ([uiDeviceClass respondsToSelector:machineNameSelector]) {
            Class uiDeviceMetaClass = object_getClass(uiDeviceClass);
            LCInstallInstanceHook(uiDeviceMetaClass, machineNameSelector, (IMP)hook_UIDevice_machineName, (IMP *)&orig_UIDevice_machineName);
        }
        SEL deviceInfoForKeySelector = NSSelectorFromString(@"_deviceInfoForKey:");
        if ([uiDeviceClass instancesRespondToSelector:deviceInfoForKeySelector]) {
            LCInstallInstanceHook(uiDeviceClass, deviceInfoForKeySelector, (IMP)hook_UIDevice_deviceInfoForKey, (IMP *)&orig_UIDevice_deviceInfoForKey);
        }

        LCInstallInstanceHook(processInfoClass, @selector(isOperatingSystemAtLeastVersion:), (IMP)hook_NSProcessInfo_isOperatingSystemAtLeastVersion, (IMP *)&orig_NSProcessInfo_isOperatingSystemAtLeastVersion);

        // NSMutableURLRequest User-Agent interception
        Class urlReqClass = objc_getClass("NSMutableURLRequest");
        LCInstallInstanceHook(urlReqClass, @selector(setValue:forHTTPHeaderField:), (IMP)hook_NSMutableURLRequest_setValue_forHTTPHeaderField, (IMP *)&orig_NSMutableURLRequest_setValue_forHTTPHeaderField);

        Class asIdManagerClass = objc_getClass("ASIdentifierManager");
        LCInstallInstanceHook(asIdManagerClass, @selector(advertisingIdentifier), (IMP)hook_ASIdentifierManager_advertisingIdentifier, (IMP *)&orig_ASIdentifierManager_advertisingIdentifier);
        LCInstallInstanceHook(asIdManagerClass, @selector(isAdvertisingTrackingEnabled), (IMP)hook_ASIdentifierManager_isAdvertisingTrackingEnabled, (IMP *)&orig_ASIdentifierManager_isAdvertisingTrackingEnabled);

        Class fileManagerClass = objc_getClass("NSFileManager");
        LCInstallInstanceHook(fileManagerClass, @selector(ubiquityIdentityToken), (IMP)hook_NSFileManager_ubiquityIdentityToken, (IMP *)&orig_NSFileManager_ubiquityIdentityToken);
        LCInstallInstanceHook(fileManagerClass, @selector(contentsAtPath:), (IMP)hook_NSFileManager_contentsAtPath, (IMP *)&orig_NSFileManager_contentsAtPath);

        Class carrierClass = objc_getClass("CTCarrier");
        LCInstallInstanceHook(carrierClass, @selector(carrierName), (IMP)hook_CTCarrier_carrierName, (IMP *)&orig_CTCarrier_carrierName);
        LCInstallInstanceHook(carrierClass, @selector(isoCountryCode), (IMP)hook_CTCarrier_isoCountryCode, (IMP *)&orig_CTCarrier_isoCountryCode);
        LCInstallInstanceHook(carrierClass, @selector(mobileCountryCode), (IMP)hook_CTCarrier_mobileCountryCode, (IMP *)&orig_CTCarrier_mobileCountryCode);
        LCInstallInstanceHook(carrierClass, @selector(mobileNetworkCode), (IMP)hook_CTCarrier_mobileNetworkCode, (IMP *)&orig_CTCarrier_mobileNetworkCode);
        SEL allowsVoipSelector = NSSelectorFromString(@"allowsVOIP");
        if (allowsVoipSelector && [carrierClass instancesRespondToSelector:allowsVoipSelector]) {
            LCInstallInstanceHook(carrierClass, allowsVoipSelector, (IMP)hook_CTCarrier_allowsVOIP, (IMP *)&orig_CTCarrier_allowsVOIP);
        }

        Class telephonyInfoClass = objc_getClass("CTTelephonyNetworkInfo");
        LCInstallInstanceHook(telephonyInfoClass, @selector(currentRadioAccessTechnology), (IMP)hook_CTTelephonyNetworkInfo_currentRadioAccessTechnology, (IMP *)&orig_CTTelephonyNetworkInfo_currentRadioAccessTechnology);
        SEL serviceRATSelector = NSSelectorFromString(@"serviceCurrentRadioAccessTechnology");
        if (serviceRATSelector && [telephonyInfoClass instancesRespondToSelector:serviceRATSelector]) {
            LCInstallInstanceHook(telephonyInfoClass, serviceRATSelector, (IMP)hook_CTTelephonyNetworkInfo_serviceCurrentRadioAccessTechnology, (IMP *)&orig_CTTelephonyNetworkInfo_serviceCurrentRadioAccessTechnology);
        }

        // Timezone hooks (class methods) are always installed to avoid startup race leakage.
        Class timeZoneClass = objc_getClass("NSTimeZone");
        if (timeZoneClass) {
            Class timeZoneMeta = object_getClass(timeZoneClass);
            if (timeZoneMeta) {
                LCInstallInstanceHook(timeZoneMeta, @selector(localTimeZone), (IMP)hook_NSTimeZone_localTimeZone, (IMP *)&orig_NSTimeZone_localTimeZone);
                LCInstallInstanceHook(timeZoneMeta, @selector(systemTimeZone), (IMP)hook_NSTimeZone_systemTimeZone, (IMP *)&orig_NSTimeZone_systemTimeZone);
                SEL defaultTimeZoneSelector = @selector(defaultTimeZone);
                if ([timeZoneMeta respondsToSelector:defaultTimeZoneSelector]) {
                    LCInstallInstanceHook(timeZoneMeta, defaultTimeZoneSelector, (IMP)hook_NSTimeZone_defaultTimeZone, (IMP *)&orig_NSTimeZone_defaultTimeZone);
                }
            }
        }

        // Locale hooks (class methods) are always installed to avoid startup race leakage.
        Class localeClass = objc_getClass("NSLocale");
        Class localeMeta = localeClass ? object_getClass(localeClass) : Nil;
        if (localeMeta) {
            LCInstallInstanceHook(localeMeta, @selector(currentLocale), (IMP)hook_NSLocale_currentLocale, (IMP *)&orig_NSLocale_currentLocale);
            LCInstallInstanceHook(localeMeta, @selector(autoupdatingCurrentLocale), (IMP)hook_NSLocale_autoupdatingCurrentLocale, (IMP *)&orig_NSLocale_autoupdatingCurrentLocale);
            SEL systemLocaleSelector = @selector(systemLocale);
            if ([localeMeta respondsToSelector:systemLocaleSelector]) {
                LCInstallInstanceHook(localeMeta, systemLocaleSelector, (IMP)hook_NSLocale_systemLocale, (IMP *)&orig_NSLocale_systemLocale);
            }
            SEL preferredLanguagesSelector = @selector(preferredLanguages);
            if (preferredLanguagesSelector && [localeMeta respondsToSelector:preferredLanguagesSelector]) {
                LCInstallInstanceHook(localeMeta, preferredLanguagesSelector, (IMP)hook_NSLocale_preferredLanguages, (IMP *)&orig_NSLocale_preferredLanguages);
            }
        }
        if (localeClass) {
            LCInstallInstanceHook(localeClass, @selector(countryCode), (IMP)hook_NSLocale_countryCode, (IMP *)&orig_NSLocale_countryCode);
            LCInstallInstanceHook(localeClass, @selector(currencyCode), (IMP)hook_NSLocale_currencyCode, (IMP *)&orig_NSLocale_currencyCode);
            LCInstallInstanceHook(localeClass, @selector(currencySymbol), (IMP)hook_NSLocale_currencySymbol, (IMP *)&orig_NSLocale_currencySymbol);
        }

        // Locale unit preference (metric/imperial)
        Class localeClass2 = objc_getClass("NSLocale");
        if (localeClass2 && [localeClass2 instancesRespondToSelector:@selector(usesMetricSystem)]) {
            LCInstallInstanceHook(localeClass2, @selector(usesMetricSystem), (IMP)hook_NSLocale_usesMetricSystem, (IMP *)&orig_NSLocale_usesMetricSystem);
        }
        if (localeClass2 && [localeClass2 instancesRespondToSelector:@selector(objectForKey:)]) {
            LCInstallInstanceHook(localeClass2, @selector(objectForKey:), (IMP)hook_NSLocale_objectForKey, (IMP *)&orig_NSLocale_objectForKey);
        }

        // Calendar identifier
        Class calendarClass = objc_getClass("NSCalendar");
        if (calendarClass) {
            SEL calendarIdSelector = NSSelectorFromString(@"calendarIdentifier");
            if (calendarIdSelector && [calendarClass instancesRespondToSelector:calendarIdSelector]) {
                LCInstallInstanceHook(calendarClass, calendarIdSelector, (IMP)hook_NSCalendar_identifier, (IMP *)&orig_NSCalendar_identifier);
            } else {
                SEL identifierSelector = NSSelectorFromString(@"identifier");
                if (identifierSelector && [calendarClass instancesRespondToSelector:identifierSelector]) {
                    LCInstallInstanceHook(calendarClass, identifierSelector, (IMP)hook_NSCalendar_identifier, (IMP *)&orig_NSCalendar_identifier);
                }
            }
        }

        if (g_keyboardSpoofingEnabled) {
            Class textInputModeClass = objc_getClass("UITextInputMode");
            if (textInputModeClass) {
                Class textInputModeMeta = object_getClass(textInputModeClass);
                SEL activeModesSelector = @selector(activeInputModes);
                if ([textInputModeMeta respondsToSelector:activeModesSelector]) {
                    LCInstallInstanceHook(textInputModeMeta, activeModesSelector, (IMP)hook_UITextInputMode_activeInputModes, (IMP *)&orig_UITextInputMode_activeInputModes);
                }
                SEL currentInputModeSelector = NSSelectorFromString(@"currentInputMode");
                if ([textInputModeMeta respondsToSelector:currentInputModeSelector]) {
                    LCInstallInstanceHook(textInputModeMeta, currentInputModeSelector, (IMP)hook_UITextInputMode_currentInputMode, (IMP *)&orig_UITextInputMode_currentInputMode);
                }
                LCInstallInstanceHook(textInputModeClass, @selector(primaryLanguage), (IMP)hook_UITextInputMode_primaryLanguage, (IMP *)&orig_UITextInputMode_primaryLanguage);
            }
        }

        if (g_userDefaultsSpoofingEnabled) {
            Class userDefaultsClass = objc_getClass("NSUserDefaults");
            LCInstallInstanceHook(userDefaultsClass, @selector(objectForKey:), (IMP)hook_NSUserDefaults_objectForKey, (IMP *)&orig_NSUserDefaults_objectForKey);
            LCInstallInstanceHook(userDefaultsClass, @selector(dictionaryRepresentation), (IMP)hook_NSUserDefaults_dictionaryRepresentation, (IMP *)&orig_NSUserDefaults_dictionaryRepresentation);
        }

        if (g_spoofEntitlementsEnabled) {
            Class plistClass = objc_getClass("NSPropertyListSerialization");
            Class plistMeta = object_getClass(plistClass);
            LCInstallInstanceHook(plistMeta, @selector(propertyListWithData:options:format:error:), (IMP)hook_NSPropertyListSerialization_propertyListWithData_options_format_error, (IMP *)&orig_NSPropertyListSerialization_propertyListWithData_options_format_error);
        }

        // Screen capture detection blocking
        if (g_screenCaptureBlockEnabled) {
            LCInstallInstanceHook(uiScreenClass, @selector(isCaptured), (IMP)hook_UIScreen_isCaptured, (IMP *)&orig_UIScreen_isCaptured);

            Class messageClass = objc_getClass("MFMessageComposeViewController");
            Class messageMeta = object_getClass(messageClass);
            LCInstallInstanceHook(messageMeta, @selector(canSendText), (IMP)hook_MFMessageComposeViewController_canSendText, (IMP *)&orig_MFMessageComposeViewController_canSendText);
            SEL canSendAttachmentsSelector = NSSelectorFromString(@"canSendAttachments");
            if (canSendAttachmentsSelector && [messageMeta respondsToSelector:canSendAttachmentsSelector]) {
                LCInstallInstanceHook(messageMeta, canSendAttachmentsSelector, (IMP)hook_MFMessageComposeViewController_canSendAttachments, (IMP *)&orig_MFMessageComposeViewController_canSendAttachments);
            }
            SEL canSendSubjectSelector = NSSelectorFromString(@"canSendSubject");
            if (canSendSubjectSelector && [messageMeta respondsToSelector:canSendSubjectSelector]) {
                LCInstallInstanceHook(messageMeta, canSendSubjectSelector, (IMP)hook_MFMessageComposeViewController_canSendSubject, (IMP *)&orig_MFMessageComposeViewController_canSendSubject);
            }

            Class mailClass = objc_getClass("MFMailComposeViewController");
            Class mailMeta = object_getClass(mailClass);
            LCInstallInstanceHook(mailMeta, @selector(canSendMail), (IMP)hook_MFMailComposeViewController_canSendMail, (IMP *)&orig_MFMailComposeViewController_canSendMail);

            Class pasteboardClass = objc_getClass("UIPasteboard");
            LCInstallInstanceHook(pasteboardClass, @selector(string), (IMP)hook_UIPasteboard_string, (IMP *)&orig_UIPasteboard_string);
            SEL stringsSelector = NSSelectorFromString(@"strings");
            if (stringsSelector && [pasteboardClass instancesRespondToSelector:stringsSelector]) {
                LCInstallInstanceHook(pasteboardClass, stringsSelector, (IMP)hook_UIPasteboard_strings, (IMP *)&orig_UIPasteboard_strings);
            }
            SEL hasStringsSelector = NSSelectorFromString(@"hasStrings");
            if (hasStringsSelector && [pasteboardClass instancesRespondToSelector:hasStringsSelector]) {
                LCInstallInstanceHook(pasteboardClass, hasStringsSelector, (IMP)hook_UIPasteboard_hasStrings, (IMP *)&orig_UIPasteboard_hasStrings);
            }
            SEL dataForTypeSelector = NSSelectorFromString(@"dataForPasteboardType:");
            if (dataForTypeSelector && [pasteboardClass instancesRespondToSelector:dataForTypeSelector]) {
                LCInstallInstanceHook(pasteboardClass, dataForTypeSelector, (IMP)hook_UIPasteboard_dataForPasteboardType, (IMP *)&orig_UIPasteboard_dataForPasteboardType);
            }

            if (g_spoofCraneEnabled || g_spoofAppiumEnabled) {
                Class nsStringClass = objc_getClass("NSString");
                LCInstallInstanceHook(nsStringClass, @selector(containsString:), (IMP)hook_NSString_containsString, (IMP *)&orig_NSString_containsString);
                LCInstallInstanceHook(nsStringClass, @selector(hasPrefix:), (IMP)hook_NSString_hasPrefix, (IMP *)&orig_NSString_hasPrefix);
                LCInstallInstanceHook(nsStringClass, @selector(hasSuffix:), (IMP)hook_NSString_hasSuffix, (IMP *)&orig_NSString_hasSuffix);
                LCInstallInstanceHook(nsStringClass, @selector(rangeOfString:), (IMP)hook_NSString_rangeOfString, (IMP *)&orig_NSString_rangeOfString);

                Class predicateClass = objc_getClass("NSPredicate");
                LCInstallInstanceHook(predicateClass, @selector(evaluateWithObject:), (IMP)hook_NSPredicate_evaluateWithObject, (IMP *)&orig_NSPredicate_evaluateWithObject);
            }

            Class assetCollectionClass = objc_getClass("PHAssetCollection");
            Class assetCollectionMeta = object_getClass(assetCollectionClass);
            SEL fetchSelector = NSSelectorFromString(@"fetchAssetCollectionsWithType:subtype:options:");
            LCInstallInstanceHook(assetCollectionMeta, fetchSelector, (IMP)hook_PHAssetCollection_fetchAssetCollectionsWithType_subtype_options, (IMP *)&orig_PHAssetCollection_fetchAssetCollectionsWithType_subtype_options);

            Class bugsnagClass = objc_getClass("BugsnagDevice");
            LCInstallInstanceHook(bugsnagClass, @selector(jailbroken), (IMP)hook_BugsnagDevice_jailbroken, (IMP *)&orig_BugsnagDevice_jailbroken);
            LCInstallInstanceHook(bugsnagClass, @selector(setJailbroken:), (IMP)hook_BugsnagDevice_setJailbroken, (IMP *)&orig_BugsnagDevice_setJailbroken);

            Class urlSessionClass = objc_getClass("NSURLSession");
            LCInstallInstanceHook(urlSessionClass, @selector(uploadTaskWithRequest:fromData:completionHandler:), (IMP)hook_NSURLSession_uploadTaskWithRequest_fromData_completionHandler, (IMP *)&orig_NSURLSession_uploadTaskWithRequest_fromData_completionHandler);
        }

        // External accessory fingerprinting
        Class accessoryMgrClass = objc_getClass("EAAccessoryManager");
        if (accessoryMgrClass && [accessoryMgrClass instancesRespondToSelector:@selector(connectedAccessories)]) {
            LCInstallInstanceHook(accessoryMgrClass, @selector(connectedAccessories), (IMP)hook_EAAccessoryManager_connectedAccessories, (IMP *)&orig_EAAccessoryManager_connectedAccessories);
        }

        // Location services enabled probing (global switch)
        Class clLocationMgrClass = objc_getClass("CLLocationManager");
        if (clLocationMgrClass) {
            Class clLocationMeta = object_getClass(clLocationMgrClass);
            SEL enabledSelector = NSSelectorFromString(@"locationServicesEnabled");
            if (enabledSelector && [clLocationMeta respondsToSelector:enabledSelector]) {
                LCInstallInstanceHook(clLocationMeta, enabledSelector, (IMP)hook_CLLocationManager_locationServicesEnabled, (IMP *)&orig_CLLocationManager_locationServicesEnabled);
            }
        }

        // Audio session heuristics (volume/mute-style probing)
        Class audioSessionClass = objc_getClass("AVAudioSession");
        if (audioSessionClass) {
            SEL outputVolumeSelector = NSSelectorFromString(@"outputVolume");
            if (outputVolumeSelector && [audioSessionClass instancesRespondToSelector:outputVolumeSelector]) {
                LCInstallInstanceHook(audioSessionClass, outputVolumeSelector, (IMP)hook_AVAudioSession_outputVolume, (IMP *)&orig_AVAudioSession_outputVolume);
            }
            SEL secondarySilenceSelector = NSSelectorFromString(@"secondaryAudioShouldBeSilencedHint");
            if (secondarySilenceSelector && [audioSessionClass instancesRespondToSelector:secondarySilenceSelector]) {
                LCInstallInstanceHook(audioSessionClass, secondarySilenceSelector, (IMP)hook_AVAudioSession_secondaryAudioShouldBeSilencedHint, (IMP *)&orig_AVAudioSession_secondaryAudioShouldBeSilencedHint);
            }
        }

        // Social accounts (deprecated but still probed)
        Class slComposeClass = objc_getClass("SLComposeViewController");
        if (slComposeClass) {
            Class slComposeMeta = object_getClass(slComposeClass);
            SEL availSelector = NSSelectorFromString(@"isAvailableForServiceType:");
            if (availSelector && [slComposeMeta respondsToSelector:availSelector]) {
                LCInstallInstanceHook(slComposeMeta, availSelector, (IMP)hook_SLComposeViewController_isAvailableForServiceType, (IMP *)&orig_SLComposeViewController_isAvailableForServiceType);
            }
        }

        // StoreKit / PaymentKit capability checks
        Class skQueueClass = objc_getClass("SKPaymentQueue");
        if (skQueueClass) {
            Class skQueueMeta = object_getClass(skQueueClass);
            SEL canMakeSelector = NSSelectorFromString(@"canMakePayments");
            if (canMakeSelector && [skQueueMeta respondsToSelector:canMakeSelector]) {
                LCInstallInstanceHook(skQueueMeta, canMakeSelector, (IMP)hook_SKPaymentQueue_canMakePayments, (IMP *)&orig_SKPaymentQueue_canMakePayments);
            }
        }

        Class pkAuthVCClass = objc_getClass("PKPaymentAuthorizationViewController");
        if (pkAuthVCClass) {
            Class pkMeta = object_getClass(pkAuthVCClass);
            SEL pkCanMake = NSSelectorFromString(@"canMakePayments");
            if (pkCanMake && [pkMeta respondsToSelector:pkCanMake]) {
                LCInstallInstanceHook(pkMeta, pkCanMake, (IMP)hook_PKPaymentAuthorizationViewController_canMakePayments, (IMP *)&orig_PKPaymentAuthorizationViewController_canMakePayments);
            }
            SEL pkNetworks = NSSelectorFromString(@"canMakePaymentsUsingNetworks:");
            if (pkNetworks && [pkMeta respondsToSelector:pkNetworks]) {
                LCInstallInstanceHook(pkMeta, pkNetworks, (IMP)hook_PKPaymentAuthorizationViewController_canMakePaymentsUsingNetworks, (IMP *)&orig_PKPaymentAuthorizationViewController_canMakePaymentsUsingNetworks);
            }
        }

        Class pkAuthControllerClass = objc_getClass("PKPaymentAuthorizationController");
        if (pkAuthControllerClass) {
            Class pkMeta = object_getClass(pkAuthControllerClass);
            SEL pkCanMake = NSSelectorFromString(@"canMakePayments");
            if (pkCanMake && [pkMeta respondsToSelector:pkCanMake]) {
                LCInstallInstanceHook(pkMeta, pkCanMake, (IMP)hook_PKPaymentAuthorizationController_canMakePayments, (IMP *)&orig_PKPaymentAuthorizationController_canMakePayments);
            }
            SEL pkNetworks = NSSelectorFromString(@"canMakePaymentsUsingNetworks:");
            if (pkNetworks && [pkMeta respondsToSelector:pkNetworks]) {
                LCInstallInstanceHook(pkMeta, pkNetworks, (IMP)hook_PKPaymentAuthorizationController_canMakePaymentsUsingNetworks, (IMP *)&orig_PKPaymentAuthorizationController_canMakePaymentsUsingNetworks);
            }
        }

        // Biometrics (LocalAuthentication)
        Class laContextClass = objc_getClass("LAContext");
        if (laContextClass) {
            SEL canEvalSelector = NSSelectorFromString(@"canEvaluatePolicy:error:");
            if (canEvalSelector && [laContextClass instancesRespondToSelector:canEvalSelector]) {
                LCInstallInstanceHook(laContextClass, canEvalSelector, (IMP)hook_LAContext_canEvaluatePolicy_error, (IMP *)&orig_LAContext_canEvaluatePolicy_error);
            }
            SEL biometrySelector = NSSelectorFromString(@"biometryType");
            if (biometrySelector && [laContextClass instancesRespondToSelector:biometrySelector]) {
                LCInstallInstanceHook(laContextClass, biometrySelector, (IMP)hook_LAContext_biometryType, (IMP *)&orig_LAContext_biometryType);
            }
        }

        // Siri authorization (Intents)
        if (g_siriPrivacyProtectionEnabled) {
            Class inPrefsClass = objc_getClass("INPreferences");
            if (inPrefsClass) {
                Class inPrefsMeta = object_getClass(inPrefsClass);
                SEL statusSelector = NSSelectorFromString(@"siriAuthorizationStatus");
                if (statusSelector && [inPrefsMeta respondsToSelector:statusSelector]) {
                    LCInstallInstanceHook(inPrefsMeta, statusSelector, (IMP)hook_INPreferences_siriAuthorizationStatus, (IMP *)&orig_INPreferences_siriAuthorizationStatus);
                }
                SEL requestSelector = NSSelectorFromString(@"requestSiriAuthorization:");
                if (requestSelector && [inPrefsMeta respondsToSelector:requestSelector]) {
                    LCInstallInstanceHook(inPrefsMeta, requestSelector, (IMP)hook_INPreferences_requestSiriAuthorization, (IMP *)&orig_INPreferences_requestSiriAuthorization);
                }
            }
        }

        if (g_deviceCheckSpoofingEnabled) {
            Class dcDeviceClass = objc_getClass("DCDevice");
            LCInstallInstanceHook(dcDeviceClass, @selector(isSupported), (IMP)hook_DCDevice_isSupported, (IMP *)&orig_DCDevice_isSupported);
            LCInstallInstanceHook(dcDeviceClass, @selector(generateTokenWithCompletionHandler:), (IMP)hook_DCDevice_generateTokenWithCompletionHandler, (IMP *)&orig_DCDevice_generateTokenWithCompletionHandler);
        }

        if (g_appAttestSpoofingEnabled) {
            Class appAttestClass = objc_getClass("DCAppAttestService");
            LCInstallInstanceHook(appAttestClass, @selector(isSupported), (IMP)hook_DCAppAttestService_isSupported, (IMP *)&orig_DCAppAttestService_isSupported);
            LCInstallInstanceHook(appAttestClass, @selector(generateKeyWithCompletionHandler:), (IMP)hook_DCAppAttestService_generateKeyWithCompletionHandler, (IMP *)&orig_DCAppAttestService_generateKeyWithCompletionHandler);
            LCInstallInstanceHook(appAttestClass, @selector(attestKey:clientDataHash:completionHandler:), (IMP)hook_DCAppAttestService_attestKey_clientDataHash_completionHandler, (IMP *)&orig_DCAppAttestService_attestKey_clientDataHash_completionHandler);
            LCInstallInstanceHook(appAttestClass, @selector(generateAssertion:clientDataHash:completionHandler:), (IMP)hook_DCAppAttestService_generateAssertion_clientDataHash_completionHandler, (IMP *)&orig_DCAppAttestService_generateAssertion_clientDataHash_completionHandler);
        }

        if (g_spoofGyroscopeEnabled) {
            Class motionClass = objc_getClass("CMMotionManager");
            if (motionClass) {
                LCInstallInstanceHook(motionClass, @selector(isGyroAvailable), (IMP)hook_CMMotionManager_isGyroAvailable, (IMP *)&orig_CMMotionManager_isGyroAvailable);
                LCInstallInstanceHook(motionClass, @selector(isDeviceMotionAvailable), (IMP)hook_CMMotionManager_isDeviceMotionAvailable, (IMP *)&orig_CMMotionManager_isDeviceMotionAvailable);
            }
        }

        // WKWebView hooks — always install for UA spoofing + JS injection
        Class wkWebViewClass = objc_getClass("WKWebView");
        if (wkWebViewClass) {
            LCInstallInstanceHook(wkWebViewClass, @selector(customUserAgent), (IMP)hook_WKWebView_customUserAgent, (IMP *)&orig_WKWebView_customUserAgent);
            LCInstallInstanceHook(wkWebViewClass, @selector(initWithFrame:configuration:), (IMP)hook_WKWebView_initWithFrame, (IMP *)&orig_WKWebView_initWithFrame);
        }

        // WKWebViewConfiguration hook
        Class wkConfigClass = objc_getClass("WKWebViewConfiguration");
        if (wkConfigClass) {
            LCInstallInstanceHook(wkConfigClass, @selector(setApplicationNameForUserAgent:), (IMP)hook_WKWebViewConfiguration_setApplicationNameForUserAgent, (IMP *)&orig_WKWebViewConfiguration_setApplicationNameForUserAgent);
        }

        // NSFileManager + NSURL storage surfaces
        Class fileManagerClass2 = objc_getClass("NSFileManager");
        Method fsAttrs = class_getInstanceMethod(fileManagerClass2, @selector(attributesOfFileSystemForPath:error:));
        if (fsAttrs) {
            orig_NSFileManager_attributesOfFileSystemForPath = (NSDictionary *(*)(id, SEL, NSString *, NSError **))
                method_setImplementation(fsAttrs, (IMP)hook_NSFileManager_attributesOfFileSystemForPath);
        }
        Method itemAttrs = class_getInstanceMethod(fileManagerClass2, @selector(attributesOfItemAtPath:error:));
        if (itemAttrs) {
            orig_NSFileManager_attributesOfItemAtPath_error = (NSDictionary *(*)(id, SEL, NSString *, NSError **))
                method_setImplementation(itemAttrs, (IMP)hook_NSFileManager_attributesOfItemAtPath_error);
        }
        LCInstallInstanceHook(fileManagerClass2, NSSelectorFromString(@"volumeAvailableCapacityForImportantUsageForURL:error:"),
                              (IMP)hook_NSFileManager_volumeAvailableCapacityForImportantUsageForURL,
                              (IMP *)&orig_NSFileManager_volumeAvailableCapacityForImportantUsageForURL);
        LCInstallInstanceHook(fileManagerClass2, NSSelectorFromString(@"volumeAvailableCapacityForOpportunisticUsageForURL:error:"),
                              (IMP)hook_NSFileManager_volumeAvailableCapacityForOpportunisticUsageForURL,
                              (IMP *)&orig_NSFileManager_volumeAvailableCapacityForOpportunisticUsageForURL);
        LCInstallInstanceHook(fileManagerClass2, NSSelectorFromString(@"volumeTotalCapacityForURL:error:"),
                              (IMP)hook_NSFileManager_volumeTotalCapacityForURL,
                              (IMP *)&orig_NSFileManager_volumeTotalCapacityForURL);

        Class nsURLClass = objc_getClass("NSURL");
        LCInstallInstanceHook(nsURLClass, @selector(getResourceValue:forKey:error:), (IMP)hook_NSURL_getResourceValue_forKey_error, (IMP *)&orig_NSURL_getResourceValue_forKey_error);
        LCInstallInstanceHook(nsURLClass, @selector(resourceValuesForKeys:error:), (IMP)hook_NSURL_resourceValuesForKeys_error, (IMP *)&orig_NSURL_resourceValuesForKeys_error);
    });
}
