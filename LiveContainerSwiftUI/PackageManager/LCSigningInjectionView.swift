import SwiftUI
import UniformTypeIdentifiers

struct LCSigningInjectionView: View {
    @State private var target = ""
    @State private var presets: [SigningInjectionPreset] = []
    @State private var importing = false
    @State private var working = false
    @State private var error: String?
    @State private var pending: Pending?
    @EnvironmentObject private var shared: SharedModel
    private struct Pending: Identifiable, Sendable {
        let id = UUID()
        let target: String
        let files: [String: Data]
        let libraries: [String]
        let name: String
        let substrate: Bool
    }
    private var root: URL? { LCSharedUtils.appGroupPath()?.appendingPathComponent("LiveContainer/SigningInjection") }

    var body: some View {
        Form {
            Section {
                TextField("lcos.signing.bundle".loc, text: $target)
                    .textInputAutocapitalization(.never).disableAutocorrection(true).autocorrectionDisabled()
                Menu("lcos.signing.chooseGuest".loc) {
                    ForEach(shared.apps, id: \.appInfo.relativeBundlePath) { app in
                        Button(app.displayName) { target = app.bundleIdentifier }
                    }
                }
                Button { importing = true } label: { Label("lcos.signing.import".loc, systemImage: "doc.badge.plus") }
                    .disabled(working || target.isEmpty)
            } header: { Text("lcos.signing.title".loc) } footer: { Text("lcos.signing.description".loc) }
            Section {
                ForEach(presets, id: \.bundleIdentifier) { preset in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(get: { presets.first { $0.bundleIdentifier == preset.bundleIdentifier }?.enabled ?? false },
                                             set: { setEnabled(preset.bundleIdentifier, $0) })) {
                            Text(preset.bundleIdentifier).font(.subheadline.weight(.medium))
                        }
                        Text(preset.packageNames.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        Text("\(preset.libraries.count) dylib").font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { removePreset(preset.bundleIdentifier) } label: { Label("lc.common.delete".loc, systemImage: "trash") }
                    }
                }
                if presets.isEmpty { Text("lcos.signing.empty".loc).foregroundStyle(.secondary) }
            } header: { Text("lcos.signing.configured".loc) }
            if working { ProgressView() }
        }
        .lcSoftScrollEdges()
        .navigationTitle("lcos.signing.title".loc)
        .task { reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { Task { await inspect(url) } } }
            catch { self.error = error.localizedDescription }
        }
        .alert("lc.common.error".loc, isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("lc.common.ok".loc) { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog("lcos.signing.confirm".loc, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if let pending {
                Button("lcos.signing.enable".loc) { configure(pending); self.pending = nil }
            }
            Button("lc.common.cancel".loc, role: .cancel) { pending = nil }
        } message: { Text("lcos.signing.trust".loc) }
    }
    private func reload() {
        guard let root else { return }
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        presets = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("preset.json")), data.count < 1_048_576 else { return nil }
            return try? JSONDecoder().decode(SigningInjectionPreset.self, from: data)
        }.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }
    private func removePreset(_ identifier: String) {
        guard let root else { return }
        do { try FileManager.default.removeItem(at: SigningInjectionPreset.directory(identifier, root: root)); reload() }
        catch { self.error = error.localizedDescription }
    }
    private func setEnabled(_ identifier: String, _ enabled: Bool) {
        guard let root else { return }
        do {
            guard var preset = try SigningInjectionPreset.read(identifier, root: root) else { return }
            preset.enabled = enabled; try preset.write(to: root); reload()
        } catch { self.error = error.localizedDescription }
    }
    private func inspect(_ url: URL) async {
        working = true; defer { working = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let identifier = target.trimmingCharacters(in: .whitespacesAndNewlines)
            try SigningInjectionPreset.validateTarget(identifier)
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: PackageLimits().archiveBytes + 1) ?? Data()
            guard data.count <= PackageLimits().archiveBytes else { throw SigningInjectionFailure.invalid("Injection file is too large") }
            let fileName = url.lastPathComponent
            pending = try await Task.detached(priority: .userInitiated) {
                if fileName.lowercased().hasSuffix(".deb") {
                    let plan = try TweakInstallPlan(package: DebianPackage(data: data), targetBundle: identifier)
                    let names = plan.binaries.keys.sorted()
                    let files = Dictionary(uniqueKeysWithValues: names.map { ($0, plan.files[$0]!) })
                    return Pending(target: identifier, files: files, libraries: names, name: plan.package.control["name"],
                        substrate: plan.binaries.values.contains { $0.dependencies.contains("@rpath/CydiaSubstrate.framework/CydiaSubstrate") })
                }
                guard fileName.lowercased().hasSuffix(".dylib") else { throw SigningInjectionFailure.invalid("Choose a .deb or .dylib file") }
                let (adapted, inspection) = try MachOInspection.inspectAndAdapt(data)
                return Pending(target: identifier, files: [fileName: adapted], libraries: [fileName], name: fileName,
                    substrate: inspection.dependencies.contains("@rpath/CydiaSubstrate.framework/CydiaSubstrate"))
            }.value
        } catch { self.error = error.localizedDescription }
    }
    private func configure(_ pending: Pending) {
        guard let root else { error = "Shared app group unavailable"; return }
        let substrateSource = Bundle.main.privateFrameworksURL?.appendingPathComponent("CydiaSubstrate.framework")
        working = true
        Task {
          defer { working = false }
          do {
            try await Task.detached(priority: .userInitiated) {
            let folder = SigningInjectionPreset.directory(pending.target, root: root)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var preset = try SigningInjectionPreset.read(pending.target, root: root)
                ?? SigningInjectionPreset(bundleIdentifier: pending.target, files: [], libraries: [], packageNames: [])
            for (name, bytes) in pending.files {
                let (_, inspection) = try MachOInspection.inspectAndAdapt(bytes)
                let version = ProcessInfo.processInfo.operatingSystemVersion
                let currentOS = UInt32(version.majorVersion << 16 | version.minorVersion << 8 | version.patchVersion)
                guard inspection.minimumOS <= currentOS else { throw SigningInjectionFailure.invalid("Library requires a newer iOS version") }
                let superseded = preset.libraries.filter { $0.hasSuffix("_" + name) }
                preset.libraries.removeAll { superseded.contains($0) }
                preset.files.removeAll { superseded.contains($0.path) }
                let name = String(PackageSHA256.hex(bytes).prefix(12)) + "_" + name
                guard !name.contains("/"), !name.contains("..") else { throw SigningInjectionFailure.invalid("Invalid library name") }
                try bytes.write(to: folder.appendingPathComponent(name), options: .atomic)
                if !preset.libraries.contains(name) { preset.libraries.append(name) }
                preset.files.removeAll { $0.path == name }
                preset.files.append(.init(path: name, sha256: PackageSHA256.hex(bytes)))
            }
            if pending.substrate {
                guard let source = substrateSource,
                      let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]) else {
                    throw SigningInjectionFailure.invalid("Bundled Substrate support is unavailable")
                }
                for case let file as URL in enumerator {
                    guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                    let relative = "CydiaSubstrate.framework/" + String(file.path.dropFirst(source.path.count + 1))
                    let target = folder.appendingPathComponent(relative)
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let bytes = try Data(contentsOf: file); try bytes.write(to: target, options: .atomic)
                    preset.files.removeAll { $0.path == relative }; preset.files.append(.init(path: relative, sha256: PackageSHA256.hex(bytes)))
                }
            }
            if !preset.packageNames.contains(pending.name) { preset.packageNames.append(pending.name) }
            preset.enabled = true; try preset.write(to: root)
            }.value
            reload()
          } catch { self.error = error.localizedDescription }
        }
    }
}
