//
//  LCUtilsExtensions.swift
//  LiveContainer
//
//  Created by s s on 2026/3/20.
//

import LocalAuthentication

extension LCUtils {
    public static let appGroupUserDefault = UserDefaults.init(suiteName: LCSharedUtils.appGroupID()) ?? UserDefaults.standard
    
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
        guard LCSharedUtils.certificatePassword() != nil else {
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
    
    public static func forEachInstalledLC(isFree: Bool, block: (String, inout Bool) -> Void) {
        for scheme in LCSharedUtils.lcUrlSchemes() {
            if scheme == UserDefaults.lcAppUrlScheme() {
                continue
            }
            
            // Check if the app is installed
            guard let url = URL(string: "\(scheme)://"),
                  UIApplication.shared.canOpenURL(url) else {
                continue
            }
            
            // Check shared utility logic
            if isFree && LCSharedUtils.isLCScheme(inUse: scheme) {
                continue
            }
            
            var shouldBreak = false
            block(scheme, &shouldBreak)
            
            if shouldBreak {
                break
            }
        }
    }
    
    public static func askForJIT(withScript script: String? = nil, onServerMessage: ((String) -> Void)? = nil) async -> Bool {
        // if LiveContainer is installed by TrollStore
        let tsPath = "\(Bundle.main.bundlePath)/../_TrollStore"
        if (access((tsPath as NSString).utf8String, 0) == 0) {
            LCSharedUtils.launchToGuestApp()
            return true
        }
        
        guard let groupUserDefaults = UserDefaults(suiteName: LCSharedUtils.appGroupID()),
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
            var launchURLStr = "stikjit://enable-jit?bundle-id=\(Bundle.main.bundleIdentifier!)"

            if let script = script, !script.isEmpty {
                launchURLStr += "&script-data=\(script)"
            }
            let launchURL : URL
            if jitEnabler == .StikJITLC {
                let encodedStr = Data(launchURLStr.utf8).base64EncodedString()


                var appToLaunch: LCAppModel? = nil
                // find an app that can respond to stikjit://
                appLoop:
                for app in DataManager.shared.model.apps {
                    if let schemes = app.appInfo.urlSchemes() {
                        for scheme in schemes {
                            if let scheme = scheme as? String, scheme == "stikjit" {
                                appToLaunch = app
                                break appLoop
                            }
                        }
                    }
                }
                guard let appToLaunch else {
                    onServerMessage?("StikDebug is not installed in LiveContainer.")
                    return false
                }
                
                if !appToLaunch.uiIsShared {
                    onServerMessage?("StikDebug is installed in LiveContainer, but is not a shared app. Convert it to a shared app to continue.")
                    return false
                }
                // check if stikdebug is already running
                var freeScheme = LCSharedUtils.getContainerUsingLCScheme(withFolderName: appToLaunch.uiDefaultDataFolder)
                
                if(freeScheme == nil) {
                    // if not, try to find a free lc
                    forEachInstalledLC(isFree: true) { scheme, shouldBreak in
                        freeScheme = scheme
                        shouldBreak = true
                    }
                }
                guard let freeScheme else {
                    onServerMessage?("No free LiveContainer is available. Please either: \n(1)close one, \n(2)install a new one, \n(3)choose another method to enable JIT.")
                    return false
                }
                
                launchURL = URL(string: "\(freeScheme)://open-url?url=\(encodedStr)")!
                
                LCUtils.appGroupUserDefault.set(appToLaunch.appInfo.relativeBundlePath, forKey: "LCLaunchExtensionBundleID")
                LCUtils.appGroupUserDefault.set(Date.now, forKey: "LCLaunchExtensionLaunchDate")
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

    
    static func openSideStore(delegate: LCAppModelDelegate? = nil) {
        let sideStoreApp = LCAppModel(appInfo: LCAppInfo(bundlePath: Bundle.main.bundleURL.appendingPathComponent("Frameworks/SideStoreApp.framework").path), delegate: delegate)
        
        Task {
            try await sideStoreApp.runApp(bundleIdOverride: "builtinSideStore")
        }
    }
}
