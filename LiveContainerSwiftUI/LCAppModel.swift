import Foundation
import CoreLocation

protocol LCAppModelDelegate {
    func closeNavigationView()
    func changeAppVisibility(app : LCAppModel)
    func jitLaunch() async
    func jitLaunch(withScript script: String) async
    func jitLaunch(withPID pid: Int, withScript script: String?) async
    func showRunWhenMultitaskAlert() async -> Bool?
}

class LCAppModel: ObservableObject, Hashable {
    
    @Published var appInfo : LCAppInfo
    
    @Published var isAppRunning = false
    @Published var isSigningInProgress = false
    @Published var signProgress = 0.0
    private var observer : NSKeyValueObservation?
    
    @Published var uiIsJITNeeded : Bool {
        didSet {
            appInfo.isJITNeeded = uiIsJITNeeded
        }
    }
    @Published var uiIsHidden : Bool
    @Published var uiIsLocked : Bool
    @Published var uiIsShared : Bool
    @Published var uiDefaultDataFolder : String?
    @Published var uiContainers : [LCContainer]
    @Published var uiSelectedContainer : LCContainer?
    @Published var uiAddonSettingsContainerFolderName : String
#if is32BitSupported
    @Published var uiIs32bit : Bool
#endif
    @Published var uiTweakFolder : String? {
        didSet {
            appInfo.tweakFolder = uiTweakFolder
        }
    }
    @Published var uiDoSymlinkInbox : Bool {
        didSet {
            appInfo.doSymlinkInbox = uiDoSymlinkInbox
        }
    }
    @Published var uiUseLCBundleId : Bool {
        didSet {
            appInfo.doUseLCBundleId = uiUseLCBundleId
        }
    }
    
    @Published var uiFixFilePickerNew : Bool {
        didSet {
            appInfo.fixFilePickerNew = uiFixFilePickerNew
        }
    }
    @Published var uiFixLocalNotification : Bool {
        didSet {
            appInfo.fixLocalNotification = uiFixLocalNotification
        }
    }
    
    @Published var uiHideLiveContainer : Bool {
        didSet {
            appInfo.hideLiveContainer = uiHideLiveContainer
        }
    }
    @Published var uiTweakLoaderInjectFailed : Bool
    @Published var uiDontInjectTweakLoader : Bool {
        didSet {
            appInfo.dontInjectTweakLoader = uiDontInjectTweakLoader
        }
    }
    @Published var uiDontLoadTweakLoader : Bool {
        didSet {
            appInfo.dontLoadTweakLoader = uiDontLoadTweakLoader
        }
    }
    @Published var uiOrientationLock : LCOrientationLock {
        didSet {
            appInfo.orientationLock = uiOrientationLock
        }
    }
    @Published var uiSelectedLanguage : String {
        didSet {
            appInfo.selectedLanguage = uiSelectedLanguage
        }
    }
    
    @Published var uiDontSign : Bool {
        didSet {
            appInfo.dontSign = uiDontSign
        }
    }
    
    @Published var jitLaunchScriptJs: String? {
        didSet {
            appInfo.jitLaunchScriptJs = jitLaunchScriptJs
        }
    }

    @Published var uiSpoofSDKVersion : Bool {
        didSet {
            appInfo.spoofSDKVersion = uiSpoofSDKVersion
        }
    }
    
    @Published var uiRemark : String {
        didSet {
            appInfo.remark = uiRemark
        }
    }
    
    @Published var supportedLanguages : [String]?

    // MARK: GPS Addon Section
    @Published var uiSpoofGPS : Bool {
        didSet {
            appInfo.spoofGPS = uiSpoofGPS
        }
    }
    @Published var uiSpoofLatitude : CLLocationDegrees {
        didSet {
            appInfo.spoofLatitude = uiSpoofLatitude
        }
    }
    @Published var uiSpoofLongitude : CLLocationDegrees {
        didSet {
            appInfo.spoofLongitude = uiSpoofLongitude
        }
    }
    @Published var uiSpoofAltitude : CLLocationDistance {
        didSet {
            appInfo.spoofAltitude = uiSpoofAltitude
        }
    }
    @Published var uiSpoofLocationName : String {
        didSet {
            appInfo.spoofLocationName = uiSpoofLocationName
        }
    }
    
    // MARK: Camera Addon Section
    @Published var uiSpoofCamera : Bool {
        didSet {
            appInfo.spoofCamera = uiSpoofCamera
        }
    }
    @Published var uiSpoofCameraType : String {
        didSet {
            appInfo.spoofCameraType = uiSpoofCameraType
        }
    }
    @Published var uiSpoofCameraImagePath : String {
        didSet {
            appInfo.spoofCameraImagePath = uiSpoofCameraImagePath
        }
    }
    @Published var uiSpoofCameraVideoPath : String {
        didSet {
            appInfo.spoofCameraVideoPath = uiSpoofCameraVideoPath
        }
    }
    @Published var uiSpoofCameraLoop : Bool {
        didSet {
            appInfo.spoofCameraLoop = uiSpoofCameraLoop
        }
    }
    @Published var uiSpoofCameraUseVideoAudio : Bool {
        didSet {
            appInfo.spoofCameraUseVideoAudio = uiSpoofCameraUseVideoAudio
        }
    }
    
    @Published var uiSpoofCameraMode : String {
        didSet {
            appInfo.spoofCameraMode = uiSpoofCameraMode
        }
    }

    // MARK: Camera Transform Options
    @Published var uiSpoofCameraTransformOrientation: String {
        didSet {
            appInfo.spoofCameraTransformOrientation = uiSpoofCameraTransformOrientation
        }
    }
    @Published var uiSpoofCameraTransformScale: String {
        didSet {
            appInfo.spoofCameraTransformScale = uiSpoofCameraTransformScale
        }
    }
    @Published var uiSpoofCameraTransformFlip: String {
        didSet {
            appInfo.spoofCameraTransformFlip = uiSpoofCameraTransformFlip
        }
    }

    @Published var isProcessingVideo = false
    @Published var videoProcessingProgress: Double = 0.0

    // MARK: SSL Addon
    @Published var uiBypassSSLPinning: Bool {
        didSet {
            appInfo.bypassSSLPinning = uiBypassSSLPinning
        }
    }

    // MARK: Device Spoofing Addon (Ghost-style)
    @Published var uiDeviceSpoofingEnabled: Bool {
        didSet {
            appInfo.deviceSpoofingEnabled = uiDeviceSpoofingEnabled
        }
    }
    @Published var uiDeviceSpoofProfile: String {
        didSet {
            appInfo.deviceSpoofProfile = uiDeviceSpoofProfile
        }
    }
    @Published var uiDeviceSpoofCustomVersion: String {
        didSet {
            appInfo.deviceSpoofCustomVersion = uiDeviceSpoofCustomVersion
        }
    }
    @Published var uiDeviceSpoofDeviceName: Bool {
        didSet {
            appInfo.deviceSpoofDeviceName = uiDeviceSpoofDeviceName
        }
    }
    @Published var uiDeviceSpoofDeviceNameValue: String {
        didSet {
            appInfo.deviceSpoofDeviceNameValue = uiDeviceSpoofDeviceNameValue
        }
    }
    @Published var uiDeviceSpoofCarrier: Bool {
        didSet {
            appInfo.deviceSpoofCarrier = uiDeviceSpoofCarrier
        }
    }
    @Published var uiDeviceSpoofCarrierName: String {
        didSet {
            appInfo.deviceSpoofCarrierName = uiDeviceSpoofCarrierName
        }
    }
    @Published var uiDeviceSpoofMCC: String {
        didSet {
            appInfo.deviceSpoofMCC = uiDeviceSpoofMCC
        }
    }
    @Published var uiDeviceSpoofMNC: String {
        didSet {
            appInfo.deviceSpoofMNC = uiDeviceSpoofMNC
        }
    }
    @Published var uiDeviceSpoofCarrierCountry: String {
        didSet {
            appInfo.deviceSpoofCarrierCountry = uiDeviceSpoofCarrierCountry
        }
    }
    @Published var uiDeviceSpoofIdentifiers: Bool {
        didSet {
            appInfo.deviceSpoofIdentifiers = uiDeviceSpoofIdentifiers
            if !isApplyingAddonContainerSettings {
                syncCurrentContainerIDFVWithDeviceSpoofing()
            }
        }
    }
    @Published var uiDeviceSpoofVendorID: String {
        didSet {
            appInfo.deviceSpoofVendorID = uiDeviceSpoofVendorID
            if !isApplyingAddonContainerSettings {
                syncCurrentContainerIDFVWithDeviceSpoofing()
            }
        }
    }
    @Published var uiDeviceSpoofAdvertisingID: String {
        didSet {
            appInfo.deviceSpoofAdvertisingID = uiDeviceSpoofAdvertisingID
        }
    }
    @Published var uiDeviceSpoofAdTrackingMode: String {
        didSet {
            appInfo.deviceSpoofAdTrackingMode = uiDeviceSpoofAdTrackingMode
        }
    }
    @Published var uiDeviceSpoofPersistentDeviceID: String {
        didSet {
            appInfo.deviceSpoofPersistentDeviceID = uiDeviceSpoofPersistentDeviceID
        }
    }
    @Published var uiDeviceSpoofInstallationID: String {
        didSet {
            appInfo.deviceSpoofInstallationID = uiDeviceSpoofInstallationID
        }
    }
    @Published var uiDeviceSpoofSecurityEnabled: Bool {
        didSet {
            appInfo.deviceSpoofSecurityEnabled = uiDeviceSpoofSecurityEnabled
            if isApplyingAddonContainerSettings {
                return
            }
            uiDeviceSpoofCloudToken = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofDeviceChecker = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofAppAttest = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofScreenCapture = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofMessage = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofMail = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofBugsnag = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofCrane = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofPasteboard = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofAlbum = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofAppium = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofKeyboard = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofUserDefaults = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofEntitlements = uiDeviceSpoofSecurityEnabled
            uiDeviceSpoofFileTimestamps = uiDeviceSpoofSecurityEnabled
            if !uiDeviceSpoofSecurityEnabled {
                // Keep Siri privacy protection opt-in, but always disable it when the master toggle is off.
                uiDeviceSpoofSiriPrivacyProtection = false
            }
        }
    }
    @Published var uiDeviceSpoofCloudToken: Bool {
        didSet {
            appInfo.deviceSpoofCloudToken = uiDeviceSpoofCloudToken
        }
    }
    @Published var uiDeviceSpoofDeviceChecker: Bool {
        didSet {
            appInfo.deviceSpoofDeviceChecker = uiDeviceSpoofDeviceChecker
        }
    }
    @Published var uiDeviceSpoofAppAttest: Bool {
        didSet {
            appInfo.deviceSpoofAppAttest = uiDeviceSpoofAppAttest
        }
    }
    @Published var uiDeviceSpoofSiriPrivacyProtection: Bool {
        didSet {
            appInfo.deviceSpoofSiriPrivacyProtection = uiDeviceSpoofSiriPrivacyProtection
        }
    }
    @Published var uiDeviceSpoofTimezone: Bool {
        didSet {
            appInfo.deviceSpoofTimezone = uiDeviceSpoofTimezone
        }
    }
    @Published var uiDeviceSpoofTimezoneValue: String {
        didSet {
            appInfo.deviceSpoofTimezoneValue = uiDeviceSpoofTimezoneValue
        }
    }
    @Published var uiDeviceSpoofLocale: Bool {
        didSet {
            appInfo.deviceSpoofLocale = uiDeviceSpoofLocale
        }
    }
    @Published var uiDeviceSpoofLocaleValue: String {
        didSet {
            appInfo.deviceSpoofLocaleValue = uiDeviceSpoofLocaleValue
        }
    }
    @Published var uiDeviceSpoofLocaleCurrencyCode: String {
        didSet {
            appInfo.deviceSpoofLocaleCurrencyCode = uiDeviceSpoofLocaleCurrencyCode
        }
    }
    @Published var uiDeviceSpoofLocaleCurrencySymbol: String {
        didSet {
            appInfo.deviceSpoofLocaleCurrencySymbol = uiDeviceSpoofLocaleCurrencySymbol
        }
    }
    @Published var uiDeviceSpoofPreferredCountry: String {
        didSet {
            appInfo.deviceSpoofPreferredCountry = uiDeviceSpoofPreferredCountry
        }
    }
    @Published var uiDeviceSpoofCellularTypeEnabled: Bool {
        didSet {
            appInfo.deviceSpoofCellularTypeEnabled = uiDeviceSpoofCellularTypeEnabled
        }
    }
    @Published var uiDeviceSpoofCellularType: Int {
        didSet {
            appInfo.deviceSpoofCellularType = Int32(uiDeviceSpoofCellularType)
        }
    }
    @Published var uiDeviceSpoofNetworkInfo: Bool {
        didSet {
            appInfo.deviceSpoofNetworkInfo = uiDeviceSpoofNetworkInfo
        }
    }
    @Published var uiDeviceSpoofWiFiAddressEnabled: Bool {
        didSet {
            appInfo.deviceSpoofWiFiAddressEnabled = uiDeviceSpoofWiFiAddressEnabled
        }
    }
    @Published var uiDeviceSpoofCellularAddressEnabled: Bool {
        didSet {
            appInfo.deviceSpoofCellularAddressEnabled = uiDeviceSpoofCellularAddressEnabled
        }
    }
    @Published var uiDeviceSpoofMACAddressEnabled: Bool {
        didSet {
            appInfo.deviceSpoofMACAddressEnabled = uiDeviceSpoofMACAddressEnabled
        }
    }
    @Published var uiDeviceSpoofWiFiAddress: String {
        didSet {
            appInfo.deviceSpoofWiFiAddress = uiDeviceSpoofWiFiAddress
        }
    }
    @Published var uiDeviceSpoofCellularAddress: String {
        didSet {
            appInfo.deviceSpoofCellularAddress = uiDeviceSpoofCellularAddress
        }
    }
    @Published var uiDeviceSpoofWiFiSSID: String {
        didSet {
            appInfo.deviceSpoofWiFiSSID = uiDeviceSpoofWiFiSSID
        }
    }
    @Published var uiDeviceSpoofWiFiBSSID: String {
        didSet {
            appInfo.deviceSpoofWiFiBSSID = uiDeviceSpoofWiFiBSSID
        }
    }
    @Published var uiDeviceSpoofMACAddress: String {
        didSet {
            appInfo.deviceSpoofMACAddress = uiDeviceSpoofMACAddress
        }
    }
    @Published var uiDeviceSpoofCanvasFingerprintProtection: Bool {
        didSet {
            appInfo.deviceSpoofCanvasFingerprintProtection = uiDeviceSpoofCanvasFingerprintProtection
        }
    }
    @Published var uiDeviceSpoofScreenCapture: Bool {
        didSet {
            appInfo.deviceSpoofScreenCapture = uiDeviceSpoofScreenCapture
        }
    }
    @Published var uiDeviceSpoofMessage: Bool {
        didSet {
            appInfo.enableSpoofMessage = uiDeviceSpoofMessage
        }
    }
    @Published var uiDeviceSpoofMail: Bool {
        didSet {
            appInfo.enableSpoofMail = uiDeviceSpoofMail
        }
    }
    @Published var uiDeviceSpoofBugsnag: Bool {
        didSet {
            appInfo.enableSpoofBugsnag = uiDeviceSpoofBugsnag
        }
    }
    @Published var uiDeviceSpoofCrane: Bool {
        didSet {
            appInfo.enableSpoofCrane = uiDeviceSpoofCrane
        }
    }
    @Published var uiDeviceSpoofPasteboard: Bool {
        didSet {
            appInfo.enableSpoofPasteboard = uiDeviceSpoofPasteboard
        }
    }
    @Published var uiDeviceSpoofAlbum: Bool {
        didSet {
            appInfo.enableSpoofAlbum = uiDeviceSpoofAlbum
        }
    }
    @Published var uiDeviceSpoofAppium: Bool {
        didSet {
            appInfo.enableSpoofAppium = uiDeviceSpoofAppium
        }
    }
    @Published var uiDeviceSpoofKeyboard: Bool {
        didSet {
            appInfo.enableSpoofKeyboard = uiDeviceSpoofKeyboard
        }
    }
    @Published var uiDeviceSpoofUserDefaults: Bool {
        didSet {
            appInfo.enableSpoofUserDefaults = uiDeviceSpoofUserDefaults
        }
    }
    @Published var uiDeviceSpoofEntitlements: Bool {
        didSet {
            appInfo.enableSpoofEntitlements = uiDeviceSpoofEntitlements
        }
    }
    @Published var uiDeviceSpoofFileTimestamps: Bool {
        didSet {
            appInfo.deviceSpoofFileTimestamps = uiDeviceSpoofFileTimestamps
        }
    }
    @Published var uiDeviceSpoofProximity: Bool {
        didSet {
            appInfo.deviceSpoofProximity = uiDeviceSpoofProximity
        }
    }
    @Published var uiDeviceSpoofOrientation: Bool {
        didSet {
            appInfo.deviceSpoofOrientation = uiDeviceSpoofOrientation
        }
    }
    @Published var uiDeviceSpoofGyroscope: Bool {
        didSet {
            appInfo.deviceSpoofGyroscope = uiDeviceSpoofGyroscope
        }
    }
    @Published var uiDeviceSpoofProcessorEnabled: Bool {
        didSet {
            appInfo.deviceSpoofProcessorEnabled = uiDeviceSpoofProcessorEnabled
        }
    }
    @Published var uiDeviceSpoofProcessorCount: Int {
        didSet {
            appInfo.deviceSpoofProcessorCount = Int32(uiDeviceSpoofProcessorCount)
        }
    }
    @Published var uiDeviceSpoofMemoryEnabled: Bool {
        didSet {
            appInfo.deviceSpoofMemoryEnabled = uiDeviceSpoofMemoryEnabled
        }
    }
    @Published var uiDeviceSpoofMemoryCount: String {
        didSet {
            appInfo.deviceSpoofMemoryCount = uiDeviceSpoofMemoryCount
        }
    }
    @Published var uiDeviceSpoofKernelVersionEnabled: Bool {
        didSet {
            appInfo.deviceSpoofKernelVersionEnabled = uiDeviceSpoofKernelVersionEnabled
        }
    }
    @Published var uiDeviceSpoofKernelVersion: String {
        didSet {
            appInfo.deviceSpoofKernelVersion = uiDeviceSpoofKernelVersion
        }
    }
    @Published var uiDeviceSpoofKernelRelease: String {
        didSet {
            appInfo.deviceSpoofKernelRelease = uiDeviceSpoofKernelRelease
        }
    }
    @Published var uiDeviceSpoofBuildVersion: String {
        didSet {
            appInfo.deviceSpoofBuildVersion = uiDeviceSpoofBuildVersion
        }
    }
    @Published var uiDeviceSpoofAlbumBlacklist: [String] {
        didSet {
            appInfo.deviceSpoofAlbumBlacklist = uiDeviceSpoofAlbumBlacklist
        }
    }

    // MARK: Extended Spoofing (Ghost + Project-X parity)
    @Published var uiDeviceSpoofBootTime: Bool {
        didSet {
            appInfo.deviceSpoofBootTime = uiDeviceSpoofBootTime
        }
    }
    @Published var uiDeviceSpoofBootTimeRange: String {
        didSet {
            appInfo.deviceSpoofBootTimeRange = uiDeviceSpoofBootTimeRange
        }
    }
    @Published var uiDeviceSpoofBootTimeRandomize: Bool {
        didSet {
            appInfo.deviceSpoofBootTimeRandomize = uiDeviceSpoofBootTimeRandomize
        }
    }
    @Published var uiDeviceSpoofUserAgent: Bool {
        didSet {
            appInfo.deviceSpoofUserAgent = uiDeviceSpoofUserAgent
        }
    }
    @Published var uiDeviceSpoofUserAgentValue: String {
        didSet {
            appInfo.deviceSpoofUserAgentValue = uiDeviceSpoofUserAgentValue
        }
    }
    @Published var uiDeviceSpoofBattery: Bool {
        didSet {
            appInfo.deviceSpoofBattery = uiDeviceSpoofBattery
        }
    }
    @Published var uiDeviceSpoofBatteryRandomize: Bool {
        didSet {
            appInfo.deviceSpoofBatteryRandomize = uiDeviceSpoofBatteryRandomize
        }
    }
    @Published var uiDeviceSpoofBatteryLevel: Float {
        didSet {
            appInfo.deviceSpoofBatteryLevel = uiDeviceSpoofBatteryLevel
        }
    }
    @Published var uiDeviceSpoofBatteryState: Int {
        didSet {
            appInfo.deviceSpoofBatteryState = Int32(uiDeviceSpoofBatteryState)
        }
    }
    @Published var uiDeviceSpoofStorage: Bool {
        didSet {
            appInfo.deviceSpoofStorage = uiDeviceSpoofStorage
        }
    }
    @Published var uiDeviceSpoofStorageCapacity: String {
        didSet {
            appInfo.deviceSpoofStorageCapacity = uiDeviceSpoofStorageCapacity
        }
    }
    @Published var uiDeviceSpoofStorageRandomFree: Bool {
        didSet {
            appInfo.deviceSpoofStorageRandomFree = uiDeviceSpoofStorageRandomFree
        }
    }
    @Published var uiDeviceSpoofStorageFreeGB: String {
        didSet {
            appInfo.deviceSpoofStorageFreeGB = uiDeviceSpoofStorageFreeGB
        }
    }
    @Published var uiDeviceSpoofBrightness: Bool {
        didSet {
            appInfo.deviceSpoofBrightness = uiDeviceSpoofBrightness
        }
    }
    @Published var uiDeviceSpoofBrightnessRandomize: Bool {
        didSet {
            appInfo.deviceSpoofBrightnessRandomize = uiDeviceSpoofBrightnessRandomize
        }
    }
    @Published var uiDeviceSpoofBrightnessValue: Float {
        didSet {
            appInfo.deviceSpoofBrightnessValue = uiDeviceSpoofBrightnessValue
        }
    }
    @Published var uiDeviceSpoofThermal: Bool {
        didSet {
            appInfo.deviceSpoofThermal = uiDeviceSpoofThermal
        }
    }
    @Published var uiDeviceSpoofThermalState: Int {
        didSet {
            appInfo.deviceSpoofThermalState = Int32(uiDeviceSpoofThermalState)
        }
    }
    @Published var uiDeviceSpoofLowPowerMode: Bool {
        didSet {
            appInfo.deviceSpoofLowPowerMode = uiDeviceSpoofLowPowerMode
        }
    }
    @Published var uiDeviceSpoofLowPowerModeValue: Bool {
        didSet {
            appInfo.deviceSpoofLowPowerModeValue = uiDeviceSpoofLowPowerModeValue
        }
    }

    var delegate : LCAppModelDelegate?
    private var isApplyingAddonContainerSettings = false
    
    init(appInfo : LCAppInfo, delegate: LCAppModelDelegate? = nil) {
        self.appInfo = appInfo
        self.delegate = delegate

        if !appInfo.isLocked && appInfo.isHidden {
            appInfo.isLocked = true
        }
        
        self.uiIsJITNeeded = appInfo.isJITNeeded
        self.uiIsHidden = appInfo.isHidden
        self.uiIsLocked = appInfo.isLocked
        self.uiIsShared = appInfo.isShared
        self.uiSelectedLanguage = appInfo.selectedLanguage ?? ""
        self.uiDefaultDataFolder = appInfo.dataUUID
        self.uiContainers = appInfo.containers
        self.uiAddonSettingsContainerFolderName = appInfo.dataUUID ?? appInfo.containers.first?.folderName ?? ""
        self.uiTweakFolder = appInfo.tweakFolder
        self.uiDoSymlinkInbox = appInfo.doSymlinkInbox
        self.uiOrientationLock = appInfo.orientationLock
        self.uiUseLCBundleId = appInfo.doUseLCBundleId
        self.uiFixFilePickerNew = appInfo.fixFilePickerNew
        self.uiFixLocalNotification = appInfo.fixLocalNotification
        self.uiHideLiveContainer = appInfo.hideLiveContainer
        self.uiDontInjectTweakLoader = appInfo.dontInjectTweakLoader
        self.uiTweakLoaderInjectFailed = appInfo.info()["LCTweakLoaderCantInject"] as? Bool ?? false
        self.uiDontLoadTweakLoader = appInfo.dontLoadTweakLoader
        self.uiDontSign = appInfo.dontSign
        self.jitLaunchScriptJs = appInfo.jitLaunchScriptJs
        self.uiSpoofSDKVersion = appInfo.spoofSDKVersion
        self.uiRemark = appInfo.remark ?? ""
#if is32BitSupported
        self.uiIs32bit = appInfo.is32bit
#endif
        
        // MARK: GPS Addon Section
        self.uiSpoofGPS = appInfo.spoofGPS
        self.uiSpoofLatitude = appInfo.spoofLatitude
        self.uiSpoofLongitude = appInfo.spoofLongitude
        self.uiSpoofAltitude = appInfo.spoofAltitude
        self.uiSpoofLocationName = appInfo.spoofLocationName ?? ""
        
        // MARK: Camera Addon Section
        self.uiSpoofCamera = appInfo.spoofCamera
        self.uiSpoofCameraType = appInfo.spoofCameraType ?? "video"
        self.uiSpoofCameraImagePath = appInfo.spoofCameraImagePath ?? ""
        self.uiSpoofCameraVideoPath = appInfo.spoofCameraVideoPath ?? ""
        self.uiSpoofCameraLoop = appInfo.spoofCameraLoop
        self.uiSpoofCameraUseVideoAudio = appInfo.spoofCameraUseVideoAudio
        self.uiSpoofCameraMode = appInfo.spoofCameraMode ?? "standard"
        // MARK: Camera transformation options initialization
        self.uiSpoofCameraTransformOrientation = appInfo.spoofCameraTransformOrientation
        self.uiSpoofCameraTransformScale = appInfo.spoofCameraTransformScale
        self.uiSpoofCameraTransformFlip = appInfo.spoofCameraTransformFlip
        
        // MARK: SSL Addon Section
        self.uiBypassSSLPinning = appInfo.bypassSSLPinning

        // MARK: Device Addon Section (Ghost-style)
        self.uiDeviceSpoofingEnabled = appInfo.deviceSpoofingEnabled
        let storedDeviceProfile = appInfo.deviceSpoofProfile ?? "iPhone 17"
        let supportedDeviceProfiles: Set<String> = [
            "iPhone 17 Pro Max",
            "iPhone 17 Pro",
            "iPhone 17",
            "iPhone 17 Air",
            "iPhone 16 Pro Max",
            "iPhone 16 Pro",
            "iPhone 16",
            "iPhone 16e",
            "iPhone 15 Pro Max",
            "iPhone 15 Pro",
            "iPhone 14 Pro Max",
            "iPhone 14 Pro",
            "iPhone 13 Pro Max",
            "iPhone 13 Pro"
        ]
        let normalizedDeviceProfile = supportedDeviceProfiles.contains(storedDeviceProfile) ? storedDeviceProfile : "iPhone 17"
        self.uiDeviceSpoofProfile = normalizedDeviceProfile
        self.uiDeviceSpoofCustomVersion = appInfo.deviceSpoofCustomVersion ?? "26.3"
        self.uiDeviceSpoofDeviceName = appInfo.deviceSpoofDeviceName
        self.uiDeviceSpoofDeviceNameValue = appInfo.deviceSpoofDeviceNameValue ?? "iPhone"
        self.uiDeviceSpoofCarrier = appInfo.deviceSpoofCarrier
        self.uiDeviceSpoofCarrierName = appInfo.deviceSpoofCarrierName ?? "Verizon"
        self.uiDeviceSpoofMCC = appInfo.deviceSpoofMCC ?? "311"
        self.uiDeviceSpoofMNC = appInfo.deviceSpoofMNC ?? "480"
        self.uiDeviceSpoofCarrierCountry = appInfo.deviceSpoofCarrierCountry ?? "us"
        self.uiDeviceSpoofIdentifiers = appInfo.deviceSpoofIdentifiers
        self.uiDeviceSpoofVendorID = appInfo.deviceSpoofVendorID ?? ""
        self.uiDeviceSpoofAdvertisingID = appInfo.deviceSpoofAdvertisingID ?? ""
        self.uiDeviceSpoofAdTrackingMode = appInfo.deviceSpoofAdTrackingMode ?? "auto"
        self.uiDeviceSpoofPersistentDeviceID = appInfo.deviceSpoofPersistentDeviceID ?? ""
        self.uiDeviceSpoofInstallationID = appInfo.deviceSpoofInstallationID ?? ""
        self.uiDeviceSpoofSecurityEnabled = appInfo.deviceSpoofSecurityEnabled
        self.uiDeviceSpoofCloudToken = appInfo.deviceSpoofCloudToken
        self.uiDeviceSpoofDeviceChecker = appInfo.deviceSpoofDeviceChecker
        self.uiDeviceSpoofAppAttest = appInfo.deviceSpoofAppAttest
        self.uiDeviceSpoofSiriPrivacyProtection = appInfo.deviceSpoofSiriPrivacyProtection
        self.uiDeviceSpoofTimezone = appInfo.deviceSpoofTimezone
        self.uiDeviceSpoofTimezoneValue = appInfo.deviceSpoofTimezoneValue ?? "America/New_York"
        self.uiDeviceSpoofLocale = appInfo.deviceSpoofLocale
        self.uiDeviceSpoofLocaleValue = appInfo.deviceSpoofLocaleValue ?? "en_US"
        self.uiDeviceSpoofLocaleCurrencyCode = appInfo.deviceSpoofLocaleCurrencyCode ?? ""
        self.uiDeviceSpoofLocaleCurrencySymbol = appInfo.deviceSpoofLocaleCurrencySymbol ?? ""
        self.uiDeviceSpoofPreferredCountry = appInfo.deviceSpoofPreferredCountry ?? ""
        self.uiDeviceSpoofCellularTypeEnabled = appInfo.deviceSpoofCellularTypeEnabled
        self.uiDeviceSpoofCellularType = Int(appInfo.deviceSpoofCellularType)
        self.uiDeviceSpoofNetworkInfo = appInfo.deviceSpoofNetworkInfo
        self.uiDeviceSpoofWiFiAddressEnabled = appInfo.deviceSpoofWiFiAddressEnabled
        self.uiDeviceSpoofCellularAddressEnabled = appInfo.deviceSpoofCellularAddressEnabled
        self.uiDeviceSpoofMACAddressEnabled = appInfo.deviceSpoofMACAddressEnabled
        self.uiDeviceSpoofWiFiAddress = appInfo.deviceSpoofWiFiAddress ?? ""
        self.uiDeviceSpoofCellularAddress = appInfo.deviceSpoofCellularAddress ?? ""
        self.uiDeviceSpoofWiFiSSID = appInfo.deviceSpoofWiFiSSID ?? "Public Network"
        self.uiDeviceSpoofWiFiBSSID = appInfo.deviceSpoofWiFiBSSID ?? "22:66:99:00"
        self.uiDeviceSpoofMACAddress = appInfo.deviceSpoofMACAddress ?? ""
        self.uiDeviceSpoofCanvasFingerprintProtection = appInfo.deviceSpoofCanvasFingerprintProtection
        self.uiDeviceSpoofScreenCapture = appInfo.deviceSpoofScreenCapture
        self.uiDeviceSpoofMessage = appInfo.enableSpoofMessage
        self.uiDeviceSpoofMail = appInfo.enableSpoofMail
        self.uiDeviceSpoofBugsnag = appInfo.enableSpoofBugsnag
        self.uiDeviceSpoofCrane = appInfo.enableSpoofCrane
        self.uiDeviceSpoofPasteboard = appInfo.enableSpoofPasteboard
        self.uiDeviceSpoofAlbum = appInfo.enableSpoofAlbum
        self.uiDeviceSpoofAppium = appInfo.enableSpoofAppium
        self.uiDeviceSpoofKeyboard = appInfo.enableSpoofKeyboard
        self.uiDeviceSpoofUserDefaults = appInfo.enableSpoofUserDefaults
        self.uiDeviceSpoofEntitlements = appInfo.enableSpoofEntitlements
        self.uiDeviceSpoofFileTimestamps = appInfo.deviceSpoofFileTimestamps
        self.uiDeviceSpoofProximity = appInfo.deviceSpoofProximity
        self.uiDeviceSpoofOrientation = appInfo.deviceSpoofOrientation
        self.uiDeviceSpoofGyroscope = appInfo.deviceSpoofGyroscope
        self.uiDeviceSpoofProcessorEnabled = appInfo.deviceSpoofProcessorEnabled
        self.uiDeviceSpoofProcessorCount = Int(appInfo.deviceSpoofProcessorCount)
        self.uiDeviceSpoofMemoryEnabled = appInfo.deviceSpoofMemoryEnabled
        self.uiDeviceSpoofMemoryCount = appInfo.deviceSpoofMemoryCount ?? "8"
        self.uiDeviceSpoofKernelVersionEnabled = appInfo.deviceSpoofKernelVersionEnabled
        self.uiDeviceSpoofKernelVersion = appInfo.deviceSpoofKernelVersion ?? ""
        self.uiDeviceSpoofKernelRelease = appInfo.deviceSpoofKernelRelease ?? ""
        self.uiDeviceSpoofBuildVersion = appInfo.deviceSpoofBuildVersion ?? ""
        self.uiDeviceSpoofAlbumBlacklist = (appInfo.deviceSpoofAlbumBlacklist as? [String]) ?? []

        // Extended spoofing
        self.uiDeviceSpoofBootTime = appInfo.deviceSpoofBootTime
        self.uiDeviceSpoofBootTimeRange = appInfo.deviceSpoofBootTimeRange ?? "medium"
        self.uiDeviceSpoofBootTimeRandomize = appInfo.deviceSpoofBootTimeRandomize
        self.uiDeviceSpoofUserAgent = appInfo.deviceSpoofUserAgent
        self.uiDeviceSpoofUserAgentValue = appInfo.deviceSpoofUserAgentValue ?? ""
        self.uiDeviceSpoofBattery = appInfo.deviceSpoofBattery
        self.uiDeviceSpoofBatteryRandomize = appInfo.deviceSpoofBatteryRandomize
        self.uiDeviceSpoofBatteryLevel = appInfo.deviceSpoofBatteryLevel
        self.uiDeviceSpoofBatteryState = Int(appInfo.deviceSpoofBatteryState)
        self.uiDeviceSpoofStorage = appInfo.deviceSpoofStorage
        self.uiDeviceSpoofStorageCapacity = Self.resolvedStorageCapacity(for: normalizedDeviceProfile,
                                                                         storedCapacity: appInfo.deviceSpoofStorageCapacity)
        self.uiDeviceSpoofStorageRandomFree = appInfo.deviceSpoofStorageRandomFree
        self.uiDeviceSpoofStorageFreeGB = appInfo.deviceSpoofStorageFreeGB ?? ""
        self.uiDeviceSpoofBrightness = appInfo.deviceSpoofBrightness
        self.uiDeviceSpoofBrightnessRandomize = appInfo.deviceSpoofBrightnessRandomize
        self.uiDeviceSpoofBrightnessValue = appInfo.deviceSpoofBrightnessValue
        self.uiDeviceSpoofThermal = appInfo.deviceSpoofThermal
        self.uiDeviceSpoofThermalState = Int(appInfo.deviceSpoofThermalState)
        self.uiDeviceSpoofLowPowerMode = appInfo.deviceSpoofLowPowerMode
        self.uiDeviceSpoofLowPowerModeValue = appInfo.deviceSpoofLowPowerModeValue

        for container in uiContainers {
            if container.folderName == uiDefaultDataFolder {
                self.uiSelectedContainer = container;
                break
            }
        }
        self.refreshAddonSettingsContainerSelection()
    }

    private func resolvedAddonSettingsContainerFolderName() -> String? {
        if let currentDataFolder = appInfo.dataUUID, !currentDataFolder.isEmpty {
            return currentDataFolder
        }
        if let uiDefaultDataFolder, !uiDefaultDataFolder.isEmpty {
            return uiDefaultDataFolder
        }
        if !uiAddonSettingsContainerFolderName.isEmpty {
            return uiAddonSettingsContainerFolderName
        }
        return nil
    }

    private func addonContainer(withFolderName folderName: String) -> LCContainer? {
        return uiContainers.first { $0.folderName == folderName }
    }

    private func normalizedDeviceSpoofProfile(_ profile: String?) -> String {
        let storedDeviceProfile = profile ?? "iPhone 17"
        let supportedDeviceProfiles: Set<String> = [
            "iPhone 17 Pro Max",
            "iPhone 17 Pro",
            "iPhone 17",
            "iPhone 17 Air",
            "iPhone 16 Pro Max",
            "iPhone 16 Pro",
            "iPhone 16",
            "iPhone 16e",
            "iPhone 15 Pro Max",
            "iPhone 15 Pro",
            "iPhone 14 Pro Max",
            "iPhone 14 Pro",
            "iPhone 13 Pro Max",
            "iPhone 13 Pro"
        ]
        return supportedDeviceProfiles.contains(storedDeviceProfile) ? storedDeviceProfile : "iPhone 17"
    }

    static func minimumStorageCapacity(for profile: String) -> String {
        switch profile {
        case "iPhone 17 Pro Max", "iPhone 17 Pro", "iPhone 17", "iPhone 17 Air":
            return "256"
        case "iPhone 16 Pro Max", "iPhone 15 Pro Max":
            return "256"
        case "iPhone 16 Pro", "iPhone 16", "iPhone 16e",
             "iPhone 15 Pro",
             "iPhone 14 Pro Max", "iPhone 14 Pro",
             "iPhone 13 Pro Max", "iPhone 13 Pro":
            return "128"
        default:
            return "256"
        }
    }

    private static func resolvedStorageCapacity(for profile: String, storedCapacity: String?) -> String {
        guard let storedCapacity else {
            return Self.minimumStorageCapacity(for: profile)
        }
        let normalized = storedCapacity.trimmingCharacters(in: .whitespacesAndNewlines)
        let supportedCapacities: Set<String> = ["64", "128", "256", "512", "1024"]
        if supportedCapacities.contains(normalized) {
            return normalized
        }
        return Self.minimumStorageCapacity(for: profile)
    }

    private func applyAddonSettingsFromAppInfo() {
        isApplyingAddonContainerSettings = true

        // GPS
        self.uiSpoofGPS = appInfo.spoofGPS
        self.uiSpoofLatitude = appInfo.spoofLatitude
        self.uiSpoofLongitude = appInfo.spoofLongitude
        self.uiSpoofAltitude = appInfo.spoofAltitude
        self.uiSpoofLocationName = appInfo.spoofLocationName ?? ""

        // Camera
        self.uiSpoofCamera = appInfo.spoofCamera
        self.uiSpoofCameraType = appInfo.spoofCameraType ?? "video"
        self.uiSpoofCameraImagePath = appInfo.spoofCameraImagePath ?? ""
        self.uiSpoofCameraVideoPath = appInfo.spoofCameraVideoPath ?? ""
        self.uiSpoofCameraLoop = appInfo.spoofCameraLoop
        self.uiSpoofCameraUseVideoAudio = appInfo.spoofCameraUseVideoAudio
        self.uiSpoofCameraMode = appInfo.spoofCameraMode ?? "standard"
        self.uiSpoofCameraTransformOrientation = appInfo.spoofCameraTransformOrientation
        self.uiSpoofCameraTransformScale = appInfo.spoofCameraTransformScale
        self.uiSpoofCameraTransformFlip = appInfo.spoofCameraTransformFlip

        // Device spoofing
        self.uiDeviceSpoofingEnabled = appInfo.deviceSpoofingEnabled
        self.uiDeviceSpoofProfile = normalizedDeviceSpoofProfile(appInfo.deviceSpoofProfile)
        self.uiDeviceSpoofCustomVersion = appInfo.deviceSpoofCustomVersion ?? "26.3"
        self.uiDeviceSpoofDeviceName = appInfo.deviceSpoofDeviceName
        self.uiDeviceSpoofDeviceNameValue = appInfo.deviceSpoofDeviceNameValue ?? "iPhone"
        self.uiDeviceSpoofCarrier = appInfo.deviceSpoofCarrier
        self.uiDeviceSpoofCarrierName = appInfo.deviceSpoofCarrierName ?? "Verizon"
        self.uiDeviceSpoofMCC = appInfo.deviceSpoofMCC ?? "311"
        self.uiDeviceSpoofMNC = appInfo.deviceSpoofMNC ?? "480"
        self.uiDeviceSpoofCarrierCountry = appInfo.deviceSpoofCarrierCountry ?? "us"
        self.uiDeviceSpoofIdentifiers = appInfo.deviceSpoofIdentifiers
        self.uiDeviceSpoofVendorID = appInfo.deviceSpoofVendorID ?? ""
        self.uiDeviceSpoofAdvertisingID = appInfo.deviceSpoofAdvertisingID ?? ""
        self.uiDeviceSpoofAdTrackingMode = appInfo.deviceSpoofAdTrackingMode ?? "auto"
        self.uiDeviceSpoofPersistentDeviceID = appInfo.deviceSpoofPersistentDeviceID ?? ""
        self.uiDeviceSpoofInstallationID = appInfo.deviceSpoofInstallationID ?? ""
        self.uiDeviceSpoofSecurityEnabled = appInfo.deviceSpoofSecurityEnabled
        self.uiDeviceSpoofCloudToken = appInfo.deviceSpoofCloudToken
        self.uiDeviceSpoofDeviceChecker = appInfo.deviceSpoofDeviceChecker
        self.uiDeviceSpoofAppAttest = appInfo.deviceSpoofAppAttest
        self.uiDeviceSpoofSiriPrivacyProtection = appInfo.deviceSpoofSiriPrivacyProtection
        self.uiDeviceSpoofTimezone = appInfo.deviceSpoofTimezone
        self.uiDeviceSpoofTimezoneValue = appInfo.deviceSpoofTimezoneValue ?? "America/New_York"
        self.uiDeviceSpoofLocale = appInfo.deviceSpoofLocale
        self.uiDeviceSpoofLocaleValue = appInfo.deviceSpoofLocaleValue ?? "en_US"
        self.uiDeviceSpoofLocaleCurrencyCode = appInfo.deviceSpoofLocaleCurrencyCode ?? ""
        self.uiDeviceSpoofLocaleCurrencySymbol = appInfo.deviceSpoofLocaleCurrencySymbol ?? ""
        self.uiDeviceSpoofPreferredCountry = appInfo.deviceSpoofPreferredCountry ?? ""
        self.uiDeviceSpoofCellularTypeEnabled = appInfo.deviceSpoofCellularTypeEnabled
        self.uiDeviceSpoofCellularType = Int(appInfo.deviceSpoofCellularType)
        self.uiDeviceSpoofNetworkInfo = appInfo.deviceSpoofNetworkInfo
        self.uiDeviceSpoofWiFiAddressEnabled = appInfo.deviceSpoofWiFiAddressEnabled
        self.uiDeviceSpoofCellularAddressEnabled = appInfo.deviceSpoofCellularAddressEnabled
        self.uiDeviceSpoofMACAddressEnabled = appInfo.deviceSpoofMACAddressEnabled
        self.uiDeviceSpoofWiFiAddress = appInfo.deviceSpoofWiFiAddress ?? ""
        self.uiDeviceSpoofCellularAddress = appInfo.deviceSpoofCellularAddress ?? ""
        self.uiDeviceSpoofWiFiSSID = appInfo.deviceSpoofWiFiSSID ?? "Public Network"
        self.uiDeviceSpoofWiFiBSSID = appInfo.deviceSpoofWiFiBSSID ?? "22:66:99:00"
        self.uiDeviceSpoofMACAddress = appInfo.deviceSpoofMACAddress ?? ""
        self.uiDeviceSpoofCanvasFingerprintProtection = appInfo.deviceSpoofCanvasFingerprintProtection
        self.uiDeviceSpoofScreenCapture = appInfo.deviceSpoofScreenCapture
        self.uiDeviceSpoofMessage = appInfo.enableSpoofMessage
        self.uiDeviceSpoofMail = appInfo.enableSpoofMail
        self.uiDeviceSpoofBugsnag = appInfo.enableSpoofBugsnag
        self.uiDeviceSpoofCrane = appInfo.enableSpoofCrane
        self.uiDeviceSpoofPasteboard = appInfo.enableSpoofPasteboard
        self.uiDeviceSpoofAlbum = appInfo.enableSpoofAlbum
        self.uiDeviceSpoofAppium = appInfo.enableSpoofAppium
        self.uiDeviceSpoofKeyboard = appInfo.enableSpoofKeyboard
        self.uiDeviceSpoofUserDefaults = appInfo.enableSpoofUserDefaults
        self.uiDeviceSpoofEntitlements = appInfo.enableSpoofEntitlements
        self.uiDeviceSpoofFileTimestamps = appInfo.deviceSpoofFileTimestamps
        self.uiDeviceSpoofProximity = appInfo.deviceSpoofProximity
        self.uiDeviceSpoofOrientation = appInfo.deviceSpoofOrientation
        self.uiDeviceSpoofGyroscope = appInfo.deviceSpoofGyroscope
        self.uiDeviceSpoofProcessorEnabled = appInfo.deviceSpoofProcessorEnabled
        self.uiDeviceSpoofProcessorCount = Int(appInfo.deviceSpoofProcessorCount)
        self.uiDeviceSpoofMemoryEnabled = appInfo.deviceSpoofMemoryEnabled
        self.uiDeviceSpoofMemoryCount = appInfo.deviceSpoofMemoryCount ?? "8"
        self.uiDeviceSpoofKernelVersionEnabled = appInfo.deviceSpoofKernelVersionEnabled
        self.uiDeviceSpoofKernelVersion = appInfo.deviceSpoofKernelVersion ?? ""
        self.uiDeviceSpoofKernelRelease = appInfo.deviceSpoofKernelRelease ?? ""
        self.uiDeviceSpoofBuildVersion = appInfo.deviceSpoofBuildVersion ?? ""
        self.uiDeviceSpoofAlbumBlacklist = (appInfo.deviceSpoofAlbumBlacklist as? [String]) ?? []
        self.uiDeviceSpoofBootTime = appInfo.deviceSpoofBootTime
        self.uiDeviceSpoofBootTimeRange = appInfo.deviceSpoofBootTimeRange ?? "medium"
        self.uiDeviceSpoofBootTimeRandomize = appInfo.deviceSpoofBootTimeRandomize
        self.uiDeviceSpoofUserAgent = appInfo.deviceSpoofUserAgent
        self.uiDeviceSpoofUserAgentValue = appInfo.deviceSpoofUserAgentValue ?? ""
        self.uiDeviceSpoofBattery = appInfo.deviceSpoofBattery
        self.uiDeviceSpoofBatteryRandomize = appInfo.deviceSpoofBatteryRandomize
        self.uiDeviceSpoofBatteryLevel = appInfo.deviceSpoofBatteryLevel
        self.uiDeviceSpoofBatteryState = Int(appInfo.deviceSpoofBatteryState)
        self.uiDeviceSpoofStorage = appInfo.deviceSpoofStorage
        self.uiDeviceSpoofStorageCapacity = Self.resolvedStorageCapacity(for: self.uiDeviceSpoofProfile,
                                                                         storedCapacity: appInfo.deviceSpoofStorageCapacity)
        self.uiDeviceSpoofStorageRandomFree = appInfo.deviceSpoofStorageRandomFree
        self.uiDeviceSpoofStorageFreeGB = appInfo.deviceSpoofStorageFreeGB ?? ""
        self.uiDeviceSpoofBrightness = appInfo.deviceSpoofBrightness
        self.uiDeviceSpoofBrightnessRandomize = appInfo.deviceSpoofBrightnessRandomize
        self.uiDeviceSpoofBrightnessValue = appInfo.deviceSpoofBrightnessValue
        self.uiDeviceSpoofThermal = appInfo.deviceSpoofThermal
        self.uiDeviceSpoofThermalState = Int(appInfo.deviceSpoofThermalState)
        self.uiDeviceSpoofLowPowerMode = appInfo.deviceSpoofLowPowerMode
        self.uiDeviceSpoofLowPowerModeValue = appInfo.deviceSpoofLowPowerModeValue

        isApplyingAddonContainerSettings = false
    }

    func switchAddonSettingsContainer(to folderName: String) {
        let targetFolder = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetFolder.isEmpty else { return }
        guard uiContainers.contains(where: { $0.folderName == targetFolder }) else { return }

        let currentFolder = appInfo.dataUUID ?? uiDefaultDataFolder
        if let currentFolder, !currentFolder.isEmpty {
            appInfo.saveAddonSettings(forContainer: currentFolder)
        }

        let targetContainer = addonContainer(withFolderName: targetFolder)
        let fallbackSpoofIDFV = targetContainer?.spoofIdentifierForVendor ?? false
        let fallbackVendorID = targetContainer?.spoofedIdentifier ?? ""
        appInfo.loadAddonSettings(
            forContainer: targetFolder,
            fallbackSpoofIdentifierForVendor: fallbackSpoofIDFV,
            fallbackVendorID: fallbackVendorID
        )

        uiSelectedContainer = targetContainer ?? uiSelectedContainer
        uiDefaultDataFolder = targetFolder
        appInfo.dataUUID = targetFolder
        uiAddonSettingsContainerFolderName = targetFolder

        applyAddonSettingsFromAppInfo()
        syncCurrentContainerIDFVWithDeviceSpoofing()
    }

    func refreshAddonSettingsContainerSelection() {
        if uiContainers.isEmpty {
            uiAddonSettingsContainerFolderName = ""
            return
        }

        if let currentFolder = resolvedAddonSettingsContainerFolderName(),
           uiContainers.contains(where: { $0.folderName == currentFolder }) {
            let shouldSwitch =
                appInfo.dataUUID != currentFolder ||
                uiDefaultDataFolder != currentFolder ||
                uiSelectedContainer?.folderName != currentFolder

            if shouldSwitch {
                switchAddonSettingsContainer(to: currentFolder)
            } else {
                uiAddonSettingsContainerFolderName = currentFolder
                if uiSelectedContainer == nil {
                    uiSelectedContainer = addonContainer(withFolderName: currentFolder)
                }
            }
            return
        }

        if let uiDefaultDataFolder,
           uiContainers.contains(where: { $0.folderName == uiDefaultDataFolder }) {
            switchAddonSettingsContainer(to: uiDefaultDataFolder)
            return
        }

        switchAddonSettingsContainer(to: uiContainers[0].folderName)
    }

    private func resolvedKeychainGroupId(for container: LCContainer) -> Int {
        let existing = container.keychainGroupId
        if existing >= 0 {
            return existing
        }

        var usedGroupIds = Set<Int>()
        for other in uiContainers where other.folderName != container.folderName {
            let groupId = other.keychainGroupId
            if groupId >= 0 {
                usedGroupIds.insert(groupId)
            }
        }

        if SharedModel.keychainAccessGroupCount > 1 {
            for candidate in 1..<SharedModel.keychainAccessGroupCount {
                if !usedGroupIds.contains(candidate) {
                    return candidate
                }
            }
        }
        return 0
    }

    func syncCurrentContainerIDFVWithDeviceSpoofing() {
        guard let folderName = resolvedAddonSettingsContainerFolderName(),
              let container = addonContainer(withFolderName: folderName) else {
            return
        }

        let normalizedVendorID = uiDeviceSpoofVendorID.trimmingCharacters(in: .whitespacesAndNewlines)
        container.spoofIdentifierForVendor = uiDeviceSpoofIdentifiers
        if uiDeviceSpoofIdentifiers {
            if normalizedVendorID.isEmpty {
                if container.spoofedIdentifier == nil || container.spoofedIdentifier?.isEmpty == true {
                    container.spoofedIdentifier = UUID().uuidString
                }
            } else {
                container.spoofedIdentifier = normalizedVendorID
            }
        } else if !normalizedVendorID.isEmpty {
            container.spoofedIdentifier = normalizedVendorID
        }

        let keychainGroupId = resolvedKeychainGroupId(for: container)
        container.makeLCContainerInfoPlist(
            appIdentifier: appInfo.bundleIdentifier() ?? "",
            keychainGroupId: keychainGroupId
        )
        appInfo.containers = uiContainers

        if uiDeviceSpoofIdentifiers,
           (uiDeviceSpoofVendorID.isEmpty || uiDeviceSpoofVendorID != container.spoofedIdentifier) {
            isApplyingAddonContainerSettings = true
            uiDeviceSpoofVendorID = container.spoofedIdentifier ?? ""
            isApplyingAddonContainerSettings = false
            appInfo.deviceSpoofVendorID = uiDeviceSpoofVendorID
        }
    }
    
    static func == (lhs: LCAppModel, rhs: LCAppModel) -> Bool {
        return lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    func runApp(multitask: Bool = false, containerFolderName : String? = nil, bundleIdOverride : String? = nil, forceJIT: Bool? = nil) async throws{
        if isAppRunning {
            return
        }
        
        if uiContainers.isEmpty {
            let newName = NSUUID().uuidString
            let newContainer = LCContainer(folderName: newName, name: newName, isShared: uiIsShared)
            uiContainers.append(newContainer)
            if uiSelectedContainer == nil {
                uiSelectedContainer = newContainer;
            }
            appInfo.containers = uiContainers;
            newContainer.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: Int.random(in: 0..<SharedModel.keychainAccessGroupCount))
            switchAddonSettingsContainer(to: newName)
        }
        if let containerFolderName {
            uiSelectedContainer = uiContainers.first { $0.folderName == containerFolderName } ?? uiSelectedContainer
        }
        let currentDataFolder = containerFolderName ?? uiSelectedContainer?.folderName
        
        if multitask,
           let currentDataFolder,
           await bringExistingMultitaskWindowIfNeeded(dataUUID: currentDataFolder) {
            return
        }
        
        // this is rerouted to bringing app to front, so not needed here?
//        if(MultitaskManager.isUsing(container: uiSelectedContainer!.folderName)) {
//            throw "lc.container.inUse".loc + "\n MultiTask"
//        }
        
        // if the selected container is in use (either other lc or multitask), open the host lc associated with it
        if
            let fn = uiSelectedContainer?.folderName,
            var runningLC = LCSharedUtils.getContainerUsingLCScheme(withFolderName: fn)
        {
            runningLC = (runningLC as NSString).deletingPathExtension
            
            let openURL = URL(string: "\(runningLC)://")!
            if await UIApplication.shared.canOpenURL(openURL) {
                await UIApplication.shared.open(openURL)
                return
            }
        }
        
        // ask user if they want to terminate all multitasking apps
        if MultitaskManager.isMultitasking() && !multitask {
            if let currentDataFolder,
               await bringExistingMultitaskWindowIfNeeded(dataUUID: currentDataFolder) {
                return
            }
            
            guard let ans = await delegate?.showRunWhenMultitaskAlert(), ans else {
                return
            }
        }
        
        await MainActor.run {
            isAppRunning = true
        }
        defer {
            Task { await MainActor.run {
                isAppRunning = false
            }}
        }
        try await signApp(force: false)
        
        if let bundleIdOverride {
            UserDefaults.standard.set(bundleIdOverride, forKey: "selected")
        } else {
            UserDefaults.standard.set(self.appInfo.relativeBundlePath, forKey: "selected")
        }
        

        UserDefaults.standard.set(uiSelectedContainer?.folderName, forKey: "selectedContainer")
        var is32bit = false
        
        #if is32BitSupported
        is32bit = appInfo.is32bit
        #endif
        var jitNeeded = appInfo.isJITNeeded
        if let forceJIT {
            jitNeeded = forceJIT
        }
        if jitNeeded || is32bit {
            if multitask, #available(iOS 17.4, *) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    LCUtils.launchMultitaskGuestApp(appInfo.displayName()) { pidNumber, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let pidNumber = pidNumber else {
                            continuation.resume(throwing: "Failed to obtain PID from LiveProcess")
                            return
                        }
                        Task {
                            if let scriptData = self.jitLaunchScriptJs, !scriptData.isEmpty {
                                await self.delegate?.jitLaunch(withPID: pidNumber.intValue, withScript: scriptData)
                            } else {
                                await self.delegate?.jitLaunch(withPID: pidNumber.intValue, withScript: nil)
                            }
                            continuation.resume()
                        }
                    }
                }
            } else {
                // Non-multitask JIT flow remains unchanged
                if let scriptData = jitLaunchScriptJs, !scriptData.isEmpty {
                    await delegate?.jitLaunch(withScript: scriptData)
                } else {
                    await delegate?.jitLaunch()
                }
            }
        } else if multitask, #available(iOS 16.0, *) {
            try await LCUtils.launchMultitaskGuestApp(appInfo.displayName())
        } else {
            if #available(iOS 26.0, *), FileManager.default.fileExists(atPath: "\(appInfo.bundlePath()!)/Frameworks/MetalANGLE.framework/MetalANGLE") {
                let fileContents = "\(appInfo.bundlePath()!)/Frameworks/MetalANGLE.framework/MetalANGLE".data(using: .utf8)
                let fileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("preloadLibraries.txt")
                try fileContents?.write(to: fileURL)
            }
            LCSharedUtils.launchToGuestApp()
        }
        
        // Record the launch time
        appInfo.lastLaunched = Date()
        await MainActor.run {
            isAppRunning = false
        }
    }
    
    func forceResign() async throws {
        if isAppRunning {
            return
        }
        isAppRunning = true
        defer {
            Task{ await MainActor.run {
                self.isAppRunning = false
            }}

        }
        try await signApp(force: true)
    }
    
    func signApp(force: Bool = false) async throws {
        var signError : String? = nil
        var signSuccess = false
        defer {
            Task{ await MainActor.run {
                self.isSigningInProgress = false
            }}
        }
        
        await withUnsafeContinuation({ c in
            appInfo.patchExecAndSignIfNeed(completionHandler: { success, error in
                signError = error;
                signSuccess = success;
                c.resume()
            }, progressHandler: { signProgress in
                guard let signProgress else {
                    return
                }
                self.isSigningInProgress = true
                self.observer = signProgress.observe(\.fractionCompleted) { p, v in
                    DispatchQueue.main.async {
                        self.signProgress = signProgress.fractionCompleted
                    }
                }
            }, forceSign: force)
        })
        if let signError {
            if !signSuccess {
                throw signError.loc
            }
        }
        
        // sign its tweak
        guard let tweakFolder = appInfo.tweakFolder else {
            return
        }
        
        let tweakFolderUrl : URL
        if(appInfo.isShared) {
            tweakFolderUrl = LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder)
        } else {
            tweakFolderUrl = LCPath.tweakPath.appendingPathComponent(tweakFolder)
        }
        try await LCUtils.signTweaks(tweakFolderUrl: tweakFolderUrl, force: force) { p in
            Task{ await MainActor.run {
                self.isSigningInProgress = true
            }}
        }
        
        // sign global tweak
        try await LCUtils.signTweaks(tweakFolderUrl: LCPath.tweakPath, force: force) { p in
            Task{ await MainActor.run {
                self.isSigningInProgress = true
            }}
        }
    }

    func setLocked(newLockState: Bool) async {
        // if locked state in appinfo already match with the new state, we just the change
        if appInfo.isLocked == newLockState {
            return
        }
        
        if newLockState {
            appInfo.isLocked = true
        } else {
            // authenticate before cancelling locked state
            do {
                let result = try await LCUtils.authenticateUser()
                if !result {
                    uiIsLocked = true
                    return
                }
            } catch {
                uiIsLocked = true
                return
            }
            
            // auth pass, we need to cancel app's lock and hidden state
            appInfo.isLocked = false
            if appInfo.isHidden {
                await toggleHidden()
            }
        }
    }
    
    func toggleHidden() async {
        delegate?.closeNavigationView()
        if appInfo.isHidden {
            appInfo.isHidden = false
            uiIsHidden = false
        } else {
            appInfo.isHidden = true
            uiIsHidden = true
        }
        delegate?.changeAppVisibility(app: self)
    }
    
    func loadSupportedLanguages() throws {
        let fm = FileManager.default
        if supportedLanguages != nil {
            return
        }
        supportedLanguages = []
        let fileURLs = try fm.contentsOfDirectory(at: URL(fileURLWithPath: appInfo.bundlePath()!) , includingPropertiesForKeys: nil)
        for fileURL in fileURLs {
            let attributes = try fm.attributesOfItem(atPath: fileURL.path)
            let fileType = attributes[.type] as? FileAttributeType
            if(fileType == .typeDirectory && fileURL.lastPathComponent.hasSuffix(".lproj")) {
                supportedLanguages?.append(fileURL.deletingPathExtension().lastPathComponent)
            }
        }
        
    }
    
    private func bringExistingMultitaskWindowIfNeeded(dataUUID: String) async -> Bool {
        guard #available(iOS 16.0, *) else { return false }
        return await MainActor.run {
            var found = false
            if #available(iOS 16.1, *) {
                found = MultitaskWindowManager.openExistingAppWindow(dataUUID: dataUUID)
            }
            if !found {
                found = MultitaskDockManager.shared.bringMultitaskViewToFront(uuid: dataUUID)
            }
            return found
        }
    }
}
