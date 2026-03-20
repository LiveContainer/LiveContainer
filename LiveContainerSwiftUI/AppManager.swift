import Foundation
import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

@_silgen_name("system")
@discardableResult
func shell(_ command: String) -> Int32

extension LCAppModel: Identifiable {
    public var id: String {
        return self.appInfo.bundleIdentifier() ?? UUID().uuidString
    }
}


extension UTType {
    static var ipafile: UTType {
        UTType(filenameExtension: "ipa") ?? .data
    }
}

struct IPAFile: FileDocument {
    static var readableContentTypes: [UTType] { [.ipa] } 
    let url: URL

    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw NSError(domain: "NS", code: -1) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return try FileWrapper(url: url, options: .immediate)
    }
}

struct LCCacheManagementView: View {
    
    @State private var isExporting = false
    @State private var exportProgressText = "" 
    @State private var exportDoc: IPAFile? = nil 
    @State private var isShowingExporter = false 

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
        ZStack {
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
                    VStack(spacing: 8) {
            Text("\(cacheItems.count) Apps")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            
            
            Color.clear
                .frame(height: 80)
                
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
              .navigationViewStyle(.stack)

            if isExporting {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.5).progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text(exportProgressText).foregroundColor(.white).font(.headline)
                    }
                    .padding(40)
                    .background(Color.secondary.opacity(0.5))
                    .cornerRadius(20)
                }
            
            
            }
        } 
        .fileExporter(
            isPresented: $isShowingExporter,
            document: exportDoc,
            contentType: .ipa,
            defaultFilename: exportDoc?.url.lastPathComponent ?? "App.ipa"
        ) { result in
            if let doc = exportDoc {
                let workDir = doc.url.deletingLastPathComponent()
                try? FileManager.default.removeItem(at: workDir)
            }
            self.exportDoc = nil
        }
        .alert(isPresented: $errorShow) {
            Alert(title: Text("Reminder"), message: Text(errorInfo), dismissButton: .default(Text("Confirm")))
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

    func exportAppAsIpa(app: LCAppModel) {
    isExporting = true
    exportProgressText = "Compress \(app.appInfo.displayName())..."
    
    Task(priority: .userInitiated) {
        let fm = FileManager.default
        guard let pathString = app.appInfo.bundlePath(), !pathString.isEmpty else {
            await MainActor.run { self.isExporting = false }
            return
        }
        
        let bundleURL = URL(fileURLWithPath: pathString)
        let appName = app.appInfo.displayName().sanitizeNonACSII().replacingOccurrences(of: " ", with: "_")
        
        
        let workDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let payloadURL = workDir.appendingPathComponent("Payload")
        
        do {
            try fm.createDirectory(at: payloadURL, withIntermediateDirectories: true)
            
            try fm.copyItem(at: bundleURL, to: payloadURL.appendingPathComponent(bundleURL.lastPathComponent))
            
            
            let coordinator = NSFileCoordinator()
            var zipError: NSError?
            var systemZipURL: URL?
            
            
            coordinator.coordinate(readingItemAt: payloadURL, options: .forUploading, error: &zipError) { zippedURL in
                
                let finalIpaURL = workDir.appendingPathComponent("\(appName).ipa")
                try? fm.moveItem(at: zippedURL, to: finalIpaURL)
                systemZipURL = finalIpaURL
            }
            
            await MainActor.run {
                self.isExporting = false
                if let finalURL = systemZipURL, fm.fileExists(atPath: finalURL.path) {
                    self.exportDoc = IPAFile(url: finalURL)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.isShowingExporter = true
                    }
                } else {
                    self.errorInfo = "Failed : \(zipError?.localizedDescription ?? "Unknown Error")"
                    self.errorShow = true
                }
            }
            
        } catch {
            await MainActor.run {
                self.errorInfo = "Error: \(error.localizedDescription)"
                self.errorShow = true
                self.isExporting = false
            }
        }
    }
}

    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
            } label: { Label("Edit Info", systemImage: "pencil") }

            Button {
                if let app = foundApp { exportAppAsIpa(app: app) }
            } label: { Label("Export IPA", systemImage: "square.and.arrow.up") }
            .disabled(foundApp == nil)

            Button(role: .destructive) {
                LCCacheDiskTool.clearCache(uuid: item.id)
                refresh()
            } label: { Label("Clear Cache", systemImage: "trash") }
        }
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


