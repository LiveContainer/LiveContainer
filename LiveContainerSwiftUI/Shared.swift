//
//  Shared.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/22.
//

import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import SafariServices
import Security
import Combine

enum MultitaskMode : Int {
    case virtualWindow = 0
    case nativeWindow = 1
}

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
        if let appGroupPathUrl = LCUtils.appGroupPath() {
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
    @Published var isHiddenAppUnlocked = false
    @Published var developerMode = false
    // 0= not installed, 1= is installed, 2=current liveContainer is the second one
    @Published var multiLCStatus = 0
    @Published var isJITModalOpen = false
    
    @Published var enableMultipleWindow = false
    
    @Published var apps : [LCAppModel] = []
    @Published var hiddenApps : [LCAppModel] = []
    
    let isPhone: Bool = {
        UIDevice.current.userInterfaceIdiom == .phone
    }()
    
    let isLiquidGlassSearchEnabled = {
        if #available(iOS 19.0, *) {
            return UIDevice.current.userInterfaceIdiom == .phone &&
            (dyld_get_program_sdk_version() >= 0x1a0000 || UserDefaults.standard.bool(forKey: "com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck"))
        } else {
            return false
        }
    }()
    
    var mainWindowOpened = false
    
    public static let keychainAccessGroupCount = 128
    
    func updateMultiLCStatus() {
        if LCUtils.appUrlScheme()?.lowercased() != "livecontainer" {
            multiLCStatus = 2
        } else if UIApplication.shared.canOpenURL(URL(string: "livecontainer2://")!) {
            multiLCStatus = 1
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
    
}

extension UTType {
    static let ipa = UTType(filenameExtension: "ipa")!
    static let tipa = UTType(filenameExtension: "tipa")!
    static let dylib = UTType(filenameExtension: "dylib")!
    static let deb = UTType(filenameExtension: "deb")!
    static let lcFramework = UTType(filenameExtension: "framework", conformingTo: .package)!
    static let p12 = UTType(filenameExtension: "p12")!
}

struct SafariView: UIViewControllerRepresentable {
    let url: Binding<URL>
    func makeUIViewController(context: UIViewControllerRepresentableContext<Self>) -> SFSafariViewController {
        return SFSafariViewController(url: url.wrappedValue)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {
        
    }
}

// https://stackoverflow.com/questions/56726663/how-to-add-a-textfield-to-alert-in-swiftui
extension View {

    public func textFieldAlert(
        isPresented: Binding<Bool>,
        title: String,
        text: Binding<String>,
        placeholder: String = "",
        action: @escaping (String?) -> Void,
        actionCancel: @escaping (String?) -> Void
    ) -> some View {
        self.modifier(TextFieldAlertModifier(isPresented: isPresented, title: title, text: text, placeholder: placeholder, action: action, actionCancel: actionCancel))
    }
    
    public func betterFileImporter(
        isPresented: Binding<Bool>,
        types : [UTType],
        multiple : Bool = false,
        callback: @escaping ([URL]) -> (),
        onDismiss: @escaping () -> Void
    ) -> some View {
        self.modifier(DocModifier(isPresented: isPresented, types: types, multiple: multiple, callback: callback, onDismiss: onDismiss))
    }
    
    func onBackground(_ f: @escaping () -> Void) -> some View {
        self.onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification),
            perform: { _ in f() }
        )
    }
    
    func onForeground(_ f: @escaping () -> Void) -> some View {
        self.onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification),
            perform: { _ in f() }
        )
    }
    
    func rainbow() -> some View {
        self.modifier(RainbowAnimation())
    }
    
    func navigationBarProgressBar(show: Binding<Bool>, progress: Binding<Float>) -> some View {
        self.modifier(NavigationBarProgressModifier(show: show, progress: progress))
    }
}

public struct DocModifier: ViewModifier {
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State private var docController: UIDocumentPickerViewController?
    @State private var delegate : UIDocumentPickerDelegate
    
    @Binding var isPresented: Bool

    var callback: ([URL]) -> ()
    private let onDismiss: () -> Void
    private let types : [UTType]
    private let multiple : Bool
    
    init(isPresented : Binding<Bool>, types : [UTType], multiple : Bool, callback: @escaping ([URL]) -> (), onDismiss: @escaping () -> Void) {
        self.callback = callback
        self.onDismiss = onDismiss
        self.types = types
        self.multiple = multiple
        self.delegate = Coordinator(callback: callback, onDismiss: onDismiss)
        self._isPresented = isPresented
    }

    public func body(content: Content) -> some View {
        content.onChange(of: isPresented) { isPresented in
            if isPresented, docController == nil {
                let controller = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
                controller.allowsMultipleSelection = multiple
                controller.delegate = delegate
                self.docController = controller
                sceneDelegate.window?.rootViewController?.present(controller, animated: true)
            } else if !isPresented, let docController = docController {
                docController.dismiss(animated: true)
                self.docController = nil
            }
        }
    }

    private func shutdown() {
        isPresented = false
        docController = nil
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var callback: ([URL]) -> ()
        private let onDismiss: () -> Void
        
        init(callback: @escaping ([URL]) -> Void, onDismiss: @escaping () -> Void) {
            self.callback = callback
            self.onDismiss = onDismiss
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            callback(urls)
            onDismiss()
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDismiss()
        }
    }

}

public struct TextFieldAlertModifier: ViewModifier {
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State private var alertController: UIAlertController?

    @Binding var isPresented: Bool

    let title: String
    let text: Binding<String>
    let placeholder: String
    let action: (String?) -> Void
    let actionCancel: (String?) -> Void

    public func body(content: Content) -> some View {
        content.onChange(of: isPresented) { isPresented in
            if isPresented, alertController == nil {
                let alertController = makeAlertController()
                self.alertController = alertController
                sceneDelegate.window?.rootViewController?.present(alertController, animated: true)
            } else if !isPresented, let alertController = alertController {
                alertController.dismiss(animated: true)
                self.alertController = nil
            }
        }
    }

    private func makeAlertController() -> UIAlertController {
        let controller = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        controller.addTextField {
            $0.placeholder = self.placeholder
            $0.text = self.text.wrappedValue
            $0.clearButtonMode = .always
        }
        controller.addAction(UIAlertAction(title: "lc.common.cancel".loc, style: .cancel) { _ in
            self.actionCancel(nil)
            shutdown()
        })
        controller.addAction(UIAlertAction(title: "lc.common.ok".loc, style: .default) { _ in
            self.action(controller.textFields?.first?.text)
            shutdown()
        })
        return controller
    }

    private func shutdown() {
        isPresented = false
        alertController = nil
    }

}

struct NavigationBarProgressModifier: ViewModifier {
    @Binding var show: Bool
    @Binding var progress: Float

    func body(content: Content) -> some View {
        content
            .background(NavigationBarProgressView(show: $show, progress: $progress))
    }
}

private struct NavigationBarProgressView: UIViewControllerRepresentable {
    @Binding var show: Bool
    @Binding var progress: Float

    func makeUIViewController(context: Context) -> ProgressInjectorViewController {
        ProgressInjectorViewController(progress: progress)
    }

    func updateUIViewController(_ uiViewController: ProgressInjectorViewController, context: Context) {
        uiViewController.updateProgress(!show, progress)
    }

    class ProgressInjectorViewController: UIViewController {
        private var progressView: UIProgressView?

        init(progress: Float) {
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            injectProgressView()
        }

        func updateProgress(_ hidden: Bool, _ progress: Float) {
            progressView?.setProgress(progress, animated: false)
            progressView?.isHidden = hidden
        }

        private func injectProgressView() {
            guard let navigationBar = self.navigationController?.navigationBar, progressView == nil else { return }

            let barProgress = UIProgressView(progressViewStyle: .bar)
            barProgress.translatesAutoresizingMaskIntoConstraints = false
            var contentView : UIView? = nil
            for curView in navigationBar.subviews {
                if NSStringFromClass(curView.classForCoder) == "_UINavigationBarContentView" ||
                    NSStringFromClass(curView.classForCoder) == "UIKit.NavigationBarContentView" {
                    contentView = curView
                    break
                }
            }
            if let contentView {
                contentView.addSubview(barProgress)
                NSLayoutConstraint.activate([
                    barProgress.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    barProgress.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                    barProgress.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
                ])
            }
            self.progressView = barProgress
        }

    }
}

// https://kieranb662.github.io/blog/2020/04/15/Rainbow
struct RainbowAnimation: ViewModifier {
    // 1
    @State var isOn: Bool = false
    let hueColors = stride(from: 0, to: 1, by: 0.01).map {
        Color(hue: $0, saturation: 1, brightness: 1)
    }
    // 2
    var duration: Double = 4
    var animation: Animation {
        Animation
            .linear(duration: duration)
            .repeatForever(autoreverses: false)
    }

    func body(content: Content) -> some View {
    // 3
        let gradient = LinearGradient(gradient: Gradient(colors: hueColors+hueColors), startPoint: .leading, endPoint: .trailing)
        return content.overlay(GeometryReader { proxy in
            ZStack {
                gradient
    // 4
                    .frame(width: 2*proxy.size.width)
    // 5
                    .offset(x: self.isOn ? -proxy.size.width : 0)
            }
        })
    // 6
        .onAppear {
            withAnimation(self.animation) {
                self.isOn = true
            }
        }
        .mask(content)
    }
}

struct BasicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        return UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
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

extension LCUtils {
    public static let appGroupUserDefault = UserDefaults.init(suiteName: LCUtils.appGroupID()) ?? UserDefaults.standard
    
    public static func signFilesInFolder(url: URL, onProgressCreated: (Progress) -> Void) async -> String? {
        let fm = FileManager()
        var ans : String? = nil
        let codesignPath = url.appendingPathComponent("_CodeSignature")
        let provisionPath = url.appendingPathComponent("embedded.mobileprovision")
        let tmpExecPath = url.appendingPathComponent("LiveContainer.tmp")
        let tmpInfoPath = url.appendingPathComponent("Info.plist")
        var info = Bundle.main.infoDictionary!;
        info["CFBundleExecutable"] = "LiveContainer.tmp";
        let nsInfo = info as NSDictionary
        nsInfo.write(to: tmpInfoPath, atomically: true)
        do {
            try fm.copyItem(at: Bundle.main.executableURL!, to: tmpExecPath)
        } catch {
            return nil
        }
        LCPatchAppBundleFixupARM64eSlice(url)
        await withUnsafeContinuation { c in
            func compeletionHandler(success: Bool, error: Error?){
                do {
                    if let error = error {
                        ans = error.localizedDescription
                    }
                    if(fm.fileExists(atPath: codesignPath.path)) {
                        try fm.removeItem(at: codesignPath)
                    }
                    if(fm.fileExists(atPath: provisionPath.path)) {
                        try fm.removeItem(at: provisionPath)
                    }

                    try fm.removeItem(at: tmpExecPath)
                    try fm.removeItem(at: tmpInfoPath)
                } catch {
                    ans = error.localizedDescription
                }
                c.resume()
            }
            let progress = LCUtils.signAppBundle(withZSign: url, completionHandler: compeletionHandler)
            
            guard let progress = progress else {
                ans = "lc.utils.initSigningError".loc
                c.resume()
                return
            }
            onProgressCreated(progress)
        }
        return ans

    }
    
    public static func signTweaks(tweakFolderUrl: URL, force : Bool = false, progressHandler : ((Progress) -> Void)? = nil) async throws {
        guard LCUtils.certificatePassword() != nil else {
            return
        }
        let fm = FileManager.default
        var isFolder :ObjCBool = false
        if(fm.fileExists(atPath: tweakFolderUrl.path, isDirectory: &isFolder) && !isFolder.boolValue) {
            return
        }
        
        // check if re-sign is needed
        // if sign is expired, or inode number of any file changes, we need to re-sign
        let tweakSignInfo = NSMutableDictionary(contentsOf: tweakFolderUrl.appendingPathComponent("TweakInfo.plist")) ?? NSMutableDictionary()
        var signNeeded = false
        if !force {
            let tweakFileINodeRecord = tweakSignInfo["files"] as? [String:NSNumber] ?? [String:NSNumber]()
            let fileURLs = try fm.contentsOfDirectory(at: tweakFolderUrl, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                let attributes = try fm.attributesOfItem(atPath: fileURL.path)
                let fileType = attributes[.type] as? FileAttributeType
                if(fileType != FileAttributeType.typeDirectory && fileType != FileAttributeType.typeRegular) {
                    continue
                }
                if(fileType == FileAttributeType.typeDirectory && !fileURL.lastPathComponent.hasSuffix(".framework")) {
                    continue
                }
                if(fileType == FileAttributeType.typeRegular && !fileURL.lastPathComponent.hasSuffix(".dylib")) {
                    continue
                }
                
                if(fileURL.lastPathComponent == "TweakInfo.plist"){
                    continue
                }
                let inodeNumber = try fm.attributesOfItem(atPath: fileURL.path)[.systemFileNumber] as? NSNumber
                if let fileInodeNumber = tweakFileINodeRecord[fileURL.lastPathComponent] {
                    if(fileInodeNumber != inodeNumber || !checkCodeSignature((fileURL.path as NSString).utf8String)) {
                        signNeeded = true
                        break
                    }
                } else {
                    signNeeded = true
                    break
                }
                
                print(fileURL.lastPathComponent) // Prints the file name
            }
            
        } else {
            signNeeded = true
        }
        
        guard signNeeded else {
            return
        }
        // sign start
        
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("TweakTmp.app")
        if fm.fileExists(atPath: tmpDir.path) {
            try fm.removeItem(at: tmpDir)
        }
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        
        var tmpPaths : [URL] = []
        // copy items to tmp folders
        let fileURLs = try fm.contentsOfDirectory(at: tweakFolderUrl, includingPropertiesForKeys: nil)
        for fileURL in fileURLs {
            let attributes = try fm.attributesOfItem(atPath: fileURL.path)
            let fileType = attributes[.type] as? FileAttributeType
            if(fileType != FileAttributeType.typeDirectory && fileType != FileAttributeType.typeRegular) {
                continue
            }
            if(fileType == FileAttributeType.typeDirectory && !fileURL.lastPathComponent.hasSuffix(".framework")) {
                continue
            }
            if(fileType == FileAttributeType.typeRegular && !fileURL.lastPathComponent.hasSuffix(".dylib")) {
                continue
            }
            
            let tmpPath = tmpDir.appendingPathComponent(fileURL.lastPathComponent)
            tmpPaths.append(tmpPath)
            try fm.copyItem(at: fileURL, to: tmpPath)
        }
        
        if tmpPaths.isEmpty {
            try fm.removeItem(at: tmpDir)
            return
        }
        
        let error = await LCUtils.signFilesInFolder(url: tmpDir) { p in
            if let progressHandler {
                progressHandler(p)
            }
        }
        if let error = error {
            throw error
        }
        
        // move signed files back and rebuild TweakInfo.plist
        tweakSignInfo.removeAllObjects()
        var fileInodes = [String:NSNumber]()
        for tmpFile in tmpPaths {
            let toPath = tweakFolderUrl.appendingPathComponent(tmpFile.lastPathComponent)
            // remove original item and move the signed ones back
            if fm.fileExists(atPath: toPath.path) {
                try fm.removeItem(at: toPath)
                
            }
            try fm.moveItem(at: tmpFile, to: toPath)
            if let inodeNumber = try fm.attributesOfItem(atPath: toPath.path)[.systemFileNumber] as? NSNumber {
                fileInodes[tmpFile.lastPathComponent] = inodeNumber
            }
        }
        try fm.removeItem(at: tmpDir)

        tweakSignInfo["files"] = fileInodes
        try tweakSignInfo.write(to: tweakFolderUrl.appendingPathComponent("TweakInfo.plist"))
        
    }
        
    private static func authenticateUser(completion: @escaping (Bool, Error?) -> Void) {
        // Create a context for authentication
        let context = LAContext()
        var error: NSError?

        // Check if the device supports biometric authentication
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            // Determine the reason for the authentication request
            let reason = "lc.utils.requireAuthentication".loc

            // Evaluate the authentication policy
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evaluationError in
                DispatchQueue.main.async {
                    if success {
                        // Authentication successful
                        completion(true, nil)
                    } else {
                        if let evaluationError = evaluationError as? LAError, evaluationError.code == LAError.userCancel || evaluationError.code == LAError.appCancel {
                            completion(false, nil)
                        } else {
                            // Authentication failed
                            completion(false, evaluationError)
                        }

                    }
                }
            }
        } else {
            // Biometric authentication is not available
            DispatchQueue.main.async {
                if let evaluationError = error as? LAError, evaluationError.code == LAError.passcodeNotSet {
                    // No passcode set, we also define this as successful Authentication
                    completion(true, nil)
                } else {
                    completion(false, error)
                }

            }
        }
    }
    
    public static func authenticateUser() async throws -> Bool {
        if DataManager.shared.model.isHiddenAppUnlocked {
            return true
        }
        
        var success = false
        var error : Error? = nil
        await withUnsafeContinuation { c in
            LCUtils.authenticateUser { success1, error1 in
                success = success1
                error = error1
                c.resume()
            }
        }
        if let error = error {
            throw error
        }
        if !success {
            return false
        }
        DispatchQueue.main.async {
            DataManager.shared.model.isHiddenAppUnlocked = true
        }
        return true
    }
    
    public static func getStoreName() -> String {
        switch LCUtils.store() {
        case .AltStore:
            return "AltStore"
        case .SideStore:
            return "SideStore"
        case .ADP:
            return "ADP"
        default:
            return "Unknown Store"
        }
    }
    
    public static func removeAppKeychain(dataUUID label: String) {
        [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassCertificate, kSecClassKey, kSecClassIdentity].forEach {
          let status = SecItemDelete([
            kSecClass as String: $0,
            "alis": label,
          ] as CFDictionary)
          if status != errSecSuccess && status != errSecItemNotFound {
              //Error while removing class $0
              NSLog("[LC] Failed to find keychain items: \(status)")
          }
        }
    }
    
    public static func askForJIT(onServerMessage : ((String) -> Void)? ) async -> Bool {
        // if LiveContainer is installed by TrollStore
        let tsPath = "\(Bundle.main.bundlePath)/../_TrollStore"
        if (access((tsPath as NSString).utf8String, 0) == 0) {
            LCUtils.launchToGuestApp()
            return true
        }
        
        guard let groupUserDefaults = UserDefaults(suiteName: appGroupID()),
              let jitEnabler = JITEnablerType(rawValue: groupUserDefaults.integer(forKey: "LCJITEnablerType")) else {
            return false
        }
        
        
        if(jitEnabler == .SideJITServer){
            guard
                  let sideJITServerAddress = groupUserDefaults.string(forKey: "LCSideJITServerAddress"),
                  let deviceUDID = groupUserDefaults.string(forKey: "LCDeviceUDID"),
                  !sideJITServerAddress.isEmpty && !deviceUDID.isEmpty else {
                return false
            }
            
            onServerMessage?("Please make sure the VPN is connected if the server is not in your local network.")
            
            do {
                let launchJITUrlStr = "\(sideJITServerAddress)/\(deviceUDID)/\(Bundle.main.bundleIdentifier ?? "")"
                guard let launchJITUrl = URL(string: launchJITUrlStr) else { return false }
                let session = URLSession.shared
                
                onServerMessage?("Contacting SideJITServer at \(sideJITServerAddress)...")
                let request = URLRequest(url: launchJITUrl)
                let (data, _) = try await session.data(for: request)
                onServerMessage?(String(decoding: data, as: UTF8.self))
                
            } catch {
                onServerMessage?("Failed to contact SideJITServer: \(error)")
            }
            
            return false
        } else if (jitEnabler == .JITStreamerEBLegacy) {
            var JITStresmerEBAddress = groupUserDefaults.string(forKey: "LCSideJITServerAddress") ?? ""
            if JITStresmerEBAddress.isEmpty {
                JITStresmerEBAddress = "http://[fd00::]:9172"
            }
            
            onServerMessage?("Please make sure the VPN is connected if the server is not in your local network.")
            
            do {

                onServerMessage?("Contacting JitStreamer-EB server at \(JITStresmerEBAddress)...")
                
                let session = URLSession.shared
                let decoder = JSONDecoder()
                
                let mountStatusUrlStr = "\(JITStresmerEBAddress)/mount"
                guard let mountStatusUrl = URL(string: mountStatusUrlStr) else { return false }
                let mountRequest = URLRequest(url: mountStatusUrl)
                
                // check mount status
                onServerMessage?("Checking mount status...")
                let (mountData, _) = try await session.data(for: mountRequest)
                let mountResponseObj = try decoder.decode(JITStreamerEBMountResponse.self, from: mountData)
                guard mountResponseObj.ok else {
                    onServerMessage?(mountResponseObj.error ?? "Mounting failed with unknown error.")
                    return false
                }
                if mountResponseObj.mounting {
                    onServerMessage?("Your device is currently mounting the developer disk image. Leave your device on and connected. Once this finishes, you can run JitStreamer again.")
                    onServerMessage?("Check \(JITStresmerEBAddress)/mount_status for mounting status.")
                    if let mountStatusUrl = URL(string: "\(JITStresmerEBAddress)/mount_status") {
                        await UIApplication.shared.open(mountStatusUrl)
                    }
                    return false
                }
                
                // open safari to use /launch_app api
                if let mountStatusUrl = URL(string: "\(JITStresmerEBAddress)/launch_app/\(Bundle.main.bundleIdentifier!)") {
                    onServerMessage?("JIT acquisition will continue in the default browser.")
                    await UIApplication.shared.open(mountStatusUrl)
                }
                return false
                

            } catch {
                onServerMessage?("Failed to contact JitStreamer-EB server: \(error)")
            }
            
        } else if jitEnabler == .StkiJIT || jitEnabler == .StikJITLC {
            let launchURLStr = "stikjit://enable-jit?bundle-id=\(Bundle.main.bundleIdentifier!)"
            let launchURL : URL
            if jitEnabler == .StikJITLC {
                let encodedStr = Data(launchURLStr.utf8).base64EncodedString()
                switch DataManager.shared.model.multiLCStatus {
                case 0:
                    onServerMessage?("Another LiveContainer is not installed. Please choose another method to enable JIT.")
                    return false;
                case 1:
                    launchURL = URL(string: "livecontainer2://open-url?url=\(encodedStr)")!
                    break
                case 2:
                    launchURL = URL(string: "livecontainer://open-url?url=\(encodedStr)")!
                    break
                default:
                    onServerMessage?("Unable to determine multiple LiveContainer status. This should not happen.")
                    return false
                }
                onServerMessage?("JIT acquisition will continue in another LiveContainer.")
                
            } else {
                launchURL = URL(string: launchURLStr)!
                onServerMessage?("JIT acquisition will continue in StikDebug.")
            }
            await UIApplication.shared.open(launchURL)
        } else if jitEnabler == .SideStore {
            onServerMessage?("JIT acquisition will continue in SideStore.")
            let launchURL = URL(string: "sidestore://enable-jit?bundle-id=\(Bundle.main.bundleIdentifier!)")!
            await UIApplication.shared.open(launchURL)
        }
        return false
    }

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

@objc class MultitaskManager : NSObject {
    static private var usingMultitaskContainers : [String] = []
    
    @objc class func registerMultitaskContainer(container: String) {
        usingMultitaskContainers.append(container)
    }
    
    @objc class func unregisterMultitaskContainer(container: String) {
        usingMultitaskContainers.removeAll(where: { c in
            return c == container
        })
    }
    
    @objc class func isUsing(container: String) -> Bool {
        return usingMultitaskContainers.contains { c in
            return c == container
        }
    }
    
    @objc class func isMultitasking() -> Bool {
        return usingMultitaskContainers.count > 0
    }
}
