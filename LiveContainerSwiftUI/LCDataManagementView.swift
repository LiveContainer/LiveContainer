//
//  LCDataManagementView.swift
//  LiveContainer
//
//  Created by s s on 2025/4/18.
//

import SwiftUI

struct LCFolderPath {
    var path : URL
    var desc : String
}

struct LCDataManagementView : View {
    @Binding var appDataFolderNames: [String]
    @State var folderPaths : [LCFolderPath]
    @State var filzaInstalled = false
    @State var appeared = false
    
    @StateObject private var appFolderRemovalAlert = YesNoHelper()
    @State private var folderRemoveCount = 0
    @StateObject private var resetUserDefaultsAlert = YesNoHelper()
    
    @StateObject private var keyChainRemovalAlert = YesNoHelper()
    
    @State var errorShow = false
    @State var errorInfo = ""
    @State var successShow = false
    @State var successInfo = ""
    
    @EnvironmentObject private var sharedModel : SharedModel
    @AppStorage("LCLaunchInMultitaskMode") var launchInMultitaskMode = false
    
    init(appDataFolderNames: Binding<[String]>) {        
        _appDataFolderNames = appDataFolderNames
        
        _folderPaths = State(initialValue: [
            LCFolderPath(path: LCPath.docPath, desc: "Private Container"),
            LCFolderPath(path: LCPath.lcGroupDocPath, desc: "App Group Container"),
            LCFolderPath(path: Bundle.main.bundleURL, desc: "LiveContainer Bundle"),
        ])
    }
    
    var body: some View {
    
        Form {
            Section {
                if sharedModel.multiLCStatus != 2 {
                    Button {
                        moveAppGroupFolderFromPrivateToAppGroup()
                    } label: {
                        Text("lc.settings.appGroupPrivateToShare".loc)
                    }
                    Button {
                        moveAppGroupFolderFromAppGroupToPrivate()
                    } label: {
                        Text("lc.settings.appGroupShareToPrivate".loc)
                    }

                    Button {
                        Task { await moveDanglingFolders() }
                    } label: {
                        Text("lc.settings.moveDanglingFolderOut".loc)
                    }
                    Button(role:.destructive) {
                        Task { await cleanUpUnusedFolders() }
                    } label: {
                        Text("lc.settings.cleanDataFolder".loc)
                    }
                }

                Button(role:.destructive) {
                    Task { await removeKeyChain() }
                } label: {
                    Text("lc.settings.cleanKeychain".loc)
                }

                Button(role:.destructive) {
                    Task { await resetUserDefaults() }
                } label: {
                    Text("Reset NSUserDefaults")
                }
            }
            
            Section {
                Button {
                    Task { await clearIconCache() }
                } label: {
                    Text("lc.settings.clearIconCache".loc)
                }
            }
            
            Section {
                ForEach(folderPaths, id:\.desc) { path in
                    HStack(spacing: 10) {
                        Text(path.desc)
                        Spacer()
                        if filzaInstalled {
                            Button {
                                openInFilza(path: path.path)
                            } label: {
                                Text("Filza")
                            }
                            .buttonStyle(.bordered)
                        }
                        Button {
                            copy(text: path.path.path)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("lc.settings.dataManagement".loc)
        .navigationBarTitleDisplayMode(.inline)
        .alert("lc.common.error".loc, isPresented: $errorShow){
        } message: {
            Text(errorInfo)
        }
        .alert("lc.common.success".loc, isPresented: $successShow){
        } message: {
            Text(successInfo)
        }
        .alert("lc.settings.cleanDataFolder".loc, isPresented: $appFolderRemovalAlert.show) {
            if folderRemoveCount > 0 {
                Button(role: .destructive) {
                    appFolderRemovalAlert.close(result: true)
                } label: {
                    Text("lc.common.delete".loc)
                }
            }

            Button("lc.common.cancel".loc, role: .cancel) {
                appFolderRemovalAlert.close(result: false)
            }
        } message: {
            if folderRemoveCount > 0 {
                Text("lc.settings.cleanDataFolderConfirm %lld".localizeWithFormat(folderRemoveCount))
            } else {
                Text("lc.settings.noDataFolderToClean".loc)
            }

        }
        .alert("lc.settings.cleanKeychain".loc, isPresented: $keyChainRemovalAlert.show) {
            Button(role: .destructive) {
                keyChainRemovalAlert.close(result: true)
            } label: {
                Text("lc.common.delete".loc)
            }

            Button("lc.common.cancel".loc, role: .cancel) {
                keyChainRemovalAlert.close(result: false)
            }
        } message: {
            Text("lc.settings.cleanKeychainDesc".loc)
        }
        .onAppear {
            onAppearFunc()
        }
        .alert("Reset NSUserDefaults", isPresented: $resetUserDefaultsAlert.show) {
            Button(role: .destructive) {
                resetUserDefaultsAlert.close(result: true)
            } label: {
                Text("Reset")
            }
            
            Button("Cancel", role: .cancel) {
                resetUserDefaultsAlert.close(result: false)
            }
        } message: {
            Text("This will completely reset NSUserDefaults to fix issue due to corruption (supports both legacy and new storage systems). LiveContainer will restart with clean preferences. Your app data in Files/LiveContainer is preserved.")
        }
    }
    
    func onAppearFunc() {
        if !appeared {
            for app in sharedModel.apps {
                if app.appInfo.bundleIdentifier() == "com.tigisoftware.Filza" {
                    filzaInstalled = true
                    break
                }
            }
            appeared = true
        }
    }
    
    func cleanUpUnusedFolders() async {
        
        var folderNameToAppDict : [String:LCAppModel] = [:]
        for app in sharedModel.apps {
            for container in app.appInfo.containers {
                folderNameToAppDict[container.folderName] = app;
            }
        }
        for app in sharedModel.hiddenApps {
            for container in app.appInfo.containers {
                folderNameToAppDict[container.folderName] = app;
            }
        }
        
        let fm = FileManager()
        var foldersToDelete: [URL] = []
        var keychainLabelsToEvaluate = Set<String>()
        var seenRootPaths = Set<String>()
        let candidateRoots = [LCPath.dataPath, LCPath.lcGroupDataPath].filter { seenRootPaths.insert($0.path).inserted }

        do {
            for root in candidateRoots where fm.fileExists(atPath: root.path) {
                let entries = try fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                for entry in entries {
                    let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
                    guard values?.isDirectory == true else {
                        continue
                    }
                    let folderName = entry.lastPathComponent
                    if folderNameToAppDict[folderName] == nil {
                        foldersToDelete.append(entry)
                        keychainLabelsToEvaluate.insert(folderName)
                    }
                }
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }

        folderRemoveCount = foldersToDelete.count
        
        guard let result = await appFolderRemovalAlert.open(), result else {
            return
        }

        do {
            for folderURL in foldersToDelete {
                try fm.removeItem(at: folderURL)
            }

            for folderName in keychainLabelsToEvaluate {
                let stillExists = candidateRoots.contains { root in
                    fm.fileExists(atPath: root.appendingPathComponent(folderName).path)
                }
                if stillExists {
                    continue
                }
                LCUtils.removeAppKeychain(dataUUID: folderName)
                self.appDataFolderNames.removeAll(where: { $0 == folderName })
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func removeKeyChain() async {
        guard let result = await keyChainRemovalAlert.open(), result else {
            return
        }

        let failures = LCUtils.removeAllAppKeychain()
        if !failures.isEmpty {
            let uniqueCodes = Array(Set(failures.map { Int($0) })).sorted()
            errorInfo = "Keychain cleanup reported errors: \(uniqueCodes.map(String.init).joined(separator: ", "))"
            errorShow = true
        }
    }
    
    func moveDanglingFolders() async {
        let fm = FileManager()
        do {
            var appDataFoldersInUse : Set<String> = Set();
            var tweakFoldersInUse : Set<String> = Set();
            for app in sharedModel.apps {
                if !app.appInfo.isShared {
                    continue
                }
                for container in app.appInfo.containers {
                    appDataFoldersInUse.update(with: container.folderName);
                }

                
                if let folder = app.appInfo.tweakFolder {
                    tweakFoldersInUse.update(with: folder);
                }

            }
            
            for app in sharedModel.hiddenApps {
                if !app.appInfo.isShared {
                    continue
                }
                for container in app.appInfo.containers {
                    appDataFoldersInUse.update(with: container.folderName);
                }
                if let folder = app.appInfo.tweakFolder {
                    tweakFoldersInUse.update(with: folder);
                }

            }
            
            var movedDataFolderCount = 0
            let sharedDataFolders = try fm.contentsOfDirectory(atPath: LCPath.lcGroupDataPath.path)
            for sharedDataFolder in sharedDataFolders {
                if appDataFoldersInUse.contains(sharedDataFolder) {
                    continue
                }
                try fm.moveItem(at: LCPath.lcGroupDataPath.appendingPathComponent(sharedDataFolder), to: LCPath.dataPath.appendingPathComponent(sharedDataFolder))
                movedDataFolderCount += 1
            }
            
            var movedTweakFolderCount = 0
            let sharedTweakFolders = try fm.contentsOfDirectory(atPath: LCPath.lcGroupTweakPath.path)
            for tweakFolderInUse in sharedTweakFolders {
                if tweakFoldersInUse.contains(tweakFolderInUse) || tweakFolderInUse == "TweakLoader.dylib" {
                    continue
                }
                try fm.moveItem(at: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolderInUse), to: LCPath.tweakPath.appendingPathComponent(tweakFolderInUse))
                movedTweakFolderCount += 1
            }
            successInfo = "lc.settings.moveDanglingFolderComplete %lld %lld".localizeWithFormat(movedDataFolderCount,movedTweakFolderCount)
            successShow = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func moveAppGroupFolderFromAppGroupToPrivate() {
        let fm = FileManager()
        do {
            if !fm.fileExists(atPath: LCPath.appGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.appGroupPath.path, withIntermediateDirectories: true)
            }
            if !fm.fileExists(atPath: LCPath.lcGroupAppGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.lcGroupAppGroupPath.path, withIntermediateDirectories: true)
            }
            
            let privateFolderContents = try fm.contentsOfDirectory(at: LCPath.appGroupPath, includingPropertiesForKeys: nil)
            let sharedFolderContents = try fm.contentsOfDirectory(at: LCPath.lcGroupAppGroupPath, includingPropertiesForKeys: nil)
            if privateFolderContents.count > 0 {
                errorInfo = "lc.settings.appGroupExistPrivate".loc
                errorShow = true
                return
            }
            for file in sharedFolderContents {
                try fm.moveItem(at: file, to: LCPath.appGroupPath.appendingPathComponent(file.lastPathComponent))
            }
            successInfo = "lc.settings.appGroup.moveSuccess".loc
            successShow = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func resetUserDefaults() async {
        guard let doReset = await resetUserDefaultsAlert.open(), doReset else {
            return
        }
        
        do {
            let lcDefaults = UserDefaults.standard
            let bundleId = Bundle.main.bundleIdentifier!
            let fm = FileManager.default
            
            NSLog("[LC] 🧹 Starting NSUserDefaults reset (all 3 implementation systems)")
            
            // SYSTEM 1: Clear new container-based NSUserDefaults storage (newest implementation)
            var clearedContainerPrefs = 0
            
            // Get all container UUIDs from app models
            var allContainerUUIDs: Set<String> = Set()
            for appModel in sharedModel.apps + sharedModel.hiddenApps {
                for container in appModel.appInfo.containers {
                    allContainerUUIDs.insert(container.folderName)
                }
            }
            
            // Also scan filesystem for any additional containers (dangling containers)
            let dataPaths = [LCPath.dataPath, LCPath.lcGroupDataPath]
            for dataPath in dataPaths where fm.fileExists(atPath: dataPath.path) {
                if let containers = try? fm.contentsOfDirectory(atPath: dataPath.path) {
                    allContainerUUIDs.formUnion(containers)
                }
            }
            
            // Clear ONLY NSUserDefaults preferences from each container's Library/Preferences folder
            for containerUUID in allContainerUUIDs {
                let containerPaths = [
                    LCPath.dataPath.appendingPathComponent(containerUUID),
                    LCPath.lcGroupDataPath.appendingPathComponent(containerUUID)
                ]
                
                for containerPath in containerPaths {
                    let preferencesPath = containerPath.appendingPathComponent("Library/Preferences")
                    if fm.fileExists(atPath: preferencesPath.path) {
                        if let prefFiles = try? fm.contentsOfDirectory(at: preferencesPath, includingPropertiesForKeys: nil) {
                            for prefFile in prefFiles where prefFile.pathExtension == "plist" {
                                try? fm.removeItem(at: prefFile)
                                clearedContainerPrefs += 1
                                NSLog("[LC] 🗑️: Removed container preference: \(prefFile.lastPathComponent)")
                            }
                        }
                    }
                }
            }
            
            if clearedContainerPrefs > 0 {
                NSLog("[LC] ✅: Cleared \(clearedContainerPrefs) container-based preferences (new system)")
            }
            
            // SYSTEM 2: Clear 8-pool storage system (middle implementation) - UNCHANGED
            var clearedStoragePools = 0
            for i in 0..<8 {
                let suiteName = "com.kdt.livecontainer.userDefaultsStorage.\(i)"
                if let poolDefaults = UserDefaults(suiteName: suiteName) {
                    let poolData = poolDefaults.dictionaryRepresentation()
                    if !poolData.isEmpty {
                        NSLog("[LC] 📦: Clearing userDefaultsStorage[\(i)] with \(poolData.count) container entries")
                        
                        for key in poolData.keys {
                            poolDefaults.removeObject(forKey: key)
                        }
                        poolDefaults.removePersistentDomain(forName: suiteName)
                        poolDefaults.synchronize()
                        clearedStoragePools += 1
                    }
                }
            }
            
            if clearedStoragePools > 0 {
                NSLog("[LC] ✅: Cleared \(clearedStoragePools) new storage pools")
            } else {
                NSLog("[LC] 📝 No new storage pools found - using legacy behavior")
            }
            
            // SYSTEM 3: Clear legacy NSUserDefaults system (original implementation) - UNCHANGED
            let allCurrentKeys = Array(lcDefaults.dictionaryRepresentation().keys)
            NSLog("[LC] 🗂️: Clearing legacy NSUserDefaults with \(allCurrentKeys.count) keys")
            
            for key in allCurrentKeys {
                lcDefaults.removeObject(forKey: key)
                NSLog("[LC]: Removed key: \(key)")
            }
            
            // Step 3: Remove persistent domains (both legacy and new) - UNCHANGED
            lcDefaults.removePersistentDomain(forName: bundleId)
            
            // Also remove new storage domains if they exist
            for i in 0..<8 {
                let suiteName = "com.kdt.livecontainer.userDefaultsStorage.\(i)"
                if let poolDefaults = UserDefaults(suiteName: suiteName) {
                    poolDefaults.removePersistentDomain(forName: suiteName)
                }
            }
            
            lcDefaults.synchronize()
            
            // Step 4: Enhanced physical file cleanup (covers all systems) - ENHANCED
            let libraryPath = fm.urls(for: .libraryDirectory, in: .userDomainMask).first!
            let preferencesPath = libraryPath.appendingPathComponent("Preferences")
            
            var deletedFiles = 0
            var totalDeletedSize = 0
            
            if fm.fileExists(atPath: preferencesPath.path) {
                let contents = try fm.contentsOfDirectory(at: preferencesPath, 
                                                        includingPropertiesForKeys: [.fileSizeKey])
                
                for file in contents {
                    let fileName = file.lastPathComponent
                    
                    // pattern matching for ALL LiveContainer preference files
                    let shouldDelete = fileName.contains(bundleId) || 
                                    fileName.contains("LiveContainer") ||
                                    fileName.contains("livecontainer") ||  // Case insensitive
                                    fileName.contains("userDefaultsStorage") ||
                                    fileName.hasPrefix("com.kdt.livecontainer") ||
                                    fileName.matches(pattern: "com\\.kdt\\.livecontainer.*\\.plist") ||
                                    fileName.matches(pattern: ".*userDefaultsStorage.*\\.plist") ||
                                    fileName.matches(pattern: ".*livecontainer.*\\.plist")
                    
                    if shouldDelete {
                        // Get file size before deletion
                        if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            totalDeletedSize += fileSize
                        }
                        
                        try fm.removeItem(at: file)
                        deletedFiles += 1
                        NSLog("[LC] 🗑️: Removed preference file: \(fileName)")
                    }
                }
            }
            
            // Clear any shared preference domains that might exist
            let sharedDomains = [
                "com.kdt.livecontainer.shared",
                "group.com.kdt.livecontainer",
                bundleId + ".shared"
            ]
            
            var clearedSharedDomains = 0
            for domain in sharedDomains {
                if let sharedDefaults = UserDefaults(suiteName: domain) {
                    let sharedKeys = Array(sharedDefaults.dictionaryRepresentation().keys)
                    if !sharedKeys.isEmpty {
                        for key in sharedKeys {
                            sharedDefaults.removeObject(forKey: key)
                        }
                        sharedDefaults.removePersistentDomain(forName: domain)
                        sharedDefaults.synchronize()
                        clearedSharedDomains += 1
                        NSLog("[LC] 🧹: Cleared shared domain: \(domain) (\(sharedKeys.count) keys)")
                    }
                }
            }
            
            // Clear CFPreferences cache (force system reload)
            // if let cfPrefsClass = NSClassFromString("_CFXPreferences") {
            //     let resetMethod = NSSelectorFromString("resetPreferences")
            //     if cfPrefsClass.responds(to: resetMethod) {
            //         // Use objc_msgSend to call the class method
            //         let objc_msgSend = unsafeBitCast(dlsym(dlopen(nil, RTLD_LAZY), "objc_msgSend"), to: (@convention(c) (AnyClass, Selector) -> Void).self)
            //         objc_msgSend(cfPrefsClass, resetMethod)
            //         NSLog("[LC] 🔄 Cleared CFPreferences cache")
            //     }
            // }
            
            let systemsDetected = [
                clearedContainerPrefs > 0 ? "container-based" : nil,
                clearedStoragePools > 0 ? "8-pool" : nil,
                allCurrentKeys.count > 0 ? "legacy" : nil
            ].compactMap { $0 }
            
            NSLog("[LC] 📊 RESET COMPLETE:")
            NSLog("[LC] - Container preferences: \(clearedContainerPrefs)")
            NSLog("[LC] - Storage pools: \(clearedStoragePools)")  
            NSLog("[LC] - Legacy keys: \(allCurrentKeys.count)")
            NSLog("[LC] - Preference files: \(deletedFiles) (\(totalDeletedSize / 1024)KB)")
            NSLog("[LC] - Shared domains: \(clearedSharedDomains)")
            NSLog("[LC] - Systems detected: \(systemsDetected.joined(separator: ", "))")
            
            // Immediate restart to prevent any re-corruption
            DispatchQueue.main.async {
                NSLog("[LC] 🔄 NSUserDefaults reset complete - forcing immediate restart")
                exit(0)
            }
            
            let detectedSystems = systemsDetected.isEmpty ? "legacy" : systemsDetected.joined(separator: " + ")
            let totalCleared = clearedContainerPrefs + clearedStoragePools + allCurrentKeys.count
            
            successInfo = "NSUserDefaults reset complete (\(detectedSystems) systems). Cleared \(totalCleared) preference entries, \(deletedFiles) files (\(totalDeletedSize / 1024)KB), and \(clearedSharedDomains) shared domains. LiveContainer will restart immediately. Your app data in Files/LiveContainer is preserved."
            successShow = true
            
        } catch {
            errorInfo = "Failed to perform NSUserDefaults reset: \(error.localizedDescription)"
            errorShow = true
        }
    }
    
    func moveAppGroupFolderFromPrivateToAppGroup() {
        let fm = FileManager()
        do {
            if !fm.fileExists(atPath: LCPath.appGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.appGroupPath.path, withIntermediateDirectories: true)
            }
            if !fm.fileExists(atPath: LCPath.lcGroupAppGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.lcGroupAppGroupPath.path, withIntermediateDirectories: true)
            }
            
            let privateFolderContents = try fm.contentsOfDirectory(at: LCPath.appGroupPath, includingPropertiesForKeys: nil)
            let sharedFolderContents = try fm.contentsOfDirectory(at: LCPath.lcGroupAppGroupPath, includingPropertiesForKeys: nil)
            if sharedFolderContents.count > 0 {
                errorInfo = "lc.settings.appGroupExist Shared".loc
                errorShow = true
                return
            }
            for file in privateFolderContents {
                try fm.moveItem(at: file, to: LCPath.lcGroupAppGroupPath.appendingPathComponent(file.lastPathComponent))
            }
            successInfo = "lc.settings.appGroup.moveSuccess".loc
            successShow = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func copy(text: String) {
        UIPasteboard.general.string = text
    }
    
    func openInFilza(path: URL) {
        let launchURLStr = "filza://view\(path.path)/."
        UserDefaults.standard.setValue(launchURLStr, forKey: "launchAppUrlScheme")
        Task {
            do {
                try await sharedModel.apps.first(where: { app in
                    return app.appInfo.bundleIdentifier() == "com.tigisoftware.Filza"
                })?.runApp(multitask: launchInMultitaskMode)
            } catch {
                successInfo = error.localizedDescription
                successShow = true
            }
        }
    }
    
    func clearIconCache() async {
        for app in sharedModel.apps {
            app.appInfo.clearIconCache()
        }
    }
}

extension String {
    func matches(pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: self.count)
            return regex.firstMatch(in: self, range: range) != nil
        } catch {
            return false
        }
    }
}
