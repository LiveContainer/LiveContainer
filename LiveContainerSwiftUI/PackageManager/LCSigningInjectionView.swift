import SwiftUI
import UniformTypeIdentifiers

struct LCSigningInjectionView: View {
    let target: String
    let appName: String
    let finish: (Bool) -> Void
    @State private var presets: [SigningInjectionPreset] = []
    @State private var importing = false
    @State private var working = false
    @State private var error: String?
    @State private var pending: Pending?
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
                Text(appName).font(.headline)
                Text(target).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button { importing = true } label: { Label("lcos.signing.import".signingLoc, systemImage: "doc.badge.plus") }
                    .disabled(working || target.isEmpty)
            } header: { Text("SideStore") } footer: { Text("lcos.signing.installDescription".signingLoc) }
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
                        Button(role: .destructive) { removePreset(preset.bundleIdentifier) } label: { Label("lc.common.delete".signingLoc, systemImage: "trash") }
                    }
                }
                if presets.isEmpty { Text("lcos.signing.empty".signingLoc).foregroundStyle(.secondary) }
            } header: { Text("lcos.signing.configured".signingLoc) }
            if working { ProgressView() }
        }
        .lcSoftScrollEdges()
        .navigationTitle("lcos.signing.title".signingLoc)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("lc.common.cancel".signingLoc) { finish(false) }.disabled(working)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("lcos.signing.continueInstall".signingLoc) { finish(true) }.disabled(working || pending != nil)
            }
        }
        .task { reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { Task { await inspect(url) } } }
            catch { self.error = error.localizedDescription }
        }
        .alert("lc.common.error".signingLoc, isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("lc.common.ok".signingLoc) { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog("lcos.signing.confirm".signingLoc, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if let pending {
                Button("lcos.signing.enable".signingLoc) { configure(pending); self.pending = nil }
            }
            Button("lc.common.cancel".signingLoc, role: .cancel) { pending = nil }
        } message: { Text("lcos.signing.trust".signingLoc) }
    }
    private func reload() {
        guard let root else { return }
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        presets = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("preset.json")), data.count < 1_048_576 else { return nil }
            guard let preset = try? JSONDecoder().decode(SigningInjectionPreset.self, from: data),
                  preset.bundleIdentifier == target else { return nil }
            return preset
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
        let substrateSource = Bundle(for: LCOSSigningInjectionPresenter.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("CydiaSubstrate.framework")
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
                let source = substrateSource
                guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]) else {
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

/// Runtime boundary used by the embedded SideStore, which cannot link the LC SwiftUI module directly.
@objc(LCOSSigningInjectionPresenter)
final class LCOSSigningInjectionPresenter: NSObject {
    @MainActor
    @objc(configureBundleIdentifier:appName:presenter:completion:)
    static func configure(bundleIdentifier: String, appName: String, presenter: UIViewController,
                          completion: @escaping (Bool) -> Void) {
        guard #available(iOS 16.1, *), presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil else { completion(false); return }
        var completed = false
        weak var sheet: UIViewController?
        let content = NavigationView {
            LCSigningInjectionView(target: bundleIdentifier, appName: appName) { accepted in
                guard !completed else { return }
                completed = true
                sheet?.dismiss(animated: true) { completion(accepted) }
            }
        }.navigationViewStyle(.stack)
        let controller = UIHostingController(rootView: content)
        controller.isModalInPresentation = true
        controller.modalPresentationStyle = .pageSheet
        sheet = controller
        presenter.present(controller, animated: true)
    }
}

private extension String {
    var signingLoc: String {
        // Bundle.main belongs to SideStore while this view is presented there.
        let url = Bundle(for: LCOSSigningInjectionPresenter.self).bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let host = Bundle(url: url) ?? .main
        let value = host.localizedString(forKey: self, value: nil, table: nil)
        if value != self { return value }
        if let path = host.path(forResource: "en", ofType: "lproj"), let english = Bundle(path: path) {
            return english.localizedString(forKey: self, value: self, table: nil)
        }
        return self
    }
}
