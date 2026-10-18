import Foundation

struct TweakInstallPlan {
    let package: DebianPackage
    let files: [String: Data]
    let targetBundles: [String]
    let binaries: [String: MachOInspection]
    let warnings: [String]

    init(package: DebianPackage, targetBundle: String) throws {
        guard !targetBundle.lowercased().contains("sidestore"), !targetBundle.lowercased().contains("livecontainer"),
              !targetBundle.hasPrefix("com.apple.") else { throw PackageFailure.invalid("Protected host, store or system application") }
        guard package.scripts.isEmpty else { throw PackageFailure.invalid("Package contains maintainer actions: \(package.scripts.joined(separator: ", ")). They are never executed; source adaptation required.") }
        guard package.layout != "mixed" else { throw PackageFailure.invalid("Mixed rootful/rootless layout requires manual review") }
        // Full Debian version/alternative resolution is not implemented. Do not pretend dependencies are satisfied.
        for field in ["depends", "pre-depends", "conflicts", "breaks"] where !package.control[field].isEmpty {
            let terms = package.control[field].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard field == "depends", terms.allSatisfy({ ["mobilesubstrate", "firmware"].contains($0) }) else {
                throw PackageFailure.invalid("Dependency resolution required: \(field): \(package.control[field])")
            }
        }
        var output: [String: Data] = [:], inspections: [String: MachOInspection] = [:]
        var targets = Set<String>()
        let directories = ["Library/MobileSubstrate/DynamicLibraries/", "usr/lib/TweakInject/"]
        for (path, data) in package.files {
            let relative = path.hasPrefix("var/jb/") ? String(path.dropFirst(7)) : path
            if relative.hasPrefix("usr/share/doc/") { continue }
            guard let prefix = directories.first(where: { relative.hasPrefix($0) }) else {
                throw PackageFailure.invalid("Unsupported package resource or system component: \(path)")
            }
            let name = String(relative.dropFirst(prefix.count))
            guard !name.contains("/"), !name.hasPrefix("."), name != "TweakLoader.dylib", output[name] == nil else {
                throw PackageFailure.invalid("Duplicate or unsupported runtime path: \(path)")
            }
            if name.hasSuffix(".dylib") {
                let result = try MachOInspection.inspectAndAdapt(data)
                output[name] = result.0
                inspections[name] = result.1
            } else if name.hasSuffix(".plist") {
                guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let filter = plist["Filter"] as? [String: Any],
                      let bundles = filter["Bundles"] as? [String], !bundles.isEmpty,
                      Set(filter.keys) == Set(["Bundles"]) else {
                    throw PackageFailure.invalid("Requires an explicit Bundles-only MobileSubstrate filter: \(name)")
                }
                guard bundles.contains(targetBundle), !bundles.contains(where: { $0.hasPrefix("com.apple.") }) else {
                    throw PackageFailure.invalid("Tweak filter does not match selected guest or targets a system process")
                }
                targets.formUnion(bundles)
                output[name] = data
            } else { throw PackageFailure.invalid("Unsupported tweak file: \(name)") }
        }
        guard !inspections.isEmpty else { throw PackageFailure.invalid("No supported tweak dylibs") }
        for binary in inspections.keys {
            let plist = String(binary.dropLast(6)) + ".plist"
            guard output[plist] != nil else { throw PackageFailure.invalid("Missing target filter for \(binary)") }
        }
        self.package = package
        self.files = output
        self.binaries = inspections
        self.targetBundles = targets.sorted()
        self.warnings = ["Potentially compatible, untested. Installation and signing do not verify loading or hook behavior.",
                         "Native tweaks can access data available to the LiveContainer host process."]
    }
}
