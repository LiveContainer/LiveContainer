// LiveContainer fork integration. No upstream contribution is submitted by this build overlay.
import Foundation
import ObjectiveC

enum LCOSSigningInjection {
    static func prepare(at app: URL, bundleIdentifier: String) throws {
        // LiveContainerShared is already loaded by the integrated SideStore host.
        // Standalone SideStore has no shared LiveContainer configuration and stays unchanged.
        guard let type = NSClassFromString("LCSharedUtils"),
              let method = class_getClassMethod(type, NSSelectorFromString("appGroupPath")) else { return }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        guard let group = getter(type as AnyObject, NSSelectorFromString("appGroupPath"))?.takeUnretainedValue() as? URL else {
            throw SigningInjectionFailure.invalid("LiveContainer shared signing configuration is unavailable")
        }
        try SigningInjectionApply.prepare(app: app, identifier: bundleIdentifier,
            root: group.appendingPathComponent("LiveContainer/SigningInjection"))
    }
}
