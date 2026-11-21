//
//  LCAppInstaller.swift
//  LiveContainerSwiftUI
//  Summary (EN): IPA install / uninstall helpers used by the REST layer.
//
//  Extracted from LCAppListView.installIpaFile / LCAppBannerViewController.uninstall,
//  keeping the UI-independent parts reusable by the remote API. Same behaviour as the originals:
//  unzip -> locate .app -> move into LCPath.bundlePath -> patchExecAndSignIfNeed -> add to sharedModel.
//

import Foundation

enum LCAppInstallerError: LocalizedError {
    case decompressFailed
    case noAppBundle
    case cannotReadInfo
    case moveFailed(String)
    case signFailed(String)

    var errorDescription: String? {
        switch self {
        case .decompressFailed: return "IPA extraction failed (not a valid zip, or out of disk space)"
        case .noAppBundle: return "no .app found inside Payload"
        case .cannotReadInfo: return "cannot read the .app Info.plist"
        case .moveFailed(let m): return "failed to move into Applications: \(m)"
        case .signFailed(let m): return "signing failed: \(m)"
        }
    }
}

@MainActor
enum LCAppInstaller {

    /// Installs an IPA. With replaceExisting=false, the same bundleId is kept side by side in a timestamped directory.
    static func install(ipa: URL,
                        replaceExisting: Bool = true,
                        progressHandler: ((Double) -> Void)? = nil) async throws -> LCAppInfo {
        let fm = FileManager.default
        let tmpRoot = fm.temporaryDirectory
        let payloadPath = tmpRoot.appendingPathComponent("Payload")
        if fm.fileExists(atPath: payloadPath.path) {
            try? fm.removeItem(at: payloadPath)
        }

        let progress = Progress.discreteProgress(totalUnitCount: 100)
        let rc: Int32 = await withCheckedContinuation { (c: CheckedContinuation<Int32, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                c.resume(returning: extract(ipa.path, tmpRoot.path, progress))
            }
        }
        guard rc == 0 else { throw LCAppInstallerError.decompressFailed }

        let payloadContents = (try? fm.contentsOfDirectory(atPath: payloadPath.path)) ?? []
        guard let bundleName = payloadContents.first(where: { $0.hasSuffix(".app") }) else {
            throw LCAppInstallerError.noAppBundle
        }
        let srcBundle = payloadPath.appendingPathComponent(bundleName)

        guard let newInfo = LCAppInfo(bundlePath: srcBundle.path),
              let bundleId = newInfo.bundleIdentifier() else {
            throw LCAppInstallerError.cannotReadInfo
        }

        let safeName = bundleId.sanitizeNonACSII()
        var relativePath = "\(safeName).app"
        var dest = LCPath.bundlePath.appendingPathComponent(relativePath)
        try? fm.createDirectory(at: LCPath.bundlePath, withIntermediateDirectories: true)

        if fm.fileExists(atPath: dest.path) {
            if replaceExisting {
                try? fm.removeItem(at: dest)
            } else {
                relativePath = "\(safeName)_\(Int(CFAbsoluteTimeGetCurrent())).app"
                dest = LCPath.bundlePath.appendingPathComponent(relativePath)
            }
        }

        do {
            try fm.moveItem(at: srcBundle, to: dest)
        } catch {
            throw LCAppInstallerError.moveFailed(error.localizedDescription)
        }
        try? fm.removeItem(at: payloadPath)

        guard let finalNewApp = LCAppInfo(bundlePath: dest.path) else {
            throw LCAppInstallerError.cannotReadInfo
        }
        finalNewApp.relativeBundlePath = relativePath
        finalNewApp.spoofSDKVersion = true
        finalNewApp.installationDate = Date.now

        // Sign with ZSign, same as the UI flow; on failure keep the app anyway (as tolerant as the original implementation)
        let signResult: (Bool, String?) = await withCheckedContinuation { c in
            finalNewApp.patchExecAndSignIfNeed(completionHandler: { success, error in
                c.resume(returning: (success, error))
            }, progressHandler: { _ in }, forceSign: false)
        }
        if !signResult.0 {
            LCRemoteLogStore.shared.append("install \(bundleId): sign failed: \(signResult.1 ?? "unknown")",
                                           src: "api")
        }

        // Drop the previous model with the same bundleId first so the list does not show two copies
        DataManager.shared.model.apps.removeAll { $0.appInfo.bundleIdentifier() == bundleId }
        DataManager.shared.model.hiddenApps.removeAll { $0.appInfo.bundleIdentifier() == bundleId }
        let model = LCAppModel(appInfo: finalNewApp)
        DataManager.shared.model.apps.append(model)

        LCRemoteLogStore.shared.append("installed \(bundleId) -> \(relativePath)", src: "api")
        progressHandler?(1.0)
        return finalNewApp
    }

    /// Uninstall: remove the bundle, optionally its data container and keychain items.
    @discardableResult
    static func uninstall(bundleId: String, removeData: Bool) throws -> [String: Any] {
        let fm = FileManager.default
        let model = (DataManager.shared.model.apps + DataManager.shared.model.hiddenApps)
            .first { $0.appInfo.bundleIdentifier() == bundleId }
        guard let appInfo = model?.appInfo, let bundlePath = appInfo.bundlePath() else {
            throw NSError(domain: "LCRemote", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "app not found: \(bundleId)"])
        }
        let containers = appInfo.containers
        try fm.removeItem(atPath: bundlePath)
        DataManager.shared.model.apps.removeAll { $0.appInfo.bundleIdentifier() == bundleId }
        DataManager.shared.model.hiddenApps.removeAll { $0.appInfo.bundleIdentifier() == bundleId }

        var removedData: [String] = []
        if removeData {
            for container in containers {
                let folder = container.folderName
                guard !folder.isEmpty else { continue }
                try? fm.removeItem(at: container.containerURL)
                LCUtils.removeAppKeychain(dataUUID: folder)
                DataManager.shared.model.appDataFolderNames.removeAll { $0 == folder }
                removedData.append(folder)
            }
        }
        LCRemoteLogStore.shared.append("uninstalled \(bundleId) (data=\(removeData), containers=\(removedData.count))",
                                       src: "api")
        return ["bundleId": bundleId, "removedDataFolders": removedData]
    }

    /// For listings: short summary of one app
    @MainActor
    static func summary(of model: LCAppModel) -> [String: Any] {
        let info = model.appInfo
        var d: [String: Any] = [
            "bundleId": info.bundleIdentifier() ?? "",
            "name": info.displayName() ?? "",
            "version": info.version() ?? "",
            "relativePath": info.relativeBundlePath ?? "",
            "path": info.bundlePath() ?? "",
            "isHidden": info.isHidden,
            "isShared": info.isShared,
            "containers": info.containers.map { ["folderName": $0.folderName, "name": $0.name] },
            "isAppRunning": model.isAppRunning
        ]
        if let last = info.lastLaunched {
            d["lastLaunched"] = ISO8601DateFormatter().string(from: last as Date)
        }
        if let inst = info.installationDate {
            d["installationDate"] = ISO8601DateFormatter().string(from: inst as Date)
        }
        return d
    }
}
