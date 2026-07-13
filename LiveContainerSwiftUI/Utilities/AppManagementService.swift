import Foundation

enum AppManagementError: LocalizedError {
    case appNotFound
    case cancelled
    case conflict
    case invalidIPA
    case bundleIdentifierMismatch

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return "App not found."
        case .cancelled:
            return "Installation cancelled."
        case .conflict:
            return "An app with this bundle identifier is already installed."
        case .invalidIPA:
            return "The uploaded file is not a valid IPA."
        case .bundleIdentifierMismatch:
            return "The uploaded IPA bundle identifier does not match the app being updated."
        }
    }
}

struct AppInstallDecision {
    let relativeBundlePath: String
    let appToReplace: LCAppModel?
}

enum AppInstallStage: String {
    case extracting
    case signing
    case installing
}

@MainActor
final class AppManagementService {
    static let shared = AppManagementService()

    static let pendingRemoteUpdateKey = "LCPendingRemoteUpdate"

    var installedApps: [LCAppModel] {
        DataManager.shared.model.apps + DataManager.shared.model.hiddenApps
    }

    func app(bundleIdentifier: String) -> LCAppModel? {
        installedApps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    @discardableResult
    func reloadInstalledApps() -> Set<String> {
        var apps: [LCAppModel] = []
        var hiddenApps: [LCAppModel] = []
        var schemes: Set<String> = []
        var roots = [(LCPath.bundlePath, false)]
        if LCPath.lcGroupDocPath != LCPath.docPath {
            roots.append((LCPath.lcGroupBundlePath, true))
        }
        for (root, isShared) in roots {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for appDirectory in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] where appDirectory.hasSuffix(".app") {
                guard let info = LCAppInfo(bundlePath: root.appendingPathComponent(appDirectory).path) else {
                    continue
                }
                info.relativeBundlePath = appDirectory
                info.isShared = isShared
                let model = LCAppModel(appInfo: info)
                if info.isHidden {
                    hiddenApps.append(model)
                } else {
                    apps.append(model)
                    schemes.formUnion((info.urlSchemes() as? [String]) ?? [])
                }
            }
        }
        DataManager.shared.model.apps = apps
        DataManager.shared.model.hiddenApps = hiddenApps
        return schemes
    }

    func installIPA(
        at ipaURL: URL,
        replacingBundleIdentifier: String? = nil,
        restartRunningApp: Bool = false,
        remoteJobID: String? = nil,
        delegate: LCAppModelDelegate? = nil,
        resolveConflict: (([LCAppModel], String) async -> AppInstallDecision?)? = nil,
        progress: @escaping (AppInstallStage, Int) -> Void = { _, _ in }
    ) async throws -> LCAppModel {
        guard ["ipa", "tipa"].contains(ipaURL.pathExtension.lowercased()) else {
            throw AppManagementError.invalidIPA
        }

        let fm = FileManager.default
        let workDirectory = fm.temporaryDirectory.appendingPathComponent("LCInstall-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDirectory) }

        let extractProgress = Progress(totalUnitCount: 100)
        let observer = extractProgress.observe(\.fractionCompleted) { value, _ in
            progress(.extracting, Int(value.fractionCompleted * 80))
        }
        defer { observer.invalidate() }

        progress(.extracting, 0)
        let extractResult = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: extract(ipaURL.path, workDirectory.path, extractProgress))
            }
        }
        guard extractResult == 0 else {
            throw AppManagementError.invalidIPA
        }

        let payloadURL = workDirectory.appendingPathComponent("Payload", isDirectory: true)
        guard let appName = try fm.contentsOfDirectory(atPath: payloadURL.path).first(where: { $0.hasSuffix(".app") }) else {
            throw AppManagementError.invalidIPA
        }
        let extractedAppURL = payloadURL.appendingPathComponent(appName)
        guard let newAppInfo = LCAppInfo(bundlePath: extractedAppURL.path), let bundleIdentifier = newAppInfo.bundleIdentifier() else {
            throw AppManagementError.invalidIPA
        }

        let matchingApps = installedApps.filter { $0.bundleIdentifier == bundleIdentifier }
        var decision: AppInstallDecision
        if let replacingBundleIdentifier {
            guard replacingBundleIdentifier == bundleIdentifier else {
                throw AppManagementError.bundleIdentifierMismatch
            }
            guard let appToReplace = app(bundleIdentifier: replacingBundleIdentifier) else {
                throw AppManagementError.appNotFound
            }
            decision = AppInstallDecision(relativeBundlePath: appToReplace.appInfo.relativeBundlePath, appToReplace: appToReplace)
        } else if matchingApps.isEmpty {
            let relativePath = "\(bundleIdentifier.sanitizeNonACSII()).app"
            if fm.fileExists(atPath: LCPath.bundlePath.appendingPathComponent(relativePath).path) {
                let suggestedPath = "\(bundleIdentifier)_\(Int(CFAbsoluteTimeGetCurrent())).app"
                guard let resolveConflict else {
                    throw AppManagementError.conflict
                }
                guard let resolved = await resolveConflict([], suggestedPath) else {
                    throw AppManagementError.cancelled
                }
                decision = resolved
            } else {
                decision = AppInstallDecision(relativeBundlePath: relativePath, appToReplace: nil)
            }
        } else {
            guard let resolveConflict else {
                throw AppManagementError.conflict
            }
            guard let resolved = await resolveConflict(matchingApps, "\(bundleIdentifier)_\(Int(CFAbsoluteTimeGetCurrent())).app") else {
                throw AppManagementError.cancelled
            }
            decision = resolved
        }

        let outputRoot = decision.appToReplace?.uiIsShared == true ? LCPath.lcGroupBundlePath : LCPath.bundlePath
        let outputURL = outputRoot.appendingPathComponent(decision.relativeBundlePath)
        var runningInstances: [(container: String, scheme: String?)] = []
        if restartRunningApp, let appToReplace = decision.appToReplace {
            for container in appToReplace.appInfo.containers {
                if MultitaskManager.isUsing(container: container.folderName) {
                    runningInstances.append((container.folderName, nil))
                    await MultitaskManager.terminate(container: container.folderName)
                } else if var scheme = LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName) {
                    if scheme.hasSuffix(".liveprocess") {
                        scheme = (scheme as NSString).deletingPathExtension
                    }
                    runningInstances.append((container.folderName, scheme))
                    if scheme == UserDefaults.lcAppUrlScheme(), UserDefaults.lcGuestAppId() != nil, let remoteJobID {
                        let stagedURL = LCPath.docPath.appendingPathComponent("RemoteAPI-" + remoteJobID + ".ipa")
                        try? fm.removeItem(at: stagedURL)
                        try fm.copyItem(at: ipaURL, to: stagedURL)
                        let defaults = UserDefaults.lc() ?? .standard
                        defaults.set([
                            "job": remoteJobID,
                            "bundleID": appToReplace.bundleIdentifier,
                            "container": container.folderName,
                            "ipaPath": stagedURL.path
                        ], forKey: Self.pendingRemoteUpdateKey)
                        defaults.set("ui", forKey: "selected")
                        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
                            LCSharedUtils.launchToGuestApp()
                        }
                    }
                    var components = URLComponents()
                    components.scheme = scheme
                    components.host = "livecontainer-launch"
                    components.queryItems = [URLQueryItem(name: "bundle-name", value: "ui")]
                    if let url = components.url {
                        await UIApplication.shared.open(url)
                    }
                    for _ in 0..<100 {
                        if LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName) == nil {
                            break
                        }
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    guard LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName) == nil else {
                        throw "The running app did not stop in time."
                    }
                }
            }
        }
        if decision.appToReplace != nil {
            try fm.removeItem(at: outputURL)
        }
        progress(.installing, 80)
        try fm.moveItem(at: extractedAppURL, to: outputURL)

        guard let installedInfo = LCAppInfo(bundlePath: outputURL.path) else {
            throw AppManagementError.invalidIPA
        }
        installedInfo.relativeBundlePath = decision.relativeBundlePath

        var signError: String?
        var signObserver: NSKeyValueObservation?
        progress(.signing, 81)
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            if decision.appToReplace?.uiDontSign == true || LCUtils.appGroupUserDefault.bool(forKey: "LCDontSignApp") {
                installedInfo.dontSign = true
            }
            installedInfo.patchExecAndSignIfNeed(completionHandler: { _, error in
                signError = error
                continuation.resume()
            }, progressHandler: { signProgress in
                guard let signProgress else { return }
                signObserver = signProgress.observe(\.fractionCompleted) { value, _ in
                    progress(.signing, 80 + Int(value.fractionCompleted * 19))
                }
            }, forceSign: false)
        }
        signObserver?.invalidate()

        if let oldApp = decision.appToReplace {
            installedInfo.autoSaveDisabled = true
            installedInfo.isLocked = oldApp.appInfo.isLocked
            installedInfo.isHidden = oldApp.appInfo.isHidden
            installedInfo.isJITNeeded = oldApp.appInfo.isJITNeeded
            installedInfo.isShared = oldApp.appInfo.isShared
            installedInfo.spoofSDKVersion = oldApp.appInfo.spoofSDKVersion
            installedInfo.doSymlinkInbox = oldApp.appInfo.doSymlinkInbox
            installedInfo.containerInfo = oldApp.appInfo.containerInfo
            installedInfo.tweakFolder = oldApp.appInfo.tweakFolder
            installedInfo.selectedLanguage = oldApp.appInfo.selectedLanguage
            installedInfo.dataUUID = oldApp.appInfo.dataUUID
            installedInfo.orientationLock = oldApp.appInfo.orientationLock
            installedInfo.dontInjectTweakLoader = oldApp.appInfo.dontInjectTweakLoader
            installedInfo.hideLiveContainer = oldApp.appInfo.hideLiveContainer
            installedInfo.dontLoadTweakLoader = oldApp.appInfo.dontLoadTweakLoader
            installedInfo.doUseLCBundleId = oldApp.appInfo.doUseLCBundleId
            installedInfo.fixFilePickerNew = oldApp.appInfo.fixFilePickerNew
            installedInfo.fixLocalNotification = oldApp.appInfo.fixLocalNotification
            installedInfo.lastLaunched = oldApp.appInfo.lastLaunched
            installedInfo.jitLaunchScriptJs = oldApp.appInfo.jitLaunchScriptJs
            installedInfo.multitaskSpecified = oldApp.appInfo.multitaskSpecified
            installedInfo.autoSaveDisabled = false
            installedInfo.save()
        } else {
            installedInfo.spoofSDKVersion = true
        }
        installedInfo.installationDate = Date.now

        let model = LCAppModel(appInfo: installedInfo, delegate: delegate ?? decision.appToReplace?.delegate)
        if let oldApp = decision.appToReplace {
            if oldApp.uiIsHidden {
                DataManager.shared.model.hiddenApps.removeAll { $0 == oldApp }
                DataManager.shared.model.hiddenApps.append(model)
            } else {
                DataManager.shared.model.apps.removeAll { $0 == oldApp }
                DataManager.shared.model.apps.append(model)
            }
        } else {
            DataManager.shared.model.apps.append(model)
            if let schemes = installedInfo.urlSchemes() as? [String] {
                UserDefaults.lcShared().mutableArrayValue(forKey: "LCGuestURLSchemes").addObjects(from: schemes)
            }
        }
        progress(.installing, 100)

        if let signError {
            throw signError
        }

        for instance in runningInstances {
            if let scheme = instance.scheme {
                var components = URLComponents()
                components.scheme = scheme
                components.host = "livecontainer-launch"
                components.queryItems = [
                    URLQueryItem(name: "bundle-name", value: model.appInfo.relativeBundlePath),
                    URLQueryItem(name: "container-folder-name", value: instance.container)
                ]
                if let url = components.url {
                    await UIApplication.shared.open(url)
                }
            } else {
                try await model.runApp(multitask: true, containerFolderName: instance.container)
            }
        }

        return model
    }

    func removeApp(bundleIdentifier: String, removeData: Bool = false) throws {
        guard let app = app(bundleIdentifier: bundleIdentifier) else {
            throw AppManagementError.appNotFound
        }
        let fm = FileManager.default
        guard let bundlePath = app.appInfo.bundlePath() else {
            throw AppManagementError.appNotFound
        }
        try fm.removeItem(atPath: bundlePath)
        DataManager.shared.model.apps.removeAll { $0 == app }
        DataManager.shared.model.hiddenApps.removeAll { $0 == app }

        if let schemes = app.appInfo.urlSchemes() as? [String] {
            UserDefaults.lcShared().mutableArrayValue(forKey: "LCGuestURLSchemes").removeObjects(in: schemes)
        }
        if removeData {
            for container in app.appInfo.containers {
                let dataURL = LCPath.dataPath.appendingPathComponent(container.folderName)
                try fm.removeItem(at: dataURL)
                LCUtils.removeAppKeychain(dataUUID: container.folderName)
            }
        }
    }
}
