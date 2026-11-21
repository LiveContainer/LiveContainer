//
//  LCWindowManager.swift
//  LiveContainerSwiftUI
//  Summary (EN): Multitask window control: drives the window title-bar buttons (closeWindow / maximizeWindow / PiP / scale slider).
//
//  Remote control for multitask windows (PiP / scale / maximize / close).
//  These windows are scene-hosted AppSceneViewController instances wrapped in DecoratedAppSceneViewController,
//  so the approach is to walk the view-controller tree of every scene and act on them.
//
//  Note: both classes are API_AVAILABLE(ios(16.0)) while the project still ships an iOS 15 deployment target,
//  so every reference lives behind @available(iOS 16.0, *) internals with plain forwarding shims outside.
//

import UIKit

struct LCWindowInfo {
    let id: String            // dataUUID: unique per app instance
    let bundleId: String
    let pid: Int32
    let isRunning: Bool
    let scale: CGFloat
    let isMaximized: Bool?
    let isDecorated: Bool
    let frame: CGRect

    var json: [String: Any] {
        var d: [String: Any] = [
            "id": id,
            "bundleId": bundleId,
            "pid": Int(pid),
            "running": isRunning,
            "scale": Double(scale),
            "decorated": isDecorated,
            "frame": ["x": Double(frame.origin.x), "y": Double(frame.origin.y),
                      "width": Double(frame.width), "height": Double(frame.height)]
        ]
        if let isMaximized { d["maximized"] = isMaximized }
        return d
    }
}

enum LCWindowManagerError: LocalizedError {
    case notFound(String)
    case unsupported(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let id): return "no such window: \(id)"
        case .unsupported(let m): return m
        }
    }
}

@MainActor
enum LCWindowManager {

    static func windows() -> [LCWindowInfo] {
        if #available(iOS 16.0, *) {
            return LCWindowManager16.windows()
        }
        return []
    }

    /// Scale (0.4-3.0), matching what the scale slider in the UI does
    static func setScale(_ id: String, _ scale: CGFloat) throws {
        guard #available(iOS 16.0, *) else { throw LCWindowManagerError.unsupported("requires iOS 16+") }
        try LCWindowManager16.setScale(id, scale)
    }

    /// PiP in / out: uses DecoratedAppSceneViewController's own minimise/restore
    static func setPiP(_ id: String, enabled: Bool) throws {
        guard #available(iOS 16.0, *) else { throw LCWindowManagerError.unsupported("requires iOS 16+") }
        try LCWindowManager16.setPiP(id, enabled: enabled)
    }

    static func setMaximized(_ id: String, maximized: Bool) throws {
        guard #available(iOS 16.0, *) else { throw LCWindowManagerError.unsupported("requires iOS 16+") }
        try LCWindowManager16.setMaximized(id, maximized: maximized)
    }

    static func close(_ id: String) throws {
        guard #available(iOS 16.0, *) else { throw LCWindowManagerError.unsupported("requires iOS 16+") }
        try LCWindowManager16.close(id)
    }

    /// Selectors bound to the three title-bar buttons (close / maximize / minimize)
    static func chromeButtons(_ id: String) -> [[String: Any]] {
        if #available(iOS 16.0, *) {
            return LCWindowManager16.chromeButtons(id)
        }
        return []
    }

    /// Fires the selector a title-bar button is bound to (equivalent to tapping that button)
    @discardableResult
    static func pressChrome(_ id: String, selector: String) throws -> [String: Any] {
        guard #available(iOS 16.0, *) else { throw LCWindowManagerError.unsupported("requires iOS 16+") }
        return try LCWindowManager16.pressChrome(id, selector: selector)
    }

    /// For screenshots: prefer the whole decorated window, then the app content view; nil id uses the key window
    static func captureView(_ id: String?) -> UIView? {
        if let id {
            if #available(iOS 16.0, *) {
                return LCWindowManager16.captureView(id)
            }
            return nil
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

@available(iOS 16.0, *)
@MainActor
private enum LCWindowManager16 {

    private static func collectControllers(_ vc: UIViewController?, into out: inout [UIViewController]) {
        guard let vc else { return }
        out.append(vc)
        for child in vc.children {
            collectControllers(child, into: &out)
        }
        collectControllers(vc.presentedViewController, into: &out)
    }

    private static func allControllers() -> [UIViewController] {
        var out: [UIViewController] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                collectControllers(window.rootViewController, into: &out)
            }
        }
        return out
    }

    static func windows() -> [LCWindowInfo] {
        var out: [LCWindowInfo] = []
        var seen = Set<String>()
        for vc in allControllers() {
            if let deco = vc as? DecoratedAppSceneViewController, let inner = deco.appSceneVC {
                let id = inner.dataUUID ?? ""
                guard !id.isEmpty else { continue }
                if seen.contains(id) {
                    // Same id already listed: only the running instance may replace the stale entry
                    if inner.isAppRunning, let i = out.firstIndex(where: { $0.id == id }) {
                        out[i] = LCWindowInfo(id: id, bundleId: inner.bundleId ?? "", pid: inner.pid,
                                              isRunning: true, scale: deco.scaleRatio,
                                              isMaximized: deco.isMaximized, isDecorated: true,
                                              frame: deco.view.frame)
                    }
                    continue
                }
                seen.insert(id)
                out.append(LCWindowInfo(id: id, bundleId: inner.bundleId ?? "", pid: inner.pid,
                                        isRunning: inner.isAppRunning, scale: deco.scaleRatio,
                                        isMaximized: deco.isMaximized, isDecorated: true,
                                        frame: deco.view.frame))
            } else if let scene = vc as? AppSceneViewController {
                let id = scene.dataUUID ?? ""
                guard !id.isEmpty, !seen.contains(id) else { continue }
                seen.insert(id)
                out.append(LCWindowInfo(id: id, bundleId: scene.bundleId ?? "", pid: scene.pid,
                                        isRunning: scene.isAppRunning, scale: scene.scaleRatio,
                                        isMaximized: nil, isDecorated: false,
                                        frame: scene.view.frame))
            }
        }
        return out
    }

    /// Finds a controller by dataUUID. The same id can exist twice: a leftover from a previous
    /// run (already exited) and the current one, so do two passes: prefer isAppRunning, else any match.
    static func find(_ id: String) -> (decorated: DecoratedAppSceneViewController?, scene: AppSceneViewController)? {
        var fallback: (DecoratedAppSceneViewController?, AppSceneViewController)?
        for vc in allControllers() {
            if let deco = vc as? DecoratedAppSceneViewController, let inner = deco.appSceneVC,
               (inner.dataUUID ?? "") == id {
                if inner.isAppRunning { return (deco, inner) }
                if fallback == nil { fallback = (deco, inner) }
            } else if let scene = vc as? AppSceneViewController, (scene.dataUUID ?? "") == id {
                if scene.isAppRunning { return (nil, scene) }
                if fallback == nil { fallback = (nil, scene) }
            }
        }
        return fallback
    }

    static func captureView(_ id: String) -> UIView? {
        guard let found = find(id) else { return nil }
        if let deco = found.decorated { return deco.view }
        return found.scene.view
    }

    /// The three title-bar buttons (close / maximize / minimize) are plain UIBarButtonItems;
    /// listing them with their selectors lets callers press the button instead of inventing behaviour.
    static func chromeButtons(_ id: String) -> [[String: Any]] {
        guard let deco = find(id)?.decorated else { return [] }
        var out: [[String: Any]] = []
        let items = (deco.navigationBar.topItem?.leftBarButtonItems ?? [])
                  + (deco.navigationBar.topItem?.rightBarButtonItems ?? [])
        for (i, item) in items.enumerated() {
            guard let action = item.action else { continue }
            out.append([
                "index": i,
                "selector": NSStringFromSelector(action),
                "target": item.target.map { NSStringFromClass(type(of: $0)) } ?? "",
                "enabled": item.isEnabled,
                "tint": item.tintColor.map { "\($0)" } ?? ""
            ])
        }
        return out
    }

    /// Fires the selector a title-bar button is bound to (equivalent to tapping that button)
    @discardableResult
    static func pressChrome(_ id: String, selector: String) throws -> [String: Any] {
        guard let deco = find(id)?.decorated else {
            throw LCWindowManagerError.unsupported("window \(id) is not a decorated window, so it has no title-bar buttons")
        }
        let items = (deco.navigationBar.topItem?.leftBarButtonItems ?? [])
                  + (deco.navigationBar.topItem?.rightBarButtonItems ?? [])
        for item in items where item.action != nil {
            guard NSStringFromSelector(item.action!) == selector else { continue }
            let sent = UIApplication.shared.sendAction(item.action!, to: item.target, from: item, for: nil)
            LCRemoteLogStore.shared.append("window \(id) chrome button \(selector) sent=\(sent)", src: "api")
            return ["ok": sent, "selector": selector, "sent": sent]
        }
        // Title bar items unavailable (some states keep them out of the bar) -> send the same selector to the controller
        let sel = NSSelectorFromString(selector)
        guard deco.responds(to: sel) else {
            throw LCWindowManagerError.unsupported("decorated window has no \(selector); available buttons: \(chromeButtons(id))")
        }
        _ = deco.perform(sel)
        LCRemoteLogStore.shared.append("window \(id) performed \(selector) directly", src: "api")
        return ["ok": true, "selector": selector, "sent": false]
    }

    private static func findSlider(in v: UIView) -> UISlider? {
        if let s = v as? UISlider { return s }
        for sub in v.subviews {
            if let s = findSlider(in: sub) { return s }
        }
        return nil
    }

    static func setScale(_ id: String, _ scale: CGFloat) throws {
        guard let found = find(id) else { throw LCWindowManagerError.notFound(id) }
        let scene = found.scene
        let clamped = min(max(scale, 0.4), 3.0)
        // Prefer the scale slider's valueChanged event so the UI stays the source of truth
        if let deco = found.decorated, let slider = findSlider(in: deco.view) {
            slider.value = Float(clamped)
            slider.sendActions(for: .valueChanged)
            LCRemoteLogStore.shared.append("window \(id) scaleSliderChanged -> \(clamped)", src: "api")
            return
        }
        scene.scaleRatio = clamped
        if let deco = found.decorated {
            deco.scaleRatio = clamped
            deco.updateVerticalConstraints()
        }
        if let content = scene.contentView {
            if scene.usesHostingControllerAPI() {
                content.transform = CGAffineTransform(scaleX: clamped, y: clamped)
            } else {
                content.layer.sublayerTransform = CATransform3DMakeScale(clamped, clamped, 1.0)
            }
        }
        scene.updateFrame(settingsBlock: { (settings: UIMutableApplicationSceneSettings?) in
            guard let settings else { return }
            settings.peripheryInsets = .zero
            settings.safeAreaInsetsPortrait = .zero
        })
        LCRemoteLogStore.shared.append("window \(id) scale -> \(clamped)", src: "api")
    }

    static func setPiP(_ id: String, enabled: Bool) throws {
        guard let found = find(id), let deco = found.decorated else {
            throw LCWindowManagerError.unsupported("window \(id) is not a decorated window, cannot switch to PiP")
        }
        if enabled {
            deco.minimizeWindowPiP()
        } else {
            deco.unminimizeWindowPiP()
        }
        LCRemoteLogStore.shared.append("window \(id) pip=\(enabled)", src: "api")
    }

    static func setMaximized(_ id: String, maximized: Bool) throws {
        guard let found = find(id), let deco = found.decorated else {
            throw LCWindowManagerError.unsupported("window \(id) is not a decorated window")
        }
        if deco.isMaximized != maximized {
            // The green button is bound to maximizeWindow (a toggle)
            try pressChrome(id, selector: "maximizeWindow")
        }
        LCRemoteLogStore.shared.append("window \(id) maximized=\(maximized)", src: "api")
    }

    static func close(_ id: String) throws {
        guard let found = find(id) else { throw LCWindowManagerError.notFound(id) }
        if found.decorated != nil {
            // The red x is bound to closeWindow (sets _isAppTerminationRequested -> scene terminate)
            try pressChrome(id, selector: "closeWindow")
            return
        }
        found.scene.terminate()
        LCRemoteLogStore.shared.append("window \(id) terminated (undecorated)", src: "api")
    }
}
