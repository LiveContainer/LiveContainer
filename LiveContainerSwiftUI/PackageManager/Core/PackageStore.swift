import Foundation

struct PackageReceipt: Codable, Identifiable {
    let schema: Int
    let id: String
    let version: String
    let name: String
    let targetBundle: String
    let origin: String
    let installedAt: Date
    let sha256: [String: String]
    let binaryNames: [String]
    let warnings: [String]
    let signature: String
    // No load attempt has happened during installation.
    let runtimeStatus: String
}

actor PackageStore {
    let root: URL
    private var busy = false
    private let fm = FileManager.default
    init(root: URL) { self.root = root }

    private func validateRoot() throws {
        // Resolve neither imported paths nor package IDs into arbitrary storage locations.
        var path = root.standardizedFileURL
        while path.path != "/", !path.path.isEmpty {
            if fm.fileExists(atPath: path.path) {
                let attributes = try fm.attributesOfItem(atPath: path.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw PackageFailure.invalid("Package storage contains a symbolic link or non-directory")
                }
            }
            let parent = path.deletingLastPathComponent()
            if parent == path { break }
            path = parent
        }
    }
    private func folder(_ identifier: String, enabled: Bool) throws -> URL {
        guard identifier.range(of: "^[a-z0-9][a-z0-9+.-]+$", options: .regularExpression) != nil else {
            throw PackageFailure.invalid("Invalid receipt identifier")
        }
        return root.appendingPathComponent("lcos-" + identifier + (enabled ? "" : ".disabled"))
    }

    func inventory() throws -> [(PackageReceipt, Bool)] {
        try validateRoot()
        guard fm.fileExists(atPath: root.path) else { return [] }
        return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("lcos-") }
            .map { url in
                let receipt = try readReceipt(at: url)
                let enabled = !url.lastPathComponent.hasSuffix(".disabled")
                guard url == (try folder(receipt.id, enabled: enabled)) else {
                    throw PackageFailure.invalid("Package directory does not match its receipt")
                }
                return (receipt, enabled)
            }.sorted { $0.0.id < $1.0.id }
    }

    private func readReceipt(at url: URL) throws -> PackageReceipt {
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw PackageFailure.invalid("Invalid package directory") }
        let receiptURL = url.appendingPathComponent("receipt.json")
        let receiptAttributes = try fm.attributesOfItem(atPath: receiptURL.path)
        guard receiptAttributes[.type] as? FileAttributeType == .typeRegular,
              (receiptAttributes[.size] as? NSNumber)?.intValue ?? Int.max < 1024 * 1024 else {
            throw PackageFailure.invalid("Invalid package receipt")
        }
        let receipt = try JSONDecoder().decode(PackageReceipt.self, from: Data(contentsOf: receiptURL))
        guard receipt.schema == 1 else { throw PackageFailure.invalid("Unsupported receipt version; files preserved") }
        return receipt
    }

    func install(_ plan: TweakInstallPlan, targetBundle: String,
                 signer: (URL) async throws -> Void) async throws -> PackageReceipt {
        guard !busy else { throw PackageFailure.invalid("Another package transaction is running") }
        busy = true
        defer { busy = false }
        try validateRoot()
        guard plan.targetBundles.contains(targetBundle) else { throw PackageFailure.invalid("Target does not match plan") }
        let final = try folder(plan.package.control["package"], enabled: true)
        let disabled = try folder(plan.package.control["package"], enabled: false)
        guard !fm.fileExists(atPath: final.path), !fm.fileExists(atPath: disabled.path) else {
            throw PackageFailure.invalid("Package already installed; remove it before replacing this version")
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Same filesystem as final location, invisible to the loader until commit.
        let stage = root.appendingPathComponent(".transaction-\(UUID().uuidString).disabled")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        for (name, contents) in plan.files {
            guard try DebianPackage.safePath(name) == name, !name.contains("/") else { throw PackageFailure.invalid("Invalid prepared filename") }
            try contents.write(to: stage.appendingPathComponent(name), options: .withoutOverwriting)
        }
        try await signer(stage)
        var hashes: [String: String] = [:]
        for name in plan.files.keys {
            hashes[name] = PackageSHA256.hex(try Data(contentsOf: stage.appendingPathComponent(name)))
        }
        let receipt = PackageReceipt(schema: 1, id: plan.package.control["package"], version: plan.package.control["version"],
            name: plan.package.control["name"].isEmpty ? plan.package.control["package"] : plan.package.control["name"],
            targetBundle: targetBundle, origin: plan.package.layout, installedAt: Date(), sha256: hashes,
            binaryNames: plan.binaries.keys.sorted(), warnings: plan.warnings, signature: "verified by installer signer",
            runtimeStatus: "not attempted")
        try JSONEncoder().encode(receipt).write(to: stage.appendingPathComponent("receipt.json"), options: .atomic)
        try fm.moveItem(at: stage, to: final)
        return receipt
    }

    func verify(_ identifier: String, enabled: Bool) throws {
        try validateRoot()
        let directory = try folder(identifier, enabled: enabled)
        let receipt = try readReceipt(at: directory)
        for (name, hash) in receipt.sha256 {
            guard try DebianPackage.safePath(name) == name, !name.contains("/") else { throw PackageFailure.invalid("Invalid receipt path") }
            let file = directory.appendingPathComponent(name)
            let attributes = try fm.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  PackageSHA256.hex(try Data(contentsOf: file)) == hash else { throw PackageFailure.invalid("Integrity check failed for \(name)") }
        }
    }

    func setEnabled(_ identifier: String, enabled: Bool) throws {
        guard !busy else { throw PackageFailure.invalid("Another package transaction is running") }
        try verify(identifier, enabled: !enabled)
        try fm.moveItem(at: folder(identifier, enabled: !enabled), to: folder(identifier, enabled: enabled))
    }

    func remove(_ identifier: String, enabled: Bool) throws {
        guard !busy else { throw PackageFailure.invalid("Another package transaction is running") }
        try validateRoot()
        let source = try folder(identifier, enabled: enabled)
        let receipt = try readReceipt(at: source)
        guard receipt.id == identifier else { throw PackageFailure.invalid("Receipt identity mismatch") }
        let trash = root.appendingPathComponent(".removal-\(UUID().uuidString).disabled")
        try fm.moveItem(at: source, to: trash)
        do { try fm.removeItem(at: trash) }
        catch {
            try fm.moveItem(at: trash, to: source)
            throw error
        }
    }
}
