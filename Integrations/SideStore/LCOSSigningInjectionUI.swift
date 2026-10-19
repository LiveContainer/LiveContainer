import Foundation
import ObjectiveC
#if canImport(UIKit)
import Darwin
#endif

/// Optional UI bridge: standalone SideStore stays unchanged; background refresh never calls this.
@MainActor
enum LCOSSigningInjectionUI {
    private static var presenting = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    static func configure(identifier: String, appName: String, presenter: NSObject) async throws {
        do { try SigningInjectionPreset.validateTarget(identifier) } catch { return }
        #if canImport(UIKit)
        // SideStore can run in a separate LiveProcess where LC's UI has not been loaded yet.
        if NSClassFromString("LCOSSigningInjectionPresenter") == nil,
           let shared = NSClassFromString("LCSharedUtils") {
            let bundle = Bundle(for: shared)
            let relative = "LiveContainerSwiftUI.framework/LiveContainerSwiftUI"
            let candidates = [bundle.privateFrameworksURL?.appendingPathComponent(relative).path,
                              bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(relative).path,
                              "@rpath/" + relative].compactMap { $0 }
            for path in candidates {
                if dlopen(path, RTLD_LAZY | RTLD_GLOBAL) != nil { break }
            }
        }
        if NSClassFromString("LCSharedUtils") != nil,
           NSClassFromString("LCOSSigningInjectionPresenter") == nil {
            throw SigningInjectionFailure.invalid("LiveContainer signing options could not be loaded")
        }
        #endif
        guard let type = NSClassFromString("LCOSSigningInjectionPresenter"),
              let method = class_getClassMethod(type, NSSelectorFromString("configureBundleIdentifier:appName:presenter:completion:")) else { return }
        // A batch may prepare several apps concurrently; present one sheet at a time.
        if presenting { await withCheckedContinuation { waiters.append($0) } }
        else { presenting = true }
        defer {
            if waiters.isEmpty { presenting = false }
            else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        typealias Callback = @convention(block) (Bool) -> Void
        typealias Configure = @convention(c) (AnyObject, Selector, NSString, NSString, NSObject, Callback) -> Void
        let configure = unsafeBitCast(method_getImplementation(method), to: Configure.self)
        let accepted: Bool = await withCheckedContinuation { continuation in
            configure(type as AnyObject, NSSelectorFromString("configureBundleIdentifier:appName:presenter:completion:"),
                      identifier as NSString, appName as NSString, presenter) { accepted in
                continuation.resume(returning: accepted)
            }
        }
        guard accepted else { throw CancellationError() }
        try Task.checkCancellation()
    }
}
