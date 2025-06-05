import SwiftUI

struct AltStoreVersion: Codable {
    let version: String?
    let downloadURL: String?
}

struct AltStoreApp: Codable, Identifiable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let developerName: String?
    let subtitle: String?
    let iconURL: String?
    let versions: [AltStoreVersion]?
    let version: String?
    let downloadURL: String?

    var latestDownloadURL: String? {
        if let versions, let first = versions.first {
            return first.downloadURL
        }
        return downloadURL
    }
}

struct AltStoreSource: Codable {
    let name: String
    let identifier: String
    let apps: [AltStoreApp]
}

struct AltStoreAppBanner: View {
    let app: AltStoreApp
    @EnvironmentObject var model: SharedModel

    var body: some View {
        HStack {
            if let icon = app.iconURL, let url = URL(string: icon) {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
            }

            VStack(alignment: .leading) {
                Text(app.name)
                    .font(.system(size: 16).bold())
                if let subtitle = app.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color("FontColor"))
                }
            }

            Spacer()

            if let download = app.latestDownloadURL,
               let encoded = download.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let dlUrl = URL(string: "livecontainer://install?url=\(encoded)") {
                Button {
                    UIApplication.shared.open(dlUrl)
                    model.selectedTab = 1
                } label: {
                    Text("Download")
                        .bold()
                        .foregroundColor(.white)
                        .frame(height: 32)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(BasicButtonStyle())
                .background(Capsule().fill(Color("FontColor")))
                .padding()
            }
        }
        .padding()
        .frame(height: 88)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color("AppBannerBG"))
        )
    }
}

struct LCSourcesView: View {
    @State private var sourceURLs: [String] = []
    @State private var sources: [String: AltStoreSource] = [:]
    @State private var loadingSources: Set<String> = []
    @State private var error: String?

    @StateObject private var addSourceInput = InputHelper()

    private let defaultSource = "https://raw.githubusercontent.com/LiveContainer/LiveContainer/main/apps.json"

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sourceURLs, id: \.self) { url in
                        if let source = sources[url] {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(source.name)
                                        .font(.system(.title2).bold())
                                    Spacer()
                                    Menu {
                                        Button(role: .destructive) {
                                            removeSource(url: url)
                                        } label: {
                                            Label("lc.common.delete".loc, systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title3)
                                    }
                                }

                                ForEach(source.apps) { app in
                                    AltStoreAppBanner(app: app)
                                }
                            }
                        } else if loadingSources.contains(url) {
                            ProgressView()
                                .padding()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("lc.tabView.sources".loc)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { if let new = await addSourceInput.open(), !new.isEmpty { addSource(url: new) } } }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .textFieldAlert(
                isPresented: $addSourceInput.show,
                title: "Enter Source URL",
                text: $addSourceInput.initVal,
                placeholder: "https://",
                action: { addSourceInput.close(result: $0) },
                actionCancel: { _ in addSourceInput.close(result: nil) }
            )
            .onAppear {
                if sourceURLs.isEmpty { loadSourceList() }
            }
            .alert(isPresented: Binding<Bool>(get: { error != nil }, set: { _ in error = nil })) {
                Alert(title: Text("Error"), message: Text(error ?? ""), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func loadSourceList() {
        sourceURLs = UserDefaults.standard.stringArray(forKey: "LCSources") ?? [defaultSource]
        for url in sourceURLs {
            loadCachedSource(url: url)
            fetchSource(url: url)
        }
    }

    private func saveSourceList() {
        UserDefaults.standard.set(sourceURLs, forKey: "LCSources")
    }

    private func cachePath(for url: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folder = caches.appendingPathComponent("LCSources", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let name = Data(url.utf8).base64EncodedString()
        return folder.appendingPathComponent(name)
    }

    private func loadCachedSource(url: String) {
        let path = cachePath(for: url)
        if let data = try? Data(contentsOf: path),
           let src = try? JSONDecoder().decode(AltStoreSource.self, from: data) {
            self.sources[url] = src
        }
    }

    private func saveCachedSource(url: String, data: Data) {
        let path = cachePath(for: url)
        try? data.write(to: path)
    }

    private func fetchSource(url: String) {
        guard let u = URL(string: url) else { return }
        loadingSources.insert(url)
        Task {
            do {
                let data = try Data(contentsOf: u)
                let src = try JSONDecoder().decode(AltStoreSource.self, from: data)
                await MainActor.run {
                    self.sources[url] = src
                    self.saveCachedSource(url: url, data: data)
                    self.loadingSources.remove(url)
                }
            } catch {
                await MainActor.run {
                    if self.sources[url] == nil {
                        self.error = error.localizedDescription
                    }
                    self.loadingSources.remove(url)
                }
            }
        }
    }

    private func addSource(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !sourceURLs.contains(trimmed) {
            sourceURLs.append(trimmed)
            saveSourceList()
            fetchSource(url: trimmed)
        }
    }

    private func removeSource(url: String) {
        sourceURLs.removeAll { $0 == url }
        sources.removeValue(forKey: url)
        let path = cachePath(for: url)
        try? FileManager.default.removeItem(at: path)
        saveSourceList()
    }
}
