import Foundation

struct LCCacheDiskTool {
    static let fileManager = FileManager.default
    
    
    static var appDataRoot: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Data/Application")
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
        let resourceKeys: [URLResourceKey] = [.fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: resourceKeys) else { return 0 }
        
        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  let fileSize = resourceValues.fileSize else { continue }
            size += Int64(fileSize)
        }
        return size
    }
}
class CacheViewModel: ObservableObject {
    @Published var cacheItems: [CacheItem] = []
    @Published var isScanning = false
    
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
        
        
        await withTaskGroup(of: CacheItem?.self) { group in
            for app in apps {
                group.addTask {
                    guard let uuid = app.appInfo.dataUUID else { return nil }
                    let size = LCCacheDiskTool.calculateCacheSize(uuid: uuid)
                    let icon = LCUtils.icon(forBundleIdentifier: app.appInfo.bundleIdentifier()) ?? UIImage(systemName: "app.dashed")
                    return CacheItem(
                        id: uuid,
                        name: app.appInfo.displayName(),
                        bundleId: app.appInfo.bundleIdentifier() ?? "Unknown",
                        size: size,
                        icon: icon

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
import SwiftUI


struct LCCacheManagementView: View {
    
    @EnvironmentObject var sharedModel: SharedModel
    @State private var cacheItems: [CacheItem] = []
    @State private var isScanning = false

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
                            Text("Total Cache Size").font(.caption).foregroundColor(.green)
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

                Section("lc.cache.appList".loc) {
                    if isScanning {
                        ProgressView()
                    } else {
                        ForEach(cacheItems) { item in
                            HStack {
                                Image(uiImage: item.icon ?? UIImage(systemName: "app")!)
                                    .resizable().frame(width: 32, height: 32).cornerRadius(6)
                                VStack(alignment: .leading) {
                                    Text(item.name).font(.subheadline)
                                    Text(item.bundleId).font(.caption2).foregroundColor(.gray)
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
                        }
                    }
                }
            }
            .navigationTitle("App Manager")
            .onAppear { refresh() }
            .refreshable { refresh() }
        }
        .navigationViewStyle(.stack)
    }

    func refresh() {
        isScanning = true
        Task {
            let apps = sharedModel.apps + sharedModel.hiddenApps
            var items: [CacheItem] = []
            for app in apps {
                if let uuid = app.appInfo.dataUUID {
                    let size = LCCacheDiskTool.calculateCacheSize(uuid: uuid)
                    items.append(CacheItem(id: uuid, name: app.appInfo.displayName(), bundleId: app.appInfo.bundleIdentifier() ?? "", size: size,icon: UIImage(systemName: "app.dashed")
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


    

