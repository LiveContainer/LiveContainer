//
//  LCGuestAppCatalog.swift
//  LiveContainerSwiftUI
//
//  Supplies the guest apps that back the App Shortcut's app parameter, and
//  tells the system when that set changes.
//
//  The App Shortcut's intent has to live in this framework, because iOS
//  instantiates it in the app process rather than in an extension. That means
//  the query runs here too and can read the live app list directly.
//

import AppIntents
import Combine
import Foundation
import UIKit

final class LCGuestAppCatalog {
    static let shared = LCGuestAppCatalog()

    /// Set this in the shared defaults to keep guest apps out of Spotlight and Siri.
    static let disableKey = "LCDisableAppShortcuts"

    private var cancellables = Set<AnyCancellable>()

    /// Watches the app list the same way `LCAppSortManager` does, so every
    /// install, delete and visibility change re-indexes without a call at each
    /// mutation site.
    private init() {
        DataManager.shared.model.$apps
            .sink { _ in Self.refreshShortcutParameters() }
            .store(in: &cancellables)
    }

    /// Touching the singleton starts the observation; the initial `@Published`
    /// value also refreshes once at launch, covering apps that changed while
    /// LiveContainer was not running.
    func start() {}

    /// Tells the system the parameter values may have changed. Without this iOS
    /// never enumerates the entities, so the App Shortcut is indexed with an
    /// empty value set and nothing matches in Spotlight.
    static func refreshShortcutParameters() {
        guard !LCUtils.appGroupUserDefault.bool(forKey: disableKey) else { return }
        if #available(iOS 17.0, *) {
            LCAppShortcuts.updateAppShortcutParameters()
        }
    }

    // MARK: - Reading the app list

    /// Hidden apps are never listed. `sharedModel.apps` already excludes them,
    /// and `hiddenApps` is deliberately not consulted, so a hidden app cannot
    /// leak into a system-wide index.
    @available(iOS 17.0, *)
    @MainActor
    static func entities() -> [LCGuestApp] {
        guard !LCUtils.appGroupUserDefault.bool(forKey: disableKey) else { return [] }

        let models = DataManager.shared.model.apps
        var out: [LCGuestApp] = []
        out.reserveCapacity(models.count)

        for model in models {
            let info = model.appInfo
            guard let bundleFolderName = info.relativeBundlePath, !bundleFolderName.isEmpty else { continue }
            let displayName = info.displayName() ?? bundleFolderName
            let bundleIdentifier = info.bundleIdentifier()
            let icon = iconURL(for: model)

            func entity(_ container: LCContainer?) -> LCGuestApp {
                LCGuestApp(displayName: displayName,
                           containerName: container?.name,
                           bundleFolderName: bundleFolderName,
                           containerFolderName: container?.folderName,
                           searchTerms: searchTerms(displayName: displayName,
                                                    bundleIdentifier: bundleIdentifier,
                                                    containerName: container?.name),
                           iconURL: icon)
            }

            out.append(entity(nil))
            // Multi-container apps get one extra row per container, so someone
            // running two accounts of the same app can reach either directly.
            guard model.uiContainers.count > 1 else { continue }
            out.append(contentsOf: model.uiContainers.map(entity))
        }
        return out
    }

    /// Builds only the requested entities, so resolving the parameter before a
    /// launch does not rebuild the whole catalog.
    @available(iOS 17.0, *)
    @MainActor
    static func entities(withIDs ids: Set<String>) -> [LCGuestApp] {
        guard !ids.isEmpty else { return [] }
        let wantedBundles = Set(ids.map { $0.split(separator: "|", maxSplits: 1)[0] })
        return entities(matchingBundleFolderNames: wantedBundles).filter { ids.contains($0.id) }
    }

    @available(iOS 17.0, *)
    @MainActor
    private static func entities(matchingBundleFolderNames wanted: Set<Substring>) -> [LCGuestApp] {
        entities().filter { wanted.contains(Substring($0.bundleFolderName)) }
    }

    // MARK: - Icons

    /// `DisplayRepresentation.Image` wants a URL, so icons are rendered to the
    /// caches directory once and reused.
    @MainActor
    private static func iconURL(for model: LCAppModel) -> URL? {
        guard let bundleFolderName = model.appInfo.relativeBundlePath else { return nil }
        let url = iconDirectory.appendingPathComponent("\(sanitize(bundleFolderName)).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        guard let icon = model.appInfo.iconIsDarkIcon(false),
              let data = resized(icon, to: 180)?.pngData() else { return nil }
        do {
            try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[LC] could not cache app shortcut icon: \(error)")
            return nil
        }
        return url
    }

    private static let iconDirectory = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AppShortcutIcons", isDirectory: true)

    // MARK: - Helpers

    private static func searchTerms(displayName: String,
                                    bundleIdentifier: String?,
                                    containerName: String?) -> [String] {
        var terms: Set<String> = [displayName.lcFolded]
        // Individual words, so "Prime Video" matches on "video".
        for word in displayName.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" }) {
            terms.insert(String(word).lcFolded)
        }
        if let bundleIdentifier {
            terms.insert(bundleIdentifier.lcFolded)
            if let last = bundleIdentifier.split(separator: ".").last {
                terms.insert(String(last).lcFolded)
            }
        }
        if let containerName {
            terms.insert(containerName.lcFolded)
        }
        terms.remove("")
        return Array(terms)
    }

    private static func sanitize(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    private static func resized(_ image: UIImage, to side: CGFloat) -> UIImage? {
        let size = CGSize(width: side, height: side)
        if image.size == size { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
