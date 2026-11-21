//
//  LCRemoteUIAutomation.swift
//  LiveContainerSwiftUI
//  Summary (EN): Accessibility-tree export plus element activation (UIControl sendActions / accessibilityActivate / text match).
//
//  Exposes UI interaction through the API so an agent can drive the UI by itself:
//   - GET  /api/v1/ui/tree      accessibility tree (label / identifier / frame / activatable)
//   - POST /api/v1/ui/activate  activate an element by index / label / identifier / text
//   - POST /api/v1/ui/tap       tap by coordinate: hitTest -> UIControl.sendActions / accessibilityActivate
//   - POST /api/v1/ui/tab       switch tabs (set selectedIndex on the UITabBarController; most reliable)
//   - POST /api/v1/ui/text      type into the current first responder
//
//  SwiftUI buttons are not UIControls, so accessibilityActivate (the VoiceOver hook) is the way in.
//

import UIKit
import CryptoKit

struct LCRemoteUIElement {
    let index: Int
    let label: String
    let identifier: String
    let value: String
    let className: String
    let frame: CGRect
    let isControl: Bool
    let canActivate: Bool
    let depth: Int
    let text: String

    var json: [String: Any] {
        ["index": index,
         "label": label,
         "identifier": identifier,
         "value": value,
         "class": className,
         "frame": ["x": Double(frame.origin.x), "y": Double(frame.origin.y),
                   "w": Double(frame.width), "h": Double(frame.height)],
         "control": isControl,
         "activatable": canActivate,
         "depth": depth,
         "text": text]
    }
}

@MainActor
enum LCRemoteUIAutomation {

    private static let maxNodes = 600
    private static let maxDepth = 24

    /// Generic text extraction that does not rely on accessibilityLabel: pulls visible text from
    /// UILabel / UIButton titles / UISegmentedControl segments / UITextField (depth 6, up to 12 entries).
    /// Works for any UIKit app; SwiftUI already provides a11y labels, so the two complement each other.
    static func texts(of ns: NSObject) -> [String] {
        guard let view = ns as? UIView else {
            return (ns.accessibilityLabel?.isEmpty == false) ? [ns.accessibilityLabel!] : []
        }
        var out: [String] = []
        collectTexts(view, depth: 0, into: &out)
        if out.isEmpty, let l = ns.accessibilityLabel, !l.isEmpty { out.append(l) }
        return out
    }

    private static func collectTexts(_ v: UIView, depth: Int, into out: inout [String]) {
        if depth > 6 || out.count >= 12 { return }
        func add(_ t: String?) {
            guard let t, !t.isEmpty, !out.contains(t), out.count < 12 else { return }
            out.append(t)
        }
        if let l = v as? UILabel {
            add(l.text)
        } else if let b = v as? UIButton {
            add(b.title(for: .normal)); add(b.title(for: .selected))
        } else if let seg = v as? UISegmentedControl {
            for i in 0..<seg.numberOfSegments { add(seg.titleForSegment(at: i)) }
        } else if let f = v as? UITextField {
            add(f.text); add(f.placeholder)
        } else if let tv = v as? UITextView {
            add(tv.text)
        } else if let sb = v as? UISearchBar {
            add(sb.placeholder)
        }
        for sub in v.subviews { collectTexts(sub, depth: depth + 1, into: &out) }
    }

    // MARK: - Tree

    private static func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { !$0.isHidden && $0.alpha > 0.01 }
    }

    /// Single traversal entry point: tree() and activate(index:) must share the order, or indexes drift.
    /// Deduplicated by ObjectIdentifier: the same SwiftUI node shows up in both view.subviews and
    /// accessibilityElements, which otherwise repeats one label four times and burns the 600-node budget.
    private static func collect() -> [NSObject] {
        var out: [NSObject] = []
        var visited = Set<ObjectIdentifier>()
        for window in windows() {
            walk(window, depth: 0, visited: &visited, into: &out)
        }
        return out
    }

    private static func isInteresting(_ ns: NSObject) -> Bool {
        if !(ns.accessibilityLabel ?? "").isEmpty { return true }
        if !(((ns as? UIAccessibilityIdentification)?.accessibilityIdentifier) ?? "").isEmpty { return true }
        if !(ns.accessibilityValue ?? "").isEmpty { return true }
        if ns is UIControl { return true }
        return ns.accessibilityTraits.contains(.button) || ns.accessibilityTraits.contains(.link)
    }

    private static func walk(_ obj: Any, depth: Int, visited: inout Set<ObjectIdentifier>, into out: inout [NSObject]) {
        guard out.count < maxNodes, depth <= maxDepth, let ns = obj as? NSObject else { return }
        guard visited.insert(ObjectIdentifier(ns)).inserted else { return }

        if isInteresting(ns) { out.append(ns) }

        if let view = ns as? UIView {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            for sub in view.subviews { walk(sub, depth: depth + 1, visited: &visited, into: &out) }
        }
        if let elements = ns.accessibilityElements as? [Any] {
            for element in elements { walk(element, depth: depth + 1, visited: &visited, into: &out) }
        }
    }

    static func tree() -> [LCRemoteUIElement] {
        var out: [LCRemoteUIElement] = []
        for (index, ns) in collect().enumerated() {
            let label = ns.accessibilityLabel ?? ""
            let ident = (ns as? UIAccessibilityIdentification)?.accessibilityIdentifier ?? ""
            let value = ns.accessibilityValue ?? ""
            var frame = CGRect.zero
            if let view = ns as? UIView {
                frame = view.convert(view.bounds, to: nil)
            } else {
                frame = ns.accessibilityFrame
            }
            let activatable = ns is UIControl
                || ns.accessibilityTraits.contains(.button)
                || ns.accessibilityTraits.contains(.link)
                || ns.accessibilityTraits.contains(.tabBar)
            let text = texts(of: ns).joined(separator: " | ")
            out.append(LCRemoteUIElement(index: index, label: label, identifier: ident,
                                         value: value, className: String(describing: type(of: ns)),
                                         frame: frame, isControl: ns is UIControl,
                                         canActivate: activatable, depth: 0, text: text))
        }
        return out
    }

    // MARK: - Activation

    private static func object(for index: Int) -> NSObject? {
        let all = collect()
        guard index >= 0, index < all.count else { return nil }
        return all[index]
    }
    /// Activate by visible text (exact match first, then contains)
    static func activate(text wanted: String) -> (ok: Bool, detail: String) {
        guard !wanted.isEmpty else { return (false, "empty text") }
        let candidates = collect()
        for pass in 0..<2 {
            for ns in candidates {
                let ts = texts(of: ns)
                let hit = ts.contains { pass == 0 ? $0 == wanted : $0.contains(wanted) }
                guard hit else { continue }
                let r = activate(ns)
                if r.ok { return (true, r.detail + " (by text \"\(wanted)\"") }
            }
        }
        let sample = candidates.compactMap { ns -> String? in
            let ts = texts(of: ns)
            return ts.isEmpty ? nil : ts.joined(separator: "/")
        }.prefix(12)
        return (false, "no element with text \"\(wanted)\"; visible text on screen: \(sample.joined(separator: ", "))")
    }

    /// Activate by index; indexes come from /ui/tree
    static func activate(index: Int) -> (ok: Bool, detail: String) {
        guard let obj = object(for: index) else {
            return (false, "index \(index) does not exist; GET /api/v1/ui/tree first")
        }
        return activate(obj)
    }

    static func activate(label: String, identifier: String) -> (ok: Bool, detail: String) {
        let wanted = label.lowercased()
        let wantIdent = identifier.lowercased()
        var tried = 0
        var lastDetail = ""
        for element in tree() {
            let matched = (!wantIdent.isEmpty && element.identifier.lowercased() == wantIdent)
                || (!wanted.isEmpty && (element.label.lowercased() == wanted
                                        || element.label.lowercased().contains(wanted)))
            guard matched else { continue }
            tried += 1
            if let obj = object(for: element.index) {
                let r = activate(obj)
                if r.ok { return r }
                lastDetail = r.detail
            }
        }
        let name = label.isEmpty ? identifier : label
        if tried == 0 {
            return (false, "no element matches \(name) (GET /api/v1/ui/tree to inspect labels)")
        }
        return (false, "matched \(tried) candidate(s) for \(name) but none could be activated: \(lastDetail)")
    }

    private static func activate(_ obj: NSObject) -> (ok: Bool, detail: String) {
        let name = String(describing: type(of: obj))
        if let control = obj as? UIControl {
            control.sendActions(for: .touchUpInside)
            return (true, "sendActions(.touchUpInside) on \(name)")
        }
        if obj.accessibilityActivate() {
            return (true, "accessibilityActivate on \(name)")
        }
        if let view = obj as? UIView {
            // Tap the centre and see whether an inner control is hit
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            if let hit = view.hitTest(center, with: nil), hit !== view,
               let r = activateHit(hit) {
                return r
            }
        }
        if !(obj is UIView) {
            // SwiftUI rows/buttons often surface as AccessibilityNode only (not a UIView),
            // which accessibilityActivate ignores, so tap the centre of its own frame.
            let f = obj.accessibilityFrame
            if f.width > 1, f.height > 1 {
                let r = tap(x: f.midX, y: f.midY)
                if r.ok { return (true, r.detail + " (a11y frame center)") }
                return (false, "a11y node cannot be activated directly and tapping its frame failed: \(r.detail)")
            }
        }
        return (false, "\(name) cannot be activated (no accessibilityActivate / UIControl and no frame)")
    }

    private static func activateHit(_ hit: UIView) -> (ok: Bool, detail: String)? {
        var node: UIView? = hit
        while let current = node {
            if let field = current as? UITextField {
                field.becomeFirstResponder()
                return (true, "becomeFirstResponder on \(type(of: current))")
            }
            if let textView = current as? UITextView {
                textView.becomeFirstResponder()
                return (true, "becomeFirstResponder on \(type(of: current))")
            }
            if let control = current as? UIControl {
                control.sendActions(for: .touchUpInside)
                return (true, "sendActions(.touchUpInside) on \(type(of: current))")
            }
            if current.accessibilityActivate() {
                return (true, "accessibilityActivate on \(type(of: current))")
            }
            node = current.superview
        }
        return nil
    }

    // MARK: - Coordinate tap

    static func tap(x: CGFloat, y: CGFloat) -> (ok: Bool, detail: String) {
        let point = CGPoint(x: x, y: y)
        for window in windows() {
            guard window.bounds.contains(point) else { continue }
            guard let hit = window.hitTest(point, with: nil) else { continue }
            if let r = activateHit(hit) { return r }
            return (false, "hit \(type(of: hit)) but found no activatable control")
        }
        return (false, "(\(Int(x)),\(Int(y))) is outside every window")
    }

    // MARK: - Tab

    static func tab(index: Int?) -> (ok: Bool, detail: String) {
        var controllers: [UITabBarController] = []
        for window in windows() {
            collectTabBars(window.rootViewController, into: &controllers)
        }
        guard let tabBar = controllers.first else {
            return (false, "no UITabBarController found (a SwiftUI TabView is not always one)")
        }
        guard let index, index >= 0, index < (tabBar.viewControllers?.count ?? 0) else {
            let names = (tabBar.viewControllers ?? []).enumerated().map { "\($0.offset):\($0.element.tabBarItem.title ?? "?")" }
            return (false, "need an index (0..\((tabBar.viewControllers?.count ?? 1) - 1)); current: \(names.joined(separator: ", "))")
        }
        tabBar.selectedIndex = index
        return (true, "selectedIndex = \(index)")
    }

    private static func collectTabBars(_ vc: UIViewController?, into out: inout [UITabBarController]) {
        guard let vc else { return }
        if let t = vc as? UITabBarController { out.append(t) }
        for child in vc.children { collectTabBars(child, into: &out) }
        collectTabBars(vc.presentedViewController, into: &out)
    }

    // MARK: - Tap sequences (chained taps)

    static func screenHash(maxWidth: CGFloat = 96) -> String {
        guard let view = LCWindowManager.captureView(nil),
              let data = LCScreenshot.jpeg(of: view, maxWidth: maxWidth, quality: 30) else { return "" }
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    /// Runs label / index / coordinate steps in order, optionally waiting, and reports whether the screen changed.
    static func runSequence(_ steps: [[String: Any]], detectChange: Bool) async -> [[String: Any]] {
        var out: [[String: Any]] = []
        for (i, step) in steps.enumerated() {
            let before = detectChange ? screenHash() : ""
            var r: (ok: Bool, detail: String)
            if let label = step["label"] as? String, !label.isEmpty {
                r = activate(label: label, identifier: (step["identifier"] as? String) ?? "")
            } else if let identifier = step["identifier"] as? String, !identifier.isEmpty {
                r = activate(label: "", identifier: identifier)
            } else if let index = step["index"] as? Int {
                r = activate(index: index)
            } else if let x = number(step["x"]), let y = number(step["y"]) {
                r = tap(x: CGFloat(x), y: CGFloat(y))
            } else {
                r = (false, "a step needs label / identifier / text / index / x+y")
            }
            let delay = (step["delayMs"] as? Int) ?? 400
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
            let after = detectChange ? screenHash() : ""
            var item: [String: Any] = ["index": i, "ok": r.ok, "detail": r.detail]
            if detectChange { item["changed"] = (before != after) }
            if let note = step["note"] as? String { item["note"] = note }
            out.append(item)
        }
        return out
    }

    // MARK: - Text input

    static func typeText(_ text: String) -> (ok: Bool, detail: String) {
        guard let responder = firstResponder() else {
            return (false, "no first responder (tap the text field first)")
        }
        if let input = responder as? UIKeyInput {
            input.insertText(text)
            return (true, "insertText on \(type(of: responder))")
        }
        if let textField = responder as? UITextField {
            textField.text = (textField.text ?? "") + text
            return (true, "set text on UITextField")
        }
        // When a UISearchBar is first responder it is not UIKeyInput, but it owns a UITextField
        if let view = responder as? UIView, let input = findTextInput(in: view) {
            input.insertText(text)
            return (true, "insertText on \(type(of: input)) (found inside \(type(of: responder)))")
        }
        return (false, "\(type(of: responder)) does not accept text input")
    }

    private static func firstResponder() -> UIResponder? {
        for window in windows() {
            if let r = findFirstResponder(in: window) { return r }
        }
        return nil
    }

    private static func findTextInput(in view: UIView) -> UIKeyInput? {
        if let input = view as? UITextField { return input }
        if let input = view as? UITextView { return input }
        for sub in view.subviews {
            if let r = findTextInput(in: sub) { return r }
        }
        return nil
    }

    private static func findFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let r = findFirstResponder(in: sub) { return r }
        }
        return nil
    }
}
