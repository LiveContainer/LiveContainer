//
//  Shared.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/22.
//

import SwiftUI
import UniformTypeIdentifiers
import SafariServices
import Security
import Combine

struct LCPath {
    public static let docPath = {
        let fm = FileManager()
        return fm.urls(for: .documentDirectory, in: .userDomainMask).last!
    }()
    public static let bundlePath = docPath.appendingPathComponent("Applications")
    public static let dataPath = docPath.appendingPathComponent("Data/Application")
    public static let appGroupPath = docPath.appendingPathComponent("Data/AppGroup")
    public static let tweakPath = docPath.appendingPathComponent("Tweaks")
    
    public static let lcGroupDocPath = {
        let fm = FileManager()
        // it seems that Apple don't want to create one for us, so we just borrow our Store's
        if let appGroupPathUrl = LCSharedUtils.appGroupPath() {
            return appGroupPathUrl.appendingPathComponent("LiveContainer")
        } else if let appGroupPathUrl =
                    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.SideStore.SideStore") {
            return appGroupPathUrl.appendingPathComponent("LiveContainer")
        } else {
            return docPath
        }
    }()
    public static let lcGroupBundlePath = lcGroupDocPath.appendingPathComponent("Applications")
    public static let lcGroupDataPath = lcGroupDocPath.appendingPathComponent("Data/Application")
    public static let lcGroupAppGroupPath = lcGroupDocPath.appendingPathComponent("Data/AppGroup")
    public static let lcGroupTweakPath = lcGroupDocPath.appendingPathComponent("Tweaks")
    
    public static func ensureAppGroupPaths() throws {
        let fm = FileManager()
        if !fm.fileExists(atPath: LCPath.lcGroupBundlePath.path) {
            try fm.createDirectory(at: LCPath.lcGroupBundlePath, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: LCPath.lcGroupDataPath.path) {
            try fm.createDirectory(at: LCPath.lcGroupDataPath, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: LCPath.lcGroupTweakPath.path) {
            try fm.createDirectory(at: LCPath.lcGroupTweakPath, withIntermediateDirectories: true)
        }
    }
}

class SharedModel: ObservableObject {
    @Published var selectedTab: LCTabIdentifier = .apps
    @Published var deepLink: URL?
    
    @Published var isHiddenAppUnlocked = false
    @Published var developerMode = false
    // 0 = current liveContainer is the primary one,
    // 2 = current liveContainer is not the primary one
    @Published var multiLCStatus = 0
    @Published var isJITModalOpen = false
    
    @Published var enableMultipleWindow = false
    
    @Published var apps : [LCAppModel] = []
    @Published var hiddenApps : [LCAppModel] = []
    
    @Published var pidCallback : ((NSNumber, Error?) -> Void)? = nil
    
    static let isPhone: Bool = {
        UIDevice.current.userInterfaceIdiom == .phone
    }()
    
    static let isLiquidGlassEnabled = {
        if #available(iOS 19.0, *), (dyld_get_program_sdk_version() >= 0x1a0000 || UserDefaults.standard.bool(forKey: "com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck")) {
            if let compatibilityEnabled = Bundle.main.infoDictionary?["UIDesignRequiresCompatibility"] as? Bool, compatibilityEnabled {
                return false
            }
            
            return true
        }
        return false
    }()
    
    static let isLiquidGlassSearchEnabled = {
            return isLiquidGlassEnabled && UIDevice.current.userInterfaceIdiom == .phone
    }()
    
    var mainWindowOpened = false
    
    public static let keychainAccessGroupCount = 128
    
    func updateMultiLCStatus() {
        if LCUtils.appUrlScheme()?.lowercased() != "livecontainer" {
            multiLCStatus = 2
        } else {
            multiLCStatus = 0
        }
    }
    
    init() {
        updateMultiLCStatus()
    }
}

class DataManager {
    static let shared = DataManager()
    let model = SharedModel()
}

class AlertHelper<T> : ObservableObject {
    @Published var show = false
    private var result : T?
    private var c : UnsafeContinuation<Void, Never>? = nil
    
    func open() async -> T? {
        await withUnsafeContinuation { c in
            self.c = c
            Task { await MainActor.run {
                self.show = true
            }}
        }
        return self.result
    }
    
    func close(result: T?) {
        if let c {
            self.result = result
            c.resume()
            self.c = nil
        }
        DispatchQueue.main.async {
            self.show = false
        }

    }
}

typealias YesNoHelper = AlertHelper<Bool>

class InputHelper : AlertHelper<String> {
    @Published var initVal = ""
    
    func open(initVal: String) async -> String? {
        self.initVal = initVal
        return await super.open()
    }
    
    override func open() async -> String? {
        self.initVal = ""
        return await super.open()
    }
}

extension String: @retroactive Error {}
extension String: @retroactive LocalizedError {
    public var errorDescription: String? { return self }
        
    private static var enBundle : Bundle? = {
        let language = "en"
        let path = Bundle.main.path(forResource:language, ofType: "lproj")
        let bundle = Bundle(path: path!)
        return bundle
    }()
    
    var loc: String {
        let message = NSLocalizedString(self, comment: "")
        if message != self {
            return message
        }

        if let forcedString = String.enBundle?.localizedString(forKey: self, value: nil, table: nil){
            return forcedString
        }else {
            return self
        }
    }
    
    func localizeWithFormat(_ arguments: CVarArg...) -> String{
        String.localizedStringWithFormat(self.loc, arguments)
    }
    
    func sanitizeNonACSII() -> String  {
        filter { $0.isASCII }
    }
}

extension UTType {
    static let ipa = UTType(filenameExtension: "ipa")!
    static let tipa = UTType(filenameExtension: "tipa")!
    static let dylib = UTType(filenameExtension: "dylib")!
    static let deb = UTType(filenameExtension: "deb")!
    static let zipArchive = UTType(filenameExtension: "zip")!
    static let lcFramework = UTType(filenameExtension: "framework", conformingTo: .package)!
    static let p12 = UTType(filenameExtension: "p12")!
}

extension Color {
    func readableTextColor() -> Color {
        let color = Color(.systemBackground)
        let percentage = 0.5
        
        // https://stackoverflow.com/a/78649412
        let components1 = UIColor(self).cgColor.components!
        var bgR: CGFloat = 0, bgG: CGFloat = 0, bgB: CGFloat = 0, bgA: CGFloat = 0
        UIColor(color).getRed(&bgR, green: &bgG, blue: &bgB, alpha: &bgA)
        var red = (1.0 - percentage) * components1[0] + percentage * bgR
        var green = (1.0 - percentage) * components1[1] + percentage * bgG
        var blue = (1.0 - percentage) * components1[2] + percentage * bgB
        //var alpha = (1.0 - percentage) * components1[3] + percentage * bgA
        //UIColor(mix(with: Color(.systemBackground), by: 0.5)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let brightness = (0.2126*red + 0.7152*green + 0.0722*blue);
        let brightnessOffset = brightness < 0.5 ? 0.4 : -0.4
        red = min(Double(red) + brightnessOffset, 1.0)
        green = min(Double(green) + brightnessOffset, 1.0)
        blue = min(Double(blue) + brightnessOffset, 1.0)
        return Color(red: red, green: green, blue: blue)
    }
}

struct ImageDocument: FileDocument {
    var data: Data
    
    static var readableContentTypes: [UTType] {
        [UTType.image] // Specify that the document supports image files
    }
    
    // Initialize with data
    init(uiImage: UIImage) {
        self.data = uiImage.pngData()!
    }
    
    // Function to read the data from the file
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    // Write data to the file
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}


struct SiteAssociationDetailItem : Codable {
    var appID: String?
    var appIDs: [String]?
    
    func getBundleIds() -> [String] {
        var ans : [String] = []
        // get rid of developer id
        if let appID = appID, appID.count > 11 {
            let index = appID.index(appID.startIndex, offsetBy: 11)
            let modifiedString = String(appID[index...])
            ans.append(modifiedString)
        }
        if let appIDs = appIDs {
            for appID in appIDs {
                if appID.count > 11 {
                    let index = appID.index(appID.startIndex, offsetBy: 11)
                    let modifiedString = String(appID[index...])
                    ans.append(modifiedString)
                }
            }
        }
        return ans
    }
}

struct AppLinks : Codable {
    var details : [SiteAssociationDetailItem]?
}

struct SiteAssociation : Codable {
    var applinks: AppLinks?
}


struct JITStreamerEBLaunchAppResponse : Codable {
    let ok: Bool
    let launching: Bool
    let position: Int?
    let error: String?
}

struct JITStreamerEBStatusResponse : Codable {
    let ok: Bool
    let done: Bool
    let position: Int?
    let error: String?
}

struct JITStreamerEBMountResponse : Codable {
    let ok: Bool
    let mounting: Bool
    let error: String?
}



extension NSNotification {
    static let InstallAppNotification = Notification.Name.init("InstallAppNotification")
}

public enum LCTabIdentifier: Hashable {
    case sources
    case apps
    case tweaks
    case settings
    case search
}
