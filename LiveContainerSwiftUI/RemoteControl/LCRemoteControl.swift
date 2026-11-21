//
//  LCRemoteControl.swift
//  LiveContainerSwiftUI
//  Summary (EN): Opt-in loopback HTTP server lifecycle (settings toggle, port, bearer token, keep-alive).
//
//  Server lifecycle and singleton facade. AppDelegate calls startIfEnabled() on launch.
//

import Foundation
import UIKit

@MainActor
final class LCRemoteControl {
    static let shared = LCRemoteControl()

    private var server: LCRemoteHTTPServer?
    private(set) var lastError: String?

    private init() {}

    var isRunning: Bool { server?.isRunning ?? false }
    var boundPort: UInt16 { server?.boundPort ?? 0 }
    var isEnabled: Bool { LCRemoteConfig.isEnabled }

    func startIfEnabled() {
        guard LCRemoteConfig.isEnabled else { return }
        do {
            try start()
        } catch {
            lastError = error.localizedDescription
            LCRemoteLogStore.shared.append("start failed: \(error.localizedDescription)", src: "api")
        }
    }

    func start() throws {
        stop()
        LCRemoteLogStore.shared.installCapture()
        let srv = LCRemoteHTTPServer { req in
            await LCRemoteAPI.handle(req)
        }
        srv.onLog = { msg in
            LCRemoteLogStore.shared.append(msg, src: "api")
        }
        // The guest sidecar shares this token through an app-group file.
        LCRemoteGuestProxy.writeTokenIfNeeded()
        try srv.start(port: LCRemoteConfig.port)
        server = srv
        lastError = nil
        // Restore keep-alive (silent audio / screen awake) per settings once the server is up.
        LCRemoteKeepAlive.shared.restore()
        LCRemoteLogStore.shared.append("remote control started on :\(LCRemoteConfig.port)", src: "api")
    }

    func stop() {
        server?.stop()
        server = nil
        LCRemoteKeepAlive.shared.suspend()
    }

    func restart() {
        stop()
        guard LCRemoteConfig.isEnabled else { return }
        try? start()
    }

    func applyEnabled(_ enabled: Bool) {
        LCRemoteConfig.isEnabled = enabled
        if enabled {
            restart()
        } else {
            stop()
        }
    }

    /// Keep-alive across foreground/background changes: iOS keeps the listener alive in the foreground.
    func installLifecycleHooks() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, LCRemoteConfig.isEnabled, !self.isRunning else { return }
                self.startIfEnabled()
            }
        }
    }
}
