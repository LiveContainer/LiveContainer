//
//  LCAltStoreSourcesView.swift
//  LiveContainerSwiftUI
//
//  Created by Stephen B on 2025/2/15.
//

import Foundation
import SwiftUI
import UIKit
import CryptoKit

struct AltStoreSourceAppVersion: Identifiable, Hashable {
    let id = UUID()
    let version: String
    let buildVersion: String?
    let releaseDate: Date?
    let localizedDescription: String?
    let downloadURL: URL
    let size: Int64?
}

struct AltStoreSourceApp: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String
    let developerName: String?
    let subtitle: String?
    let description: String?
    let iconURL: URL?
    let tintColor: Color?
    let screenshots: [URL]
    let versions: [AltStoreSourceAppVersion]
    let latestVersion: AltStoreSourceAppVersion?
    let isBeta: Bool
}

struct AltStoreSource: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let identifier: String?
    let subtitle: String?
    let description: String?
    let iconURL: URL?
    let headerURL: URL?
    let tintColor: Color?
    let website: URL?
    let apps: [AltStoreSourceApp]
}

private struct AltStoreSourceResponse: Decodable {
    let name: String?
    let identifier: String?
    let subtitle: String?
    let description: String?
    let iconURL: String?
    let headerURL: String?
    let tintColor: String?
    let website: String?
    let apps: [AltStoreSourceAppResponse]?
}

private struct AltStoreSourceAppResponse: Decodable {
    let beta: Bool?
    let name: String?
    let bundleIdentifier: String?
    let developerName: String?
    let subtitle: String?
    let version: String?
    let versionDate: String?
    let versionDescription: String?
    let downloadURL: String?
    let localizedDescription: String?
    let iconURL: String?
    let tintColor: String?
    let screenshotURLs: [String]?
    let versions: [AltStoreSourceAppVersionResponse]?
    
    enum CodingKeys: String, CodingKey {
        case beta
        case name
        case bundleIdentifier
        case developerName
        case subtitle
        case version
        case versionDate
        case versionDescription
        case downloadURL
        case localizedDescription
        case iconURL
        case tintColor
        case screenshotURLs
        case versions
    }
}

private struct AltStoreSourceAppVersionResponse: Decodable {
    let version: String?
    let buildVersion: String?
    let date: String?
    let localizedDescription: String?
    let downloadURL: String?
    let size: Int64?
    
    enum CodingKeys: String, CodingKey {
        case version
        case buildVersion = "buildNumber"
        case date
        case localizedDescription
        case downloadURL
        case size
    }
}

@MainActor
final class AltStoreSourcesViewModel: ObservableObject {
    struct SourceItem: Identifiable, Hashable {
        let id: URL
        let url: URL
        var source: AltStoreSource?
        var isLoading: Bool
        var error: String?
        
        init(url: URL, isLoading: Bool = false, source: AltStoreSource? = nil, error: String? = nil) {
            self.url = url
            self.id = url
            self.isLoading = isLoading
            self.source = source
            self.error = error
        }
        
        var displayName: String {
            if let source {
                return source.name
            }
            if let host = url.host, !host.isEmpty {
                return host
            }
            return url.absoluteString
        }
        
        var primaryIconURL: URL? {
            if let icon = source?.iconURL {
                return icon
            }
            if let appIcon = source?.apps.first(where: { $0.iconURL != nil })?.iconURL {
                return appIcon
            }
            return nil
        }
    }
    
    @Published private(set) var sources: [SourceItem] = []
    @Published var isRefreshingAll = false
    private let defaultsKey = "LCAltStoreSourceURLs"

    private let cacheDirectoryName = "AltStoreSourceCache"
    
    init() {
        loadStoredSources()
        Task {
            await refreshAllSources()
        }
    }
    
    func addSource(from rawValue: String) async -> String? {
        guard let normalizedURL = normalizeSourceURL(from: rawValue) else {
            return "lc.sources.error.invalidUrl".loc
        }
        
        if sources.contains(where: { $0.url == normalizedURL }) {
            return "lc.sources.error.duplicate".loc
        }
        
        sources.append(SourceItem(url: normalizedURL, isLoading: true))
        persistSources()
        await refreshSource(url: normalizedURL)
        return nil
    }
    
    func removeSource(_ item: SourceItem) {
        sources.removeAll { $0.id == item.id }
        persistSources()
        removeCache(for: item.url)
    }
    
    func refreshSource(_ item: SourceItem) async {
        await refreshSource(url: item.url)
    }
    
    func refreshAllSources() async {
        guard !sources.isEmpty else {
            return
        }
        isRefreshingAll = true
        for url in sources.map({ $0.url }) {
            await refreshSource(url: url)
        }
        isRefreshingAll = false
    }
    
    private func refreshSource(url: URL) async {
        guard let index = sources.firstIndex(where: { $0.url == url }) else {
            return
        }
        sources[index].isLoading = true
        sources[index].error = nil
        let previousData = cachedData(for: url)
        do {
            let (source, data) = try await AltStoreSourceLoader.load(from: url)
            guard let sourceIndex = sources.firstIndex(where: { $0.url == url }) else {
                return
            }
            if let previousData, previousData == data {
                sources[sourceIndex].isLoading = false
                return
            }
            sources[sourceIndex].source = source
            sources[sourceIndex].isLoading = false
            storeCache(data, for: url)
        } catch {
            if let sourceIndex = sources.firstIndex(where: { $0.url == url }) {
                sources[sourceIndex].error = error.localizedDescription
                sources[sourceIndex].isLoading = false
            }
        }
    }
    
    private func loadStoredSources() {
        let defaults = UserDefaults.standard
        let stored = defaults.array(forKey: defaultsKey) as? [String] ?? []
        let urls = stored.compactMap { URL(string: $0) }
        self.sources = urls.map { SourceItem(url: $0, isLoading: false) }
        for index in sources.indices {
            let url = sources[index].url
            if let data = cachedData(for: url),
               let cachedSource = try? AltStoreSourceLoader.decode(from: data, baseURL: url) {
                sources[index].source = cachedSource
            }
        }
    }
    
    private func persistSources() {
        let urls = sources.map { $0.url.absoluteString }
        UserDefaults.standard.set(urls, forKey: defaultsKey)
    }
    
    private func normalizeSourceURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        if let httpsURL = URL(string: "https://\(trimmed)") {
            return httpsURL
        }
        return nil
    }
}

private extension AltStoreSourcesViewModel {
    func cachedData(for url: URL) -> Data? {
        guard let fileURL = cacheFileURL(for: url) else { return nil }
        return try? Data(contentsOf: fileURL)
    }
    
    func storeCache(_ data: Data, for url: URL) {
        guard let fileURL = cacheFileURL(for: url) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Ignore cache write errors
        }
    }
    
    func cacheFileURL(for url: URL) -> URL? {
        guard let directory = ensureCacheDirectory() else { return nil }
        let fileName = cacheFileName(for: url)
        return directory.appendingPathComponent(fileName)
    }
    
    func ensureCacheDirectory() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }
        return directory
    }
    
    func cacheFileName(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).json"
    }
    
    func removeCache(for url: URL) {
        guard let fileURL = cacheFileURL(for: url) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            // Ignore cache removal errors
        }
    }
}

enum AltStoreSourceLoader {
    static func load(from url: URL) async throws -> (AltStoreSource, Data) {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw NSError(domain: "AltStoreSource", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
        }
        let source = try decode(from: data, baseURL: url)
        return (source, data)
    }
    
    static func decode(from data: Data, baseURL: URL) throws -> AltStoreSource {
        try decodeSource(from: data, baseURL: baseURL)
    }
    
    private static func decodeSource(from data: Data, baseURL: URL) throws -> AltStoreSource {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom({ decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let isoDate = ISO8601DateFormatter().date(from: rawValue) {
                return isoDate
            }
            let shortFormatter = DateFormatter()
            shortFormatter.dateFormat = "yyyy-MM-dd"
            if let shortDate = shortFormatter.date(from: rawValue) {
                return shortDate
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(rawValue)")
        })
        
        let response = try decoder.decode(AltStoreSourceResponse.self, from: data)
        guard let name = response.name else {
            throw NSError(domain: "AltStoreSource", code: 0, userInfo: [NSLocalizedDescriptionKey: "lc.sources.error.malformed".loc])
        }
        let apps = (response.apps ?? []).compactMap { appResponse in
            buildApp(from: appResponse, baseURL: baseURL, fallbackTint: response.tintColor)
        }
        return AltStoreSource(
            name: name,
            identifier: response.identifier,
            subtitle: response.subtitle,
            description: response.description,
            iconURL: url(for: response.iconURL, baseURL: baseURL),
            headerURL: url(for: response.headerURL, baseURL: baseURL),
            tintColor: color(from: response.tintColor),
            website: url(for: response.website, baseURL: baseURL),
            apps: apps
        )
    }
    
    private static func buildApp(from response: AltStoreSourceAppResponse, baseURL: URL, fallbackTint: String?) -> AltStoreSourceApp? {
        guard let name = response.name,
              let bundleIdentifier = response.bundleIdentifier else {
            return nil
        }
        
        let versions = buildVersions(from: response, baseURL: baseURL)
        let latest = versions.first ?? buildLegacyVersion(from: response, baseURL: baseURL)
        
        return AltStoreSourceApp(
            name: name,
            bundleIdentifier: bundleIdentifier,
            developerName: response.developerName,
            subtitle: response.subtitle,
            description: response.localizedDescription ?? response.versionDescription,
            iconURL: url(for: response.iconURL, baseURL: baseURL),
            tintColor: color(from: response.tintColor ?? fallbackTint),
            screenshots: (response.screenshotURLs ?? []).compactMap { url(for: $0, baseURL: baseURL) },
            versions: versions,
            latestVersion: latest,
            isBeta: response.beta ?? false
        )
    }
    
    private static func buildVersions(from response: AltStoreSourceAppResponse, baseURL: URL) -> [AltStoreSourceAppVersion] {
        guard let versions = response.versions else { return [] }
        return versions.compactMap { version in
            guard let versionString = version.version,
                  let downloadURLString = version.downloadURL,
                  let downloadURL = url(for: downloadURLString, baseURL: baseURL) else {
                return nil
            }
            return AltStoreSourceAppVersion(
                version: versionString,
                buildVersion: version.buildVersion,
                releaseDate: parseDate(version.date),
                localizedDescription: version.localizedDescription,
                downloadURL: downloadURL,
                size: version.size
            )
        }
    }
    
    private static func buildLegacyVersion(from response: AltStoreSourceAppResponse, baseURL: URL) -> AltStoreSourceAppVersion? {
        guard let versionString = response.version,
              let downloadURLString = response.downloadURL,
              let downloadURL = url(for: downloadURLString, baseURL: baseURL) else {
            return nil
        }
        return AltStoreSourceAppVersion(
            version: versionString,
            buildVersion: nil,
            releaseDate: parseDate(response.versionDate),
            localizedDescription: response.versionDescription ?? response.localizedDescription,
            downloadURL: downloadURL,
            size: nil
        )
    }
    
    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let isoDate = ISO8601DateFormatter().date(from: value) {
            return isoDate
        }
        let shortFormatter = DateFormatter()
        shortFormatter.dateFormat = "yyyy-MM-dd"
        return shortFormatter.date(from: value)
    }
    
    private static func url(for string: String?, baseURL: URL) -> URL? {
        guard let string = string, !string.isEmpty else { return nil }
        if let absoluteURL = URL(string: string), absoluteURL.scheme != nil {
            return absoluteURL
        }
        return URL(string: string, relativeTo: baseURL)?.absoluteURL
    }
    
    private static func color(from hex: String?) -> Color? {
        guard let hex = hex else { return nil }
        return Color(hexString: hex)
    }
}

private extension Color {
    init?(hexString: String) {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")
        
        if cleaned.count == 3 {
            var expanded = ""
            for character in cleaned {
                expanded.append(character)
                expanded.append(character)
            }
            cleaned = expanded
        }
        
        if cleaned.count == 6 {
            cleaned.append("FF")
        }
        
        guard cleaned.count == 8,
              let value = UInt64(cleaned, radix: 16) else {
            return nil
        }
        
        let red = Double((value & 0xFF00_0000) >> 24) / 255.0
        let green = Double((value & 0x00FF_0000) >> 16) / 255.0
        let blue = Double((value & 0x0000_FF00) >> 8) / 255.0
        let alpha = Double(value & 0x0000_00FF) / 255.0
        
        self = Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct LCSourcesView: View {
    @StateObject private var viewModel = AltStoreSourcesViewModel()
    @State private var errorMessage: String?
    @State private var sourcePendingRemoval: AltStoreSourcesViewModel.SourceItem?
    @ObservedObject public var searchContext = SearchContext()
    @State private var expandedSources: Set<URL> = []
    @State private var isManagingSources = false
    
    @EnvironmentObject private var sharedModel : SharedModel
    
    @State private var isViewAppeared = false
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.sources.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("lc.sources.empty".loc)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.sources, id: \.id) { item in
                                let apps = filteredApps(for: item)
                                AltStoreSourceSectionView(
                                    item: item,
                                    filteredApps: apps,
                                    isFiltering: isFiltering,
                                    isExpanded: expandedSources.contains(item.id),
                                    onRefresh: { Task { await viewModel.refreshSource(item) } },
                                    onInstall: install(app:),
                                    onRemove: { sourcePendingRemoval = item },
                                    toggleExpanded: { toggleExpansion(for: item.id) }
                                )
                                .padding(.horizontal)
                                .animation(.easeInOut, value: apps.count)
                            }
                            
                            if totalFilteredAppCount == 0 {
                                VStack(spacing: 8) {
                                    Text("lc.sources.section.noApps".loc)
                                        .foregroundStyle(.gray)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 160, alignment: .center)
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("lc.tabView.sources".loc)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isRefreshingAll {
                        ProgressView()
                    } else {
                        Button("lc.sources.refreshAll".loc, systemImage: "arrow.clockwise") {
                            Task { await viewModel.refreshAllSources() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("lc.sources.addSource".loc, systemImage: "plus") {
                        isManagingSources = true
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .alert("lc.common.error".loc, isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })
        ) {
            Button("lc.common.ok".loc, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("lc.sources.removeConfirmation.title".loc, isPresented: Binding(
            get: { sourcePendingRemoval != nil },
            set: { if !$0 { sourcePendingRemoval = nil } })
        ) {
            Button("lc.common.remove".loc, role: .destructive) {
                if let sourcePendingRemoval {
                    viewModel.removeSource(sourcePendingRemoval)
                }
                sourcePendingRemoval = nil
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                sourcePendingRemoval = nil
            }
        } message: {
            if let name = sourcePendingRemoval?.displayName {
                Text("lc.sources.removeConfirmation.message %@".localizeWithFormat(name))
            } else {
                Text("lc.sources.removeConfirmation.message %@".localizeWithFormat(""))
            }
        }
        .sheet(isPresented: $isManagingSources) {
            if #available(iOS 16.0, *) {
                ManageSourcesSheet(
                    viewModel: viewModel,
                    isPresented: $isManagingSources,
                    onAdd: { rawValue in
                        await handleAddSource(rawValue)
                    }
                )
                .presentationDetents([.large])
            } else {
                ManageSourcesSheet(
                    viewModel: viewModel,
                    isPresented: $isManagingSources,
                    onAdd: { rawValue in
                        await handleAddSource(rawValue)
                    }
                )
            }
        }
        .apply {
            if #available(iOS 19.0, *), SharedModel.isLiquidGlassSearchEnabled {
                $0
            } else {
                $0.searchable(text: $searchContext.query)
            }
        }
        .onAppear {
            expandedSources = []
            if !isViewAppeared {
                guard sharedModel.selectedTab == .sources, let link = sharedModel.deepLink else { return }
                sharedModel.deepLink = nil
                handleURL(url: link)
                isViewAppeared = true
            }
        }
        .onChange(of: viewModel.sources) { newSources in
            let newSet = Set(newSources.map { $0.id })
            expandedSources = expandedSources.intersection(newSet)
        }
        .onChange(of: sharedModel.deepLink) { link in
            guard sharedModel.selectedTab == .sources, let link else { return }
            sharedModel.deepLink = nil
            handleURL(url: link)
        }
    }
    
    private var isFiltering: Bool {
        !searchContext.debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var totalFilteredAppCount: Int {
        viewModel.sources.reduce(0) { partialResult, item in
            partialResult + filteredApps(for: item).count
        }
    }
    
    private func filteredApps(for item: AltStoreSourcesViewModel.SourceItem) -> [AltStoreSourceApp] {
        guard let source = item.source else { return [] }
        let query = searchContext.debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return source.apps
        }
        return source.apps.filter { app in
            let lower = query.lowercased()
            if app.name.lowercased().contains(lower) {
                return true
            }
            if app.bundleIdentifier.lowercased().contains(lower) {
                return true
            }
            if let developer = app.developerName?.lowercased(), developer.contains(lower) {
                return true
            }
            if let subtitle = app.subtitle?.lowercased(), subtitle.contains(lower) {
                return true
            }
            return false
        }
    }
    
    @MainActor
    private func handleAddSource(_ rawValue: String) async -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let error = await viewModel.addSource(from: trimmed)
        if let error {
            errorMessage = error
            return false
        }
        return true
    }
    
    @MainActor
    private func install(app: AltStoreSourceApp) {
        guard let downloadURL = app.latestVersion?.downloadURL else {
            errorMessage = "lc.sources.error.missingDownload".loc
            return
        }
        withAnimation {
            DataManager.shared.model.selectedTab = .apps
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: NSNotification.InstallAppNotification, object: ["url": downloadURL])
        }


    }
    
    private func toggleExpansion(for id: URL) {
        withAnimation(.easeInOut) {
            if expandedSources.contains(id) {
                expandedSources.remove(id)
            } else {
                expandedSources.insert(id)
            }
        }
    }
    
    func handleURL(url : URL) {
        if url.host == "source" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var sourceUrl : String? = nil
                for queryItem in components.queryItems ?? [] {
                    if queryItem.name == "url", let installUrl1 = queryItem.value {
                        sourceUrl = installUrl1
                    }
                }
                if let sourceUrl {
                    DataManager.shared.model.selectedTab = .sources
                    Task { await handleAddSource(sourceUrl) }
                }
            }
        }
    }
}

private struct ManageSourcesSheet: View {
    @ObservedObject var viewModel: AltStoreSourcesViewModel
    @Binding var isPresented: Bool
    let onAdd: (String) async -> Bool
    
    @State private var manualSourceValue = ""
    @State private var isAddingManual = false
    @State private var sourcePendingRemoval: AltStoreSourcesViewModel.SourceItem?
    @FocusState private var isManualFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    if viewModel.sources.isEmpty {
                        Text("lc.sources.empty".loc)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.sources, id: \.id) { item in
                            HStack(alignment: .top, spacing: 12) {
                                SourceIconView(url: resolvedIconURL(for: item))
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.displayName)
                                        .bold()
                                    Text(item.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    sourcePendingRemoval = item
                                } label: {
                                    Label("lc.sources.removeSource".loc, systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("lc.sources.manage.current".loc)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("https://example.com/source.json", text: $manualSourceValue)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($isManualFieldFocused)
                        
                        Button {
                            attemptManualAdd()
                        } label: {
                            if isAddingManual {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("lc.sources.addSource".loc)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualSourceValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingManual)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("lc.sources.manage.manual".loc)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("lc.sources.addSource".loc)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("lc.common.close".loc) {
                        isPresented = false
                    }
                }
            }
        }
        .confirmationDialog(
            "lc.sources.removeConfirmation.title".loc,
            isPresented: Binding<Bool>(
                get: { sourcePendingRemoval != nil },
                set: { if !$0 { sourcePendingRemoval = nil } }
            ),
            presenting: sourcePendingRemoval
        ) { item in
            Button("lc.common.remove".loc, role: .destructive) {
                viewModel.removeSource(item)
                sourcePendingRemoval = nil
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                sourcePendingRemoval = nil
            }
        } message: { item in
            Text("lc.sources.removeConfirmation.message %@".localizeWithFormat(item.displayName))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func resolvedIconURL(for item: AltStoreSourcesViewModel.SourceItem) -> URL? {
        if let icon = item.primaryIconURL {
            return icon
        }
        if let existing = viewModel.sources.first(where: { $0.url == item.url }) {
            if let icon = existing.primaryIconURL {
                return icon
            }
        }
        return nil
    }
    
    private func attemptManualAdd() {
        let trimmed = manualSourceValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAddingManual else { return }
        isAddingManual = true
        Task {
            let success = await onAdd(trimmed)
            if success {
                manualSourceValue = ""
                isManualFieldFocused = false
            }
            isAddingManual = false
        }
    }
}

private struct AltStoreSourceSectionView: View {
    let item: AltStoreSourcesViewModel.SourceItem
    let filteredApps: [AltStoreSourceApp]
    let isFiltering: Bool
    let isExpanded: Bool
    let onRefresh: () -> Void
    let onInstall: (AltStoreSourceApp) -> Void
    let onRemove: () -> Void
    let toggleExpanded: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundStyle(.secondary)
                        SourceIconView(url: item.primaryIconURL)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(item.source?.name ?? item.displayName)
                            .font(.system(.title2).bold())
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if item.isLoading {
                    ProgressView()
                } else {
                    Menu {
                        Button("lc.sources.refresh".loc, systemImage: "arrow.clockwise", action: onRefresh)
                        Button("lc.sources.removeSource".loc, systemImage: "trash", role: .destructive, action: onRemove)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let subtitle = item.source?.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if item.source == nil, let host = item.url.host {
                Text(host)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            if let error = item.error {
                VStack(alignment: .leading, spacing: 6) {
                    Text("lc.sources.section.error".loc)
                        .font(.subheadline)
                        .bold()
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("lc.sources.refresh".loc, action: onRefresh)
                        .font(.footnote)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(uiColor: UIColor.secondarySystemBackground))
                )
            } else if let source = item.source, isExpanded || isFiltering {
                VStack(spacing: 12) {
                    ForEach(filteredApps[0..<min(50, filteredApps.count)]) { app in
                        LCSourceAppBanner(app: app, source: source, installAction: onInstall)
                    }
                    if filteredApps.isEmpty {
                        if source.apps.isEmpty || isFiltering {
                            Text("lc.sources.section.noApps".loc)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if filteredApps.count > 50 {
                        Text("lc.sources.section.tooManyApps".loc)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if item.isLoading {
                ProgressView("lc.sources.loading".loc)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct LCSourceAppBanner: View {
    let app: AltStoreSourceApp
    let source: AltStoreSource
    let installAction: (AltStoreSourceApp) -> Void
    
    @AppStorage("dynamicColors") private var dynamicColors = true
    @Environment(\.colorScheme) var colorScheme
    
    private var primaryColor: Color {
        guard dynamicColors else { return Color("FontColor") }
        return app.tintColor ?? source.tintColor ?? Color("FontColor")
    }
    
    private var textColor: Color {
        _ = colorScheme == .dark // trigger refresh
        let color = dynamicColors ? primaryColor : Color("FontColor")
        return color.readableTextColor()
    }
    
    private var backgroundColor: Color {
        dynamicColors ? primaryColor.opacity(0.5) : Color("AppBannerBG")
    }
    
    private var metadataText: String {
        guard let latest = app.latestVersion else {
            return app.bundleIdentifier
        }
        if let build = latest.buildVersion, !build.isEmpty {
            return "\(latest.version) (\(build)) • \(app.bundleIdentifier)"
        }
        return "\(latest.version) • \(app.bundleIdentifier)"
    }
    
    private var subtitleText: String {
        if let subtitle = app.subtitle, !subtitle.isEmpty {
            return subtitle
        }
        if let developer = app.developerName, !developer.isEmpty {
            return developer
        }
        return ""
    }
    
    var body: some View {
        HStack {
            HStack(alignment: .center, spacing: 12) {
                SourceIconView(url: app.iconURL)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 16)).bold()
                        if app.isBeta {
                            Text("lc.sources.badge.beta".loc.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    Text(metadataText)
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    if !subtitleText.isEmpty {
                        Text(subtitleText)
                            .font(.system(size: 11))
                            .foregroundColor(textColor)
                            .lineLimit(1)
                    }
                }
            }
            .allowsHitTesting(false)
            Spacer()
            Button {
                installAction(app)
            } label: {
                Text("lc.common.install".loc)
                    .bold()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(height: 32)
                    .minimumScaleFactor(0.1)
            }
            .buttonStyle(BasicButtonStyle())
            .padding()
            .frame(idealWidth: 70)
            .frame(height: 32)
            .fixedSize()
            .background(
                Capsule().fill(dynamicColors ? primaryColor : Color("FontColor"))
            )
            .clipShape(Capsule())
        }
        .padding()
        .frame(height: 88)
        .background {
            RoundedRectangle(cornerSize: CGSize(width: 22, height: 22))
                .fill(backgroundColor)
        }
    }
}

private struct SourceIconView: View {
    let url: URL?
    
    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }
    
    private var placeholder: some View {
        Image("DefaultIcon")
            .resizable()
            .scaledToFill()
    }
}
