import SwiftUI

struct AltStoreVersion: Codable {
    let version: String?
    let date: String?
    let downloadURL: String?
    let localizedDescription: String?
    let size: Int?
    let absoluteVersion: String?
}

struct AltStoreAppPermissions: Codable {
    let entitlements: [String]?
    let privacy: [String: String]?
}

struct AltStoreApp: Codable, Identifiable {
    var id: String { appID ?? bundleIdentifier ?? name }
    var name: String = ""
    var bundleIdentifier: String?
    var developerName: String?
    var subtitle: String?
    var iconURL: String?
    var tintColor: String?
    var screenshotURLs: [String]?
    var localizedDescription: String?
    var appPermissions: AltStoreAppPermissions?
    var versions: [AltStoreVersion]?
    var version: String?
    var versionDate: String?
    var versionDescription: String?
    var downloadURL: String?
    var absoluteVersion: String?
    var appID: String?
    var size: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case bundleIdentifier
        case developerName
        case subtitle
        case iconURL
        case tintColor
        case screenshotURLs
        case localizedDescription
        case appPermissions
        case versions
        case version
        case versionDate
        case versionDescription
        case downloadURL
        case absoluteVersion
        case appID
        case size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        bundleIdentifier = try? container.decode(String.self, forKey: .bundleIdentifier)
        developerName = try? container.decode(String.self, forKey: .developerName)
        subtitle = try? container.decode(String.self, forKey: .subtitle)
        iconURL = try? container.decode(String.self, forKey: .iconURL)
        tintColor = try? container.decode(String.self, forKey: .tintColor)
        screenshotURLs = try? container.decode([String].self, forKey: .screenshotURLs)
        localizedDescription = try? container.decode(String.self, forKey: .localizedDescription)
        appPermissions = try? container.decode(AltStoreAppPermissions.self, forKey: .appPermissions)
        versions = try? container.decode([AltStoreVersion].self, forKey: .versions)
        version = try? container.decode(String.self, forKey: .version)
        versionDate = try? container.decode(String.self, forKey: .versionDate)
        versionDescription = try? container.decode(String.self, forKey: .versionDescription)
        downloadURL = try? container.decode(String.self, forKey: .downloadURL)
        absoluteVersion = try? container.decode(String.self, forKey: .absoluteVersion)
        appID = try? container.decode(String.self, forKey: .appID)
        if let intVal = try? container.decodeIfPresent(Int.self, forKey: .size) {
            size = intVal
        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .size),
                  let intVal = Int(strVal) {
            size = intVal
        }
    }

    var latestDownloadURL: String? {
        if let versions, let first = versions.first {
            return first.downloadURL
        }
        return downloadURL
    }
}

struct AltStoreSource: Decodable {
    let name: String
    let identifier: String
    let version: Int?
    let apiVersion: String?
    let apps: [AltStoreApp]

    enum CodingKeys: String, CodingKey {
        case name
        case identifier
        case version
        case apiVersion
        case apps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        identifier = try container.decode(String.self, forKey: .identifier)
        version = try? container.decode(Int.self, forKey: .version)
        apiVersion = try? container.decode(String.self, forKey: .apiVersion)
        if let appArray = try? container.decode([AltStoreApp].self, forKey: .apps) {
            apps = appArray
        } else if let appDict = try? container.decode([String: AltStoreApp].self, forKey: .apps) {
            apps = appDict.map { key, value in
                var app = value
                if app.appID == nil { app.appID = key }
                if app.bundleIdentifier == nil { app.bundleIdentifier = key }
                return app
            }
        } else {
            throw DecodingError.dataCorruptedError(forKey: .apps, in: container, debugDescription: "Unsupported apps format")
        }
    }
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
                        self.removeSource(url: url)
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
