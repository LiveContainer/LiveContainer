import Foundation

struct LCCacheDiskTool {
    static let fileManager = FileManager.default
    
    // 取得 LiveContainer 資料夾下的 Application 根目錄
    static var appDataRoot: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Data/Application")
    }

    // 計算特定 UUID 的快取大小
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

    // 清除特定 UUID 的快取
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

    // 遞迴計算資料夾大小
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
        let id: String // 使用 UUID 作為 ID
        let name: String
        let bundleId: String
        var size: Int64
        let icon: UIImage?
    }

    @MainActor
    func reload(apps: [LCAppModel]) async {
        isScanning = true
        var items: [CacheItem] = []
        
        // 使用 TaskGroup 並行計算提高效率
        await withTaskGroup(of: CacheItem?.self) { group in
            for app in apps {
                group.addTask {
                    guard let uuid = app.appInfo.dataUUID else { return nil }
                    let size = LCCacheDiskTool.calculateCacheSize(uuid: uuid)
                    return CacheItem(
                        id: uuid,
                        name: app.appInfo.displayName(),
                        bundleId: app.appInfo.bundleIdentifier() ?? "Unknown",
                        size: size,
                        icon: app.appInfo.icon()
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
struct LCCacheManagementView: View {
    @EnvironmentObject var sharedModel: SharedModel
    @StateObject private var viewModel = CacheViewModel()
    
    var totalSize: Int64 {
        viewModel.cacheItems.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Total Caches").font(.caption).foregroundColor(.gray)
                        Text(formatSize(totalSize)).font(.title3).bold()
                    }
                    Spacer()
                    Button("Clear All Caches") {
                        for item in viewModel.cacheItems {
                            LCCacheDiskTool.clearCache(uuid: item.id)
                        }
                        refreshData()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(totalSize == 0)
                }
                .padding(.vertical, 4)
            }

            Section("App List") {
                if viewModel.isScanning {
                    ProgressView("Scanning...")
                } else {
                    ForEach(viewModel.cacheItems) { item in
                        HStack {
                            Image(uiImage: item.icon ?? UIImage(systemName: "app")!)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading) {
                                Text(item.name).font(.body)
                                Text(item.bundleId).font(.caption2).foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Text(formatSize(item.size))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.blue)
                            
                            Button {
                                LCCacheDiskTool.clearCache(uuid: item.id)
                                refreshData()
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
        .onAppear { refreshData() }
        .refreshable { refreshData() }
    }

    private func refreshData() {
        Task {
            
            let allApps = sharedModel.apps + sharedModel.hiddenApps
            await viewModel.reload(apps: allApps)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

