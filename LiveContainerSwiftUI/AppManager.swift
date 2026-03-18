import Foundation
import SwiftUI
import UIKit


struct LCCacheDiskTool {
    static let fileManager = FileManager.default
    
    static var appDataRoot: URL {
        
        return LCPath.docPath.appendingPathComponent("Data/Application")
    }

    static func calculateCacheSize(uuid: String) -> Int64 {
        let appPath = appDataRoot.appendingPathComponent(uuid)
        let targets = [
            appPath.appendingPathComponent("Library/Caches"),
            appPath.appendingPathComponent("tmp")
        ]
        
        var total: Int64 = 0
        for target in targets {
            total += getDirectorySize(url: target)
        }
        return total
    }

    static func clearCache(uuid: String) {
        let appPath = appDataRoot.appendingPathComponent(uuid)
        let targets = [
            appPath.appendingPathComponent("Library/Caches"),
            appPath.appendingPathComponent("tmp")
        ]
        
        for target in targets {
            guard let contents = try? fileManager.contentsOfDirectory(at: target, includingPropertiesForKeys: nil) else { continue }
            for file in contents {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private static func getDirectorySize(url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) else { return 0 }
        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }
}


struct LCCacheManagementView: View {
    @EnvironmentObject var sharedModel: SharedModel
    @State private var cacheItems: [CacheItem] = []
    @State private var isScanning = false
    @State private var editingApp: LCAppModel? = nil

    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) var darkModeIcon = false

    struct CacheItem: Identifiable {
        let id: String
        let name: String
        let bundleId: String
        var size: Int64
        let icon: UIImage?
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    let total = cacheItems.reduce(0) { $0 + $1.size }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Total Cache Size").font(.caption).foregroundColor(.gray)
                            Text(formatSize(total)).font(.headline).bold()
                        }
                        Spacer()
                        Button("Clear All Cache") {
                            cacheItems.forEach { LCCacheDiskTool.clearCache(uuid: $0.id) }
                            refresh()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(total == 0)
                    }
                }

                Section("App List") {
                    if isScanning {
                        HStack {
                            Spacer()
                            ProgressView("Scanning...")
                            Spacer()
                        }.padding()
                    } else if cacheItems.isEmpty {
                        Text("No Cache Data").foregroundColor(.gray)
                    } else {
                        ForEach(cacheItems) { item in
                            HStack(spacing: 12) {
                                let displayIcon = LCAppCustomizer.getCustomIcon(for: item.bundleId) ?? item.icon
                                let displayName = LCAppCustomizer.getCustomName(for: item.bundleId, defaultName: item.name)

                                Image(uiImage: displayIcon ?? UIImage(systemName: "app.dashed")!)
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName).font(.subheadline).lineLimit(1)
                                    Text(item.bundleId).font(.caption2).foregroundColor(.gray).lineLimit(1)
                                }
                                Spacer()
                                Text(formatSize(item.size)).font(.caption.monospaced()).foregroundColor(.blue)

                                Button {
                                    LCCacheDiskTool.clearCache(uuid: item.id)
                                    refresh()
                                } label: {
                                    Image(systemName: "trash").foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            .swipeActions(edge: .leading) {
                                Button {
                                    let allApps = sharedModel.apps + sharedModel.hiddenApps
                                    if let foundApp = allApps.first(where: { $0.appInfo.bundleIdentifier() == item.bundleId }) {
                                        self.editingApp = foundApp
                                    }
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cache Manager")
            .onAppear { refresh() }
            .refreshable { refresh() }
            
            .sheet(item: $editingApp) { appModel in
                LCEditAppView(app: appModel, onSave: {
                    refresh()
                })
            }
        }
        .navigationViewStyle(.stack)
    }

    func refresh() {
        isScanning = true
        Task {
            let allApps = sharedModel.apps + sharedModel.hiddenApps
            var items: [CacheItem] = []
            
            for app in allApps {
                if let uuid = app.appInfo.dataUUID {
                    let size = LCCacheDiskTool.calculateCacheSize(uuid: uuid)
                    let appIcon = app.appInfo.iconIsDarkIcon(darkModeIcon)
                    
                    items.append(CacheItem(
                        id: uuid, 
                        name: app.appInfo.displayName(), 
                        bundleId: app.appInfo.bundleIdentifier() ?? "Unknown", 
                        size: size,
                        icon: appIcon
                    ))
                }
            }
            
            await MainActor.run {
                self.cacheItems = items.sorted { $0.size > $1.size }
                self.isScanning = false
            }
        }
    }

    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}


class CacheViewModel: ObservableObject {
    @Published var cacheItems: [CacheItem] = []
    @Published var isScanning = false
    
    
    private var darkModeIcon: Bool {
        return LCUtils.appGroupUserDefault.bool(forKey: "darkModeIcon")
    }
    
    struct CacheItem: Identifiable {
        let id: String
        let name: String
        let bundleId: String
        var size: Int64
        let icon: UIImage?
    }

    @MainActor
    func reload(apps: [LCAppModel]) async {
        isScanning = true
        var items: [CacheItem] = []
        
        
        let isDark = self.darkModeIcon
        
        await withTaskGroup(of: CacheItem?.self) { group in
            for app in apps {
                group.addTask {
                    guard let uuid = app.appInfo.dataUUID else { return nil }
                    let size = LCCacheDiskTool.calculateCacheSize(uuid: uuid)
                    
                    
                    let appIcon = app.appInfo.iconIsDarkIcon(isDark)
                    
                    return CacheItem(
                        id: uuid,
                        name: app.appInfo.displayName(),
                        bundleId: app.appInfo.bundleIdentifier() ?? "Unknown",
                        size: size,
                        icon: appIcon
                    )
                }
            }
            
            for await item in group {
                if let item = item { items.append(item) }
            }
        }
        
        self.cacheItems = items.sorted { $0.size > $1.size }
        isScanning = false
    }
}
