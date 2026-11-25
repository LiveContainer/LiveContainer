//
//  EchoStore.swift
//  Echo Launcher
//
//  Fetches the manifest, keeps the client libraries in the global tweak folder in step with it,
//  and hands the game IPA to LiveContainer's own installer.
//

import Foundation
import CryptoKit
import SwiftUI

@MainActor
final class EchoStore: ObservableObject {
    static let manifestKey = "EchoManifestURL"
    static let rendererKey = "EchoRenderer"
    static let installedGameKey = "EchoInstalledGameSHA256"

    @Published var manifestAddress: String = UserDefaults.standard.string(forKey: EchoStore.manifestKey) ?? ""
    @Published var renderer: EchoRenderer = EchoRenderer(rawValue: UserDefaults.standard.string(forKey: EchoStore.rendererKey) ?? "") ?? .echo
    @Published var manifest: EchoManifest?
    @Published var status: String = ""
    @Published var busy = false
    @Published var progress: Double = 0

    var gameNeedsInstall: Bool {
        guard let manifest else { return false }
        return UserDefaults.standard.string(forKey: EchoStore.installedGameKey)?.lowercased() != manifest.game.sha256.lowercased()
    }

    func saveAddress() {
        UserDefaults.standard.set(manifestAddress.trimmingCharacters(in: .whitespacesAndNewlines), forKey: EchoStore.manifestKey)
    }

    func setRenderer(_ value: EchoRenderer) {
        renderer = value
        UserDefaults.standard.set(value.rawValue, forKey: EchoStore.rendererKey)
        do {
            try applyRenderer()
            status = "Renderer: \(value.title)"
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: manifest

    private func httpsURL(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.lowercased() == "https" else {
            throw EchoError.message("Every address must use HTTPS: \(text)")
        }
        return url
    }

    private func safeName(_ name: String) throws -> String {
        if name.isEmpty || name.contains("/") || name.contains("\\") || name.hasPrefix(".") {
            throw EchoError.message("The manifest has an invalid file name: \(name)")
        }
        return name
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            saveAddress()
            let url = try httpsURL(manifestAddress)
            status = "Checking for updates"
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw EchoError.message("The manifest request failed")
            }
            let decoded = try JSONDecoder().decode(EchoManifest.self, from: data)
            guard decoded.version == 1 else {
                throw EchoError.message("This launcher is too old for the manifest (version \(decoded.version))")
            }
            manifest = decoded
            try await syncClient(decoded)
            status = gameNeedsInstall ? "Game install needed" : "Up to date"
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: client libraries (global tweak folder)

    private var tweakFolder: URL { LCPath.tweakPath }

    private func syncClient(_ manifest: EchoManifest) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: tweakFolder, withIntermediateDirectories: true)
        let files = manifest.client ?? []
        for (index, file) in files.enumerated() {
            let name = try safeName(file.name)
            let enabled = tweakFolder.appendingPathComponent(name)
            let disabled = tweakFolder.appendingPathComponent(name + ".disabled")
            let existing = fm.fileExists(atPath: enabled.path) ? enabled : (fm.fileExists(atPath: disabled.path) ? disabled : nil)
            if let existing, let have = try? Self.sha256(of: existing), have == file.sha256.lowercased() {
                continue
            }
            status = "Downloading \(name)"
            progress = Double(index) / Double(max(files.count, 1))
            let temp = try await download(try httpsURL(file.url), expecting: file.sha256)
            for old in [enabled, disabled] where fm.fileExists(atPath: old.path) {
                try fm.removeItem(at: old)
            }
            try fm.moveItem(at: temp, to: enabled)
        }
        progress = 1
        try applyRenderer()
    }

    /// Libraries tagged for the other renderer are renamed to ".disabled", which TweakLoader skips.
    private func applyRenderer() throws {
        guard let manifest else { return }
        let fm = FileManager.default
        for file in manifest.client ?? [] {
            let name = try safeName(file.name)
            let enabled = tweakFolder.appendingPathComponent(name)
            let disabled = tweakFolder.appendingPathComponent(name + ".disabled")
            let wanted = file.renderer == nil || file.renderer == renderer.rawValue
            if wanted, fm.fileExists(atPath: disabled.path), !fm.fileExists(atPath: enabled.path) {
                try fm.moveItem(at: disabled, to: enabled)
            } else if !wanted, fm.fileExists(atPath: enabled.path) {
                if fm.fileExists(atPath: disabled.path) {
                    try fm.removeItem(at: disabled)
                }
                try fm.moveItem(at: enabled, to: disabled)
            }
        }
    }

    // MARK: game

    func installGame() async {
        guard !busy, let manifest else { return }
        busy = true
        defer { busy = false }
        do {
            status = "Downloading Fortnite"
            progress = 0
            let temp = try await download(try httpsURL(manifest.game.url), expecting: manifest.game.sha256)
            let ipa = FileManager.default.temporaryDirectory.appendingPathComponent("EchoGame.ipa")
            if FileManager.default.fileExists(atPath: ipa.path) {
                try FileManager.default.removeItem(at: ipa)
            }
            try FileManager.default.moveItem(at: temp, to: ipa)
            UserDefaults.standard.set(manifest.game.sha256.lowercased(), forKey: EchoStore.installedGameKey)
            status = "Installing Fortnite"
            DataManager.shared.model.selectedTab = .apps
            // the app list only listens once its tab has been shown
            try? await Task.sleep(nanoseconds: 700_000_000)
            NotificationCenter.default.post(name: NSNotification.InstallAppNotification, object: ["url": ipa])
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: download + integrity

    private func download(_ url: URL, expecting sha256: String) async throws -> URL {
        let (location, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EchoError.message("Download failed: \(url.lastPathComponent)")
        }
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("echo-" + UUID().uuidString)
        try FileManager.default.moveItem(at: location, to: kept)
        let have = try await Task.detached { try EchoStore.sha256(of: kept) }.value
        guard have == sha256.lowercased() else {
            try? FileManager.default.removeItem(at: kept)
            throw EchoError.message("\(url.lastPathComponent) failed its integrity check")
        }
        return kept
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
