import Foundation

struct SigningInjectionPreset: Codable, Equatable {
    struct File: Codable, Equatable { var path: String; var sha256: String }
    var schema = 1
    var bundleIdentifier: String
    var enabled = true
    var files: [File]
    var libraries: [String]
    var packageNames: [String]
    static func directory(_ identifier: String, root: URL) -> URL { root.appendingPathComponent(PackageSHA256.hex(Data(identifier.utf8))) }
    static func validateTarget(_ identifier: String) throws {
        guard identifier.count <= 255, identifier.contains("."),
              identifier.range(of: #"\A[A-Za-z0-9][A-Za-z0-9.-]+\z"#, options: .regularExpression) != nil,
              !identifier.hasPrefix("com.apple."), !identifier.lowercased().contains("sidestore"),
              !identifier.lowercased().contains("livecontainer") else { throw SigningInjectionFailure.invalid("Choose an explicit third-party application bundle identifier") }
    }
    func write(to root: URL) throws {
        try Self.validateTarget(bundleIdentifier)
        guard schema == 1, files.count <= 256, libraries.count <= 64,
              Set(files.map(\.path)).count == files.count, Set(libraries).count == libraries.count else {
            throw SigningInjectionFailure.invalid("Injection preset exceeds supported limits or contains duplicate entries")
        }
        let folder = Self.directory(bundleIdentifier, root: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent("preset.json"), options: .atomic)
    }
    static func read(_ identifier: String, root: URL) throws -> Self? {
        let url = directory(identifier, root: root).appendingPathComponent("preset.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 1_048_576 else { throw SigningInjectionFailure.invalid("Oversized injection preset") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schema == 1, value.bundleIdentifier == identifier, value.files.count <= 256, value.libraries.count <= 64 else {
            throw SigningInjectionFailure.invalid("Invalid injection preset")
        }
        return value
    }
}

/// Shared by LiveContainer's configuration UI and the source-built SideStore signing operation.
enum SigningInjectionApply {
    static func prepare(app: URL, identifier: String, root: URL) throws {
        let manager = FileManager.default
        let preset = try SigningInjectionPreset.read(identifier, root: root)
        let frameworkRoot = app.appendingPathComponent("Frameworks")
        let destination = frameworkRoot.appendingPathComponent("LCOSInjected")
        let receipt = destination.appendingPathComponent("lcos-owned.json")
        let exists = manager.fileExists(atPath: destination.path)
        if exists, !manager.fileExists(atPath: receipt.path) { throw SigningInjectionFailure.invalid("LCOSInjected folder belongs to the original app; refusing to overwrite it") }
        guard preset?.enabled == true || exists else { return }
        let infoData = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty, !executable.contains("/"), !executable.contains("..") else {
            throw SigningInjectionFailure.invalid("Invalid application executable")
        }
        let binaryURL = app.appendingPathComponent(executable)
        let originalAttributes = try manager.attributesOfItem(atPath: binaryURL.path)
        let original = try Data(contentsOf: binaryURL)
        let libraries = preset?.enabled == true ? preset!.libraries : []
        let changed = try SigningMachO.inject(original, libraries: libraries)
        // Stage and validate every byte before modifying the application. SideStore signs after this returns.
        let stage = frameworkRoot.appendingPathComponent(".lcos-injection-" + UUID().uuidString)
        try manager.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: stage) }
        if let preset, preset.enabled {
            try SigningInjectionPreset.validateTarget(identifier)
            let source = SigningInjectionPreset.directory(identifier, root: root)
            var paths = Set<String>()
            for file in preset.files {
                let parts = file.path.split(separator: "/", omittingEmptySubsequences: false)
                guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                      !file.path.hasPrefix("."), paths.insert(file.path).inserted else { throw SigningInjectionFailure.invalid("Invalid injection payload path") }
                let url = source.appendingPathComponent(file.path).resolvingSymlinksInPath()
                guard url.path.hasPrefix(source.resolvingSymlinksInPath().path + "/") else { throw SigningInjectionFailure.invalid("Injection payload escapes preset") }
                let attributes = try manager.attributesOfItem(atPath: url.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 64 * 1024 * 1024 else { throw SigningInjectionFailure.invalid("Invalid injection payload file") }
                let data = try Data(contentsOf: url)
                guard PackageSHA256.hex(data) == file.sha256 else { throw SigningInjectionFailure.invalid("Injection payload checksum mismatch: " + file.path) }
                let target = stage.appendingPathComponent(file.path)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target)
            }
            guard libraries.allSatisfy({ paths.contains($0) }) else { throw SigningInjectionFailure.invalid("Missing injection library payload") }
            try JSONEncoder().encode(preset).write(to: stage.appendingPathComponent("lcos-owned.json"))
        }
        let backup = frameworkRoot.appendingPathComponent(".lcos-backup-" + UUID().uuidString)
        if exists { try manager.moveItem(at: destination, to: backup) }
        do {
            if !libraries.isEmpty { try manager.moveItem(at: stage, to: destination) }
            try changed.write(to: binaryURL, options: .atomic)
            if let permissions = originalAttributes[.posixPermissions] { try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: binaryURL.path) }
            try? manager.removeItem(at: backup)
        } catch {
            try? original.write(to: binaryURL, options: .atomic)
            if let permissions = originalAttributes[.posixPermissions] { try? manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: binaryURL.path) }
            try? manager.removeItem(at: destination)
            if exists { try? manager.moveItem(at: backup, to: destination) }
            throw error
        }
    }
}
