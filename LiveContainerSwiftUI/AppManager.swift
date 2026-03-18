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
                        ProgressView("Scanning...").frame(maxWidth: .infinity)
                    } else {
                        ForEach(cacheItems) { item in
                            appRow(item: item) 
                        }
                    }
                }
            }
            .navigationTitle("App Manager")
            .navigationViewStyle(.stack)
            .onAppear { refresh() }
            .refreshable { refresh() }
            .sheet(item: $editingApp) { appModel in
                LCEditAppView(app: appModel, onSave: { refresh() })
            }
        }
        .disabled(isExporting) 

        
        if isExporting {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    
                    Text(exportProgressText)
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .padding(40)
                .background(Color.secondary.opacity(0.5))
                .cornerRadius(20)
            }
        }
    }
    
    .alert(isPresented: $errorShow) {
        Alert(title: Text("Reminder"), message: Text(errorInfo), dismissButton: .default(Text("Confirm")))
    }
}


@ViewBuilder
func appRow(item: CacheItem) -> some View {
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
    }
    .contentShape(Rectangle())
    .contextMenu {
        let allApps = sharedModel.apps + sharedModel.hiddenApps
        let foundApp = allApps.first(where: { $0.appInfo.bundleIdentifier() == item.bundleId })

        Button {
            if let app = foundApp { self.editingApp = app }
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

        

        Button(role: .destructive) {
            LCCacheDiskTool.clearCache(uuid: item.id)
            refresh()
        } label: {
            Label("Clear Cache", systemImage: "trash")
        }
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
    
    isExporting = true
    exportProgressText = "正在導出 \(app.appInfo.displayName())..."
    
    Task(priority: .userInitiated) {
        let fm = FileManager.default
        
        
        guard let pathString = app.appInfo.bundlePath(), !pathString.isEmpty else {
            await MainActor.run {
                self.errorInfo = "找不到路徑"
                self.errorShow = true
                self.isExporting = false
            }
            return
        }
        
        let bundleURL = URL(fileURLWithPath: pathString)
        let appName = app.appInfo.displayName().sanitizeNonACSII()
        let exportIpaURL = fm.temporaryDirectory.appendingPathComponent("\(appName).ipa")
        let workDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let payloadURL = workDir.appendingPathComponent("Payload")
        
        try? fm.removeItem(at: exportIpaURL)
        try? fm.removeItem(at: workDir)
        
        do {
            try fm.createDirectory(at: payloadURL, withIntermediateDirectories: true)
            try fm.copyItem(at: bundleURL, to: payloadURL.appendingPathComponent(bundleURL.lastPathComponent))
            
            let currentDir = fm.currentDirectoryPath
            fm.changeCurrentDirectoryPath(workDir.path)
            
            
            let command = "zip -ry '\(exportIpaURL.path)' 'Payload'"
            let result = shell(command)
            
            fm.changeCurrentDirectoryPath(currentDir)
            
            await MainActor.run {
                self.isExporting = false
                if result == 0 {
                    let activityVC = UIActivityViewController(activityItems: [exportIpaURL], applicationActivities: nil)
                    if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                        activityVC.popoverPresentationController?.sourceView = rootVC.view
                        activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                        rootVC.present(activityVC, animated: true)
                    }
                } else {
                    self.errorInfo = "壓縮失敗 (\(result))"
                    self.errorShow = true
                }
                try? fm.removeItem(at: workDir)
            }
        } catch {
            await MainActor.run {
                self.errorInfo = error.localizedDescription
                self.errorShow = true
                self.isExporting = false
            }
        }
    }
}


