import Foundation
import SwiftUI
import UIKit
import PhotosUI


@_silgen_name("system")
@discardableResult
func shell(_ command: String) -> Int32

extension LCAppModel: Identifiable {
    public var id: String {
        return self.appInfo.bundleIdentifier() ?? UUID().uuidString
    }
}


struct LCCacheDiskTool {
    static let fileManager = FileManager.default
    static var appDataRoot: URL {
        return LCPath.dataPath 
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
    @State private var isExporting = false
@State private var exportProgressText = "" 

    @EnvironmentObject var sharedModel: SharedModel
    @State private var cacheItems: [CacheItem] = []
    @State private var isScanning = false
    @State private var editingApp: LCAppModel? = nil
    @State private var errorInfo = ""
    @State private var errorShow = false
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
                                    Image(systemName: "trash").foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                           .contextMenu {
    let allApps = sharedModel.apps + sharedModel.hiddenApps
    let foundApp = allApps.first(where: { $0.appInfo.bundleIdentifier() == item.bundleId })

    Button {
        if let app = foundApp {
            self.editingApp = app
        }
    } label: {
        Label("Edit App Info", systemImage: "pencil")
    }

    Button {
        if let app = foundApp {
            exportAppAsIpa(app: app)
        }
    } label: {
        Label("Export As ipa", systemImage: "square.and.arrow.up")
    }
    .disabled(foundApp == nil) 

                                Divider() 

                                Button(role: .destructive) {
                                    LCCacheDiskTool.clearCache(uuid: item.id)
                                    refresh()
                                } label: {
                                    Label("Clear Cache", systemImage: "trash")
                                }
                            }
                        } 
                    }
                } 
            } 
            .navigationViewStyle(.stack) 
            .navigationTitle("App Manager")
        
            .onAppear { refresh() }
            .refreshable { refresh() }
            .sheet(item: $editingApp) { appModel in
                LCEditAppView(app: appModel, onSave: {
                    refresh()
                })
            }
        } 
            .navigationViewStyle(.stack) 
             .disabled(isExporting) 

        
        if isExporting {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 15) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text(exportProgressText)
                    .foregroundColor(.white)
                    .font(.subheadline)
                    .bold()
            }
            .padding(30)
             
            .cornerRadius(15)
        }
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

    func exportAppAsIpa(app: LCAppModel) {
    let fm = FileManager.default
    
    // 取得 .app 的路徑 (注意：LiveContainer 中通常是 app.appInfo.bundlePath())
    guard let pathString = app.appInfo.bundlePath(), !pathString.isEmpty else {
        self.errorInfo = "找不到 App 路徑"
        self.errorShow = true
        return
    }
    
    let bundleURL = URL(fileURLWithPath: pathString)
    let appName = app.appInfo.displayName().sanitizeNonACSII()
    let exportIpaURL = fm.temporaryDirectory.appendingPathComponent("\(appName).ipa")

    // 1. 建立一個乾淨的臨時工作目錄
    let workDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let payloadURL = workDir.appendingPathComponent("Payload")
    
    try? fm.removeItem(at: exportIpaURL)
    try? fm.removeItem(at: workDir)

    do {
        // 建立 Payload 資料夾
        try fm.createDirectory(at: payloadURL, withIntermediateDirectories: true)
        
        // 2. 把 .app 拷貝進去
        let targetAppURL = payloadURL.appendingPathComponent(bundleURL.lastPathComponent)
        try fm.copyItem(at: bundleURL, to: targetAppURL)

        // 3. 核心步驟：切換目錄並壓縮
        let currentDir = fm.currentDirectoryPath
        fm.changeCurrentDirectoryPath(workDir.path) // 切換到包含 Payload 的那一層
        
        // 執行指令：將 Payload 壓縮到 temp 目錄下的 ipa 檔案
        // -r 是遞迴壓縮，-y 是保留符號連結 (這對 iOS App 很重要)
        let command = "zip -ry '\(exportIpaURL.path)' 'Payload'"
        let result = shell(command)
        
        fm.changeCurrentDirectoryPath(currentDir) // 換回來

        if result != 0 {
            throw NSError(domain: "ZipError", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "壓縮失敗"])
        }

        // 4. 跳出 iPad 分享選單
        let activityVC = UIActivityViewController(activityItems: [exportIpaURL], applicationActivities: nil)
        if let rootVC = UIApplication.shared.windows.first?.rootViewController {
            activityVC.popoverPresentationController?.sourceView = rootVC.view
            // 設定在螢幕中間彈出，避免 iPad 閃退
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            rootVC.present(activityVC, animated: true)
        }
        
        // 清理 Payload 暫存
        try? fm.removeItem(at: workDir)
        
    } catch {
        self.errorInfo = "導出失敗: \(error.localizedDescription)"
        self.errorShow = true
    }
}


}


