import Foundation

enum SigningBundleIdentifiers {
    static func extensionMap(originalParent: String, targetParent: String, signedParent: String,
                             extensions: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        var used = Set<String>()
        for identifier in extensions {
            guard identifier.hasPrefix(originalParent + ".") else {
                throw SigningInjectionFailure.invalid("Extension bundle ID must begin with its parent bundle ID followed by a dot: \(identifier)")
            }
            let suffix = String(identifier.dropFirst(originalParent.count))
            let signed = signedParent + suffix
            guard used.insert(signed).inserted else {
                throw SigningInjectionFailure.invalid("Duplicate extension bundle ID: \(signed)")
            }
            // ResignAppOperation looks up the ID after applying the custom parent ID.
            result[targetParent + suffix] = signed
        }
        return result
    }

    static func validateBundle(at app: URL) throws {
        func identifier(_ bundle: URL) throws -> String {
            let data = try Data(contentsOf: bundle.appendingPathComponent("Info.plist"))
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let id = plist["CFBundleIdentifier"] as? String, !id.isEmpty else {
                throw SigningInjectionFailure.invalid("Missing bundle identifier in \(bundle.lastPathComponent)")
            }
            return id
        }
        let parent = try identifier(app)
        let plugins = app.appendingPathComponent("PlugIns")
        guard FileManager.default.fileExists(atPath: plugins.path) else { return }
        var used = Set<String>()
        for bundle in try FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
            where bundle.pathExtension == "appex" {
            let id = try identifier(bundle)
            guard id.hasPrefix(parent + "."), used.insert(id).inserted else {
                throw SigningInjectionFailure.invalid("Invalid or duplicate extension bundle ID \(id); expected prefix \(parent). Reinstall using a fresh IPA or remove the affected extension.")
            }
        }
    }
}
