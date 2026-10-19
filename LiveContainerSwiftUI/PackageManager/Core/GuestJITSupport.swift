import Foundation

enum GuestJITSupport {
    /// Use the script shipped by the imported app, never a mutable remote download.
    static func bundledScript(in app: URL, bundleIdentifier: String) throws -> Data? {
        guard bundleIdentifier == "com.husk.app" || bundleIdentifier.hasPrefix("com.husk.app.") else { return nil }
        let root = app.resolvingSymlinksInPath().path + "/"
        for relative in ["husk-jit.js", "Resources/husk-jit.js"] {
            let url = app.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard url.resolvingSymlinksInPath().path.hasPrefix(root) else {
                throw SigningInjectionFailure.invalid("Bundled JIT script escapes the application bundle")
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 256 * 1024 else {
                throw SigningInjectionFailure.invalid("Bundled JIT script is not a bounded regular file")
            }
            let bytes = try Data(contentsOf: url)
            guard String(data: bytes, encoding: .utf8) != nil else {
                throw SigningInjectionFailure.invalid("Bundled JIT script is not UTF-8")
            }
            return bytes
        }
        return nil
    }
}
