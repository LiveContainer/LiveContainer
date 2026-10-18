import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LCDebPackageView: View {
    @EnvironmentObject private var shared: SharedModel
    @State private var selectedApp = ""
    @State private var importing = false
    @State private var working = false
    @State private var phase = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var plan: TweakInstallPlan?
    @State private var receipts: [PackageReceipt] = []
    @State private var enabled: Set<String> = []
    @State private var store: PackageStore?
    @State private var runtimeFolder = ""
    @State private var removal: PackageReceipt?
    @State private var trusted = false

    private var apps: [LCAppModel] {
        shared.apps.filter { !$0.uiIsShared && !$0.uiIsLocked && !$0.uiIs32bit &&
            !$0.bundleIdentifier.lowercased().contains("sidestore") &&
            !$0.bundleIdentifier.lowercased().contains("livecontainer") }
    }
    private var app: LCAppModel? { apps.first { $0.appInfo.relativeBundlePath == selectedApp } }

    var body: some View {
        List {
            Section {
                Picker("Guest application", selection: $selectedApp) {
                    Text("Select an app").tag("")
                    ForEach(apps, id: \.self) { app in
                        Text(app.displayName).tag(app.appInfo.relativeBundlePath ?? "")
                    }
                }
                Button { importing = true } label: { Label("Import .deb", systemImage: "square.and.arrow.down") }
                    .disabled(app == nil || working)
            } footer: {
                Text("Private, unlocked arm64 guests are supported in this first version. Quit the guest before changing its tweaks. Existing global tweaks are managed separately.")
            }
            if let plan {
                Section("Package inspection") {
                    Text(plan.package.control["name"].isEmpty ? plan.package.control["package"] : plan.package.control["name"])
                        .font(.headline)
                    Text("Version: \(plan.package.control["version"])")
                    Text("Architecture: \(plan.package.control["architecture"])")
                    Text("Layout: \(plan.package.layout)")
                    Text("Libraries: \(plan.binaries.keys.sorted().joined(separator: ", "))")
                    ForEach(plan.warnings, id: \.self) { warning in Text(warning).font(.footnote).foregroundStyle(.secondary) }
                    Toggle("I trust this package and its native code", isOn: $trusted)
                    Button("Install to App") { Task { await install(plan) } }
                        .disabled(!trusted || working)
                }
            }
            if working { Section { ProgressView(phase) } }
            if !phase.isEmpty && !working { Section { Text(phase).font(.footnote) } }
            Section("Installed packages for selected app") {
                ForEach(receipts) { receipt in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(receipt.name, isOn: Binding(get: { enabled.contains(receipt.id) }, set: { value in
                            Task { await changeEnabled(receipt, value: value) }
                        }))
                        Text("\(receipt.version) · \(receipt.origin) · \(receipt.signature)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Runtime: \(receipt.runtimeStatus). Confirm loading and behavior in the guest.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Uninstall", role: .destructive) { removal = receipt }
                    }
                    .disabled(working)
                }
            }
        }
        .navigationTitle("Debian Packages")
        .disabled(working)
        .task(id: selectedApp) { await selectGuest() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "deb") ?? .data]) { result in
            switch result {
            case .success(let url): Task { await inspect(url) }
            case .failure(let error): report(error)
            }
        }
        .alert("Package operation failed", isPresented: $showError) { Button("OK", role: .cancel) {} } message: { Text(errorMessage) }
        .confirmationDialog("Remove this package's files? Guest app data will be preserved.", isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            if let receipt = removal {
                Button("Uninstall \(receipt.name)", role: .destructive) { Task { await uninstall(receipt) } }
            }
            Button("Cancel", role: .cancel) { removal = nil }
        }
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        phase = "Failed: " + error.localizedDescription
    }

    private func selectGuest() async {
        plan = nil; trusted = false; receipts = []; enabled = []; store = nil; phase = ""
        guard let app else { return }
        let folder = app.uiTweakFolder.flatMap { $0.isEmpty ? nil : $0 } ?? "LCOS-\(UUID().uuidString)"
        let otherApps = shared.apps + shared.hiddenApps
        guard !otherApps.contains(where: { $0 != app && $0.uiTweakFolder == folder }) else {
            report(PackageFailure.invalid("This tweak folder is shared with another guest. Select an exclusive folder in app settings first.")); return
        }
        do {
            guard try DebianPackage.safePath(folder) == folder, !folder.contains("/"), !folder.hasSuffix(".disabled") else {
                throw PackageFailure.invalid("Select an enabled, exclusive tweak folder in app settings")
            }
            runtimeFolder = folder
            store = PackageStore(root: LCPath.tweakPath.resolvingSymlinksInPath().appendingPathComponent(folder))
            try await refresh()
        } catch { report(error) }
    }

    private func inspect(_ url: URL) async {
        guard let app, store != nil else { return }
        working = true; phase = "Validating archive and checking compatibility"; plan = nil; trusted = false
        defer { working = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let target = app.bundleIdentifier
            // Snapshot the import with a hard limit before handing it to a background parser.
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: PackageLimits().archiveBytes + 1) ?? Data()
            let prepared = try await Task.detached(priority: .userInitiated) {
                try TweakInstallPlan(package: DebianPackage(data: data), targetBundle: target)
            }.value
            let version = ProcessInfo.processInfo.operatingSystemVersion
            let packedOS = UInt32(version.majorVersion << 16 | version.minorVersion << 8 | version.patchVersion)
            guard prepared.binaries.values.allSatisfy({ $0.minimumOS <= packedOS }) else {
                throw PackageFailure.invalid("Tweak requires a newer iOS version")
            }
            plan = prepared
            phase = "Inspection complete. Native loading and hook behavior remain untested."
        } catch { report(error) }
    }

    private func install(_ plan: TweakInstallPlan) async {
        guard let app, let store, !working else { return }
        working = true; phase = "Signing libraries, verifying signatures and committing package"
        defer { working = false }
        do {
            guard !app.isAppRunning else { throw PackageFailure.invalid("Quit this guest before installing tweaks") }
            guard !app.appInfo.dontLoadTweakLoader && !app.appInfo.dontInjectTweakLoader else {
                throw PackageFailure.invalid("Enable TweakLoader injection in this guest's existing app settings first")
            }
            guard LCSharedUtils.certificatePassword() != nil else { throw PackageFailure.invalid("Import a valid signing certificate through the existing LiveContainer settings first") }
            let names = plan.binaries.keys.sorted()
            _ = try await store.install(plan, targetBundle: app.bundleIdentifier) { stage in
                let binaries = names.map { stage.appendingPathComponent($0) }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    LCUtils.signFilesWithZSign(with: binaries) { success, error in
                        if success { continuation.resume() }
                        else { continuation.resume(throwing: error ?? PackageFailure.invalid("ZSign failed without an error")) }
                    }
                }
                for binary in binaries {
                    guard checkCodeSignature((binary.path as NSString).utf8String) else {
                        throw PackageFailure.invalid("Signature verification failed: \(binary.lastPathComponent)")
                    }
                }
            }
            app.uiTweakFolder = runtimeFolder
            app.appInfo.save()
            if !shared.tweakFolderNames.contains(runtimeFolder) { shared.tweakFolderNames.append(runtimeFolder) }
            self.plan = nil
            try await refresh()
            phase = "Installed and signed. Launch the guest from Apps to test loading and behavior."
        } catch { report(error) }
    }

    private func refresh() async throws {
        guard let store else { return }
        let items = try await store.inventory()
        receipts = items.map { $0.0 }
        enabled = Set(items.filter { $0.1 }.map { $0.0.id })
    }
    private func changeEnabled(_ receipt: PackageReceipt, value: Bool) async {
        guard let store else { return }
        working = true
        defer { working = false }
        do {
            guard app?.isAppRunning != true else { throw PackageFailure.invalid("Quit this guest before changing tweaks") }
            try await store.setEnabled(receipt.id, enabled: value)
            try await refresh()
        } catch { report(error) }
    }
    private func uninstall(_ receipt: PackageReceipt) async {
        guard let store else { return }
        working = true; removal = nil
        defer { working = false }
        do {
            guard app?.isAppRunning != true else { throw PackageFailure.invalid("Quit this guest before removing tweaks") }
            try await store.remove(receipt.id, enabled: enabled.contains(receipt.id))
            try await refresh()
        } catch { report(error) }
    }
}
