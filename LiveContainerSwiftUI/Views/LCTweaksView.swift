//
//  LCTweaksView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private let lcDisabledTweaksKey = "disabledItems"

final class LCTweakMoveContext: ObservableObject {
    @Published var draggingItemURL: URL?
    @Published var pendingMoveItemURL: URL?

    func beginDrag(_ url: URL) {
        draggingItemURL = url
    }

    func clearDrag() {
        draggingItemURL = nil
    }

    func beginMove(_ url: URL) {
        pendingMoveItemURL = url
    }

    func clearMove() {
        pendingMoveItemURL = nil
    }
}

struct LCTweakItem : Hashable {
    let fileUrl: URL
    let isFolder: Bool
    let isFramework: Bool
    let isTweak: Bool

    var supportsDisableToggle: Bool {
        isFramework || isTweak
    }
}

struct LCTweakHelpView: View {
    @Binding var isPresent: Bool

    var body: some View {
        NavigationView {
            Form {
                Section("lc.tabView.tweaks".loc) {
                    Text("lc.tweakView.helpText1".loc)
                    Text("lc.tweakView.helpText2".loc)
                    Text("lc.tweakView.helpText3".loc)
                    Text("lc.tweakView.helpText4".loc)
                    Text("lc.tweakView.helpText5".loc)
                    Text("lc.tweakView.helpText6".loc)
                }
            }
            .navigationTitle("lc.tweakView.helpTitle".loc)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("lc.common.done".loc) {
                        isPresent = false
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct LCTweakFolderView : View {
    @State var baseUrl : URL
    @State var tweakItems : [LCTweakItem]
    private var isRoot : Bool
    @Binding var tweakFolders : [String]
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    @StateObject private var newFolderInput = InputHelper()
    
    @StateObject private var renameFileInput = InputHelper()
    
    @State private var choosingTweak = false
    @StateObject private var installUrlInput = InputHelper()
    @ObservedObject var downloadHelper = DownloadHelper()
    
    @State private var isTweakSigning = false
    @State private var isInstallingFromURL = false
    @State private var helpPresent = false
    @State private var disabledTweaks: Set<String>
    
    @EnvironmentObject private var moveContext: LCTweakMoveContext

    init(baseUrl: URL, isRoot: Bool = false, tweakFolders: Binding<[String]>) {
        _baseUrl = State(initialValue: baseUrl)
        _tweakFolders = tweakFolders
        self.isRoot = isRoot
        _tweakItems = State(initialValue: LCTweakFolderView.loadTweakItems(baseUrl))
        _disabledTweaks = State(initialValue: LCTweakFolderView.loadDisabledTweaks(baseUrl))
    }
    
    var body: some View {
        List {
            if moveContext.pendingMoveItemURL != nil {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("lc.tweakView.moveMode %@".localizeWithFormat(moveContext.pendingMoveItemURL?.lastPathComponent ?? ""))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("lc.tweakView.moveHere".loc) {
                                movePendingItemHere()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("lc.common.cancel".loc) {
                                moveContext.clearMove()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            Section {
                ForEach(tweakItems, id:\.self) { tweakItem in
                    rowView(for: tweakItem)
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture(count: 2).onEnded {
                            toggleTweakDisabled(tweakItem)
                        })
                        .onDrag {
                            moveContext.beginDrag(tweakItem.fileUrl)
                            return NSItemProvider(object: tweakItem.fileUrl.path as NSString)
                        }
                        .onDrop(of: [.text], isTargeted: nil) { _ in
                            dropDraggedItem(into: tweakItem)
                        }
                    .contextMenu {
                        Button {
                            Task { await renameTweakItem(tweakItem: tweakItem)}
                        } label: {
                            Label("lc.common.rename".loc, systemImage: "pencil")
                        }

                        if tweakItem.supportsDisableToggle {
                            Button {
                                toggleTweakDisabled(tweakItem)
                            } label: {
                                if isTweakDisabled(tweakItem) {
                                    Label("lc.tweakView.enable".loc, systemImage: "checkmark.circle")
                                } else {
                                    Label("lc.tweakView.disable".loc, systemImage: "nosign")
                                }
                            }
                        }

                        Button {
                            moveContext.beginMove(tweakItem.fileUrl)
                        } label: {
                            Label("lc.common.move".loc, systemImage: "folder")
                        }
                        
                        Button(role: .destructive) {
                            deleteTweakItem(tweakItem: tweakItem)
                        } label: {
                            Label("lc.common.delete".loc, systemImage: "trash")
                        }
                    }

                }.onDelete { indexSet in
                    deleteTweakItem(indexSet: indexSet)
                }
            }
            Section {
                VStack{
                    if isRoot {
                        Text("lc.tweakView.globalFolderDesc".loc)
                            .foregroundStyle(.gray)
                            .font(.system(size: 12))
                    } else {
                        Text("lc.tweakView.appFolderDesc".loc)
                            .foregroundStyle(.gray)
                            .font(.system(size: 12))
                    }

                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color(UIColor.systemGroupedBackground))
                    .listRowInsets(EdgeInsets())
            }

        }
        .onAppear {
            reloadTweakItems()
            disabledTweaks = Self.loadDisabledTweaks(baseUrl)
            syncRootTweakFoldersIfNeeded()
        }
        .navigationTitle(isRoot ? "lc.tabView.tweaks".loc : baseUrl.lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("lc.tweakView.helpButton".loc, systemImage: "questionmark") {
                    helpPresent = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !isTweakSigning && LCSharedUtils.certificatePassword() != nil {
                    Button {
                        Task { await signAllTweaks() }
                    } label: {
                        Label("sign".loc, systemImage: "signature")
                    }
                }

            }
            ToolbarItem(placement: .topBarTrailing) {
                if !isTweakSigning && !isInstallingFromURL {
                    Menu {
                        Button {
                            if choosingTweak {
                                choosingTweak = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                                    choosingTweak = true
                                })
                            } else {
                                choosingTweak = true
                            }
                        } label: {
                            Label("lc.tweakView.importTweak".loc, systemImage: "square.and.arrow.down")
                        }

                        Button {
                            Task { await startInstallFromUrl() }
                        } label: {
                            Label("lc.appList.installFromUrl".loc, systemImage: "link.badge.plus")
                        }
                        
                        Button {
                            Task { await createNewFolder() }
                        } label: {
                            Label("lc.tweakView.newFolder".loc, systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Label("add", systemImage: "plus")
                    }
                } else {
                    ProgressView().progressViewStyle(.circular)
                }

            }
        }
        .sheet(isPresented: $helpPresent) {
            LCTweakHelpView(isPresent: $helpPresent)
        }
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        .textFieldAlert(
            isPresented: $newFolderInput.show,
            title: "lc.common.enterNewFolderName".loc,
            text: $newFolderInput.initVal,
            placeholder: "",
            action: { newText in
                newFolderInput.close(result: newText)
            },
            actionCancel: {_ in
                newFolderInput.close(result: "")
            }
        )
        .textFieldAlert(
            isPresented: $renameFileInput.show,
            title: "lc.common.enterNewName".loc,
            text: $renameFileInput.initVal,
            placeholder: "",
            action: { newText in
                renameFileInput.close(result: newText)
            },
            actionCancel: {_ in
                renameFileInput.close(result: "")
            }
        )
        .textFieldAlert(
            isPresented: $installUrlInput.show,
            title:  "lc.appList.installUrlInputTip".loc,
            text: $installUrlInput.initVal,
            placeholder: "https://",
            action: { newText in
                installUrlInput.close(result: newText)
            },
            actionCancel: {_ in
                installUrlInput.close(result: nil)
            }
        )
        .betterFileImporter(isPresented: $choosingTweak, types: [.dylib, .lcFramework, .zipArchive, .deb], multiple: true, callback: { fileUrls in
            Task { await importSelectedTweaks(fileUrls) }
        }, onDismiss: {
            choosingTweak = false
        })
        .downloadAlert(helper: downloadHelper)
    }

    @ViewBuilder
    private func rowView(for tweakItem: LCTweakItem) -> some View {
        if tweakItem.isFolder || tweakItem.isFramework {
            NavigationLink {
                LCTweakFolderView(baseUrl: tweakItem.fileUrl, isRoot: false, tweakFolders: $tweakFolders)
                    .environmentObject(moveContext)
            } label: {
                tweakItemLabel(tweakItem)
            }
        } else {
            tweakItemLabel(tweakItem)
        }
    }

    private func tweakItemLabel(_ tweakItem: LCTweakItem) -> some View {
        Label {
            Text(tweakItem.fileUrl.lastPathComponent)
                .lineLimit(1)
        } icon: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: iconName(for: tweakItem))
                    .frame(width: 20, height: 20)
                if tweakItem.supportsDisableToggle {
                    Circle()
                        .fill(isTweakDisabled(tweakItem) ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle().stroke(Color(.systemBackground), lineWidth: 1)
                        )
                        .offset(x: 4, y: -4)
                }
            }
        }
    }

    private func iconName(for tweakItem: LCTweakItem) -> String {
        if tweakItem.isFramework {
            return "shippingbox.fill"
        }
        if tweakItem.isFolder {
            return "folder.fill"
        }
        if tweakItem.isTweak {
            return "building.columns.fill"
        }
        return "document.fill"
    }

    private func isTweakDisabled(_ tweakItem: LCTweakItem) -> Bool {
        disabledTweaks.contains(tweakItem.fileUrl.lastPathComponent)
    }

    private func dropDraggedItem(into tweakItem: LCTweakItem) -> Bool {
        guard tweakItem.isFolder || tweakItem.isFramework else {
            return false
        }
        guard let dragURL = moveContext.draggingItemURL else {
            return false
        }
        moveContext.clearDrag()
        moveTweakItem(from: dragURL, toFolder: tweakItem.fileUrl)
        return true
    }
    
    func deleteTweakItem(indexSet: IndexSet) {
        var indexToRemove : [Int] = []
        let fm = FileManager()
        do {
            for i in indexSet {
                let tweakItem = tweakItems[i]
                try fm.removeItem(at: tweakItem.fileUrl)
                if tweakItem.supportsDisableToggle {
                    disabledTweaks.remove(tweakItem.fileUrl.lastPathComponent)
                }
                indexToRemove.append(i)
            }
            try persistDisabledTweaks()
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        if isRoot {
            for iToRemove in indexToRemove {
                tweakFolders.removeAll(where: { s in
                    return s == tweakItems[iToRemove].fileUrl.lastPathComponent
                })
            }
        }

        tweakItems.remove(atOffsets: IndexSet(indexToRemove))
    }
    
    func deleteTweakItem(tweakItem: LCTweakItem) {
        var indexToRemove : Int?
        let fm = FileManager()
        do {

            try fm.removeItem(at: tweakItem.fileUrl)
            indexToRemove = tweakItems.firstIndex(where: { s in
                return s == tweakItem
            })
            if tweakItem.supportsDisableToggle {
                disabledTweaks.remove(tweakItem.fileUrl.lastPathComponent)
                try persistDisabledTweaks()
            }
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        
        guard let indexToRemove = indexToRemove else {
            return
        }
        tweakItems.remove(at: indexToRemove)
        if isRoot {
            tweakFolders.removeAll(where: { s in
                return s == tweakItem.fileUrl.lastPathComponent
            })
        }
    }
    
    func renameTweakItem(tweakItem: LCTweakItem) async {
        guard let newName = await renameFileInput.open(initVal: tweakItem.fileUrl.lastPathComponent), newName != "" else {
            return
        }
        
        let indexToRename = tweakItems.firstIndex(where: { s in
            return s == tweakItem
        })
        guard let indexToRename = indexToRename else {
            return
        }
        let newUrl = self.baseUrl.appendingPathComponent(newName)
        
        let fm = FileManager()
        do {
            try fm.moveItem(at: tweakItem.fileUrl, to: newUrl)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        if tweakItem.supportsDisableToggle, disabledTweaks.contains(tweakItem.fileUrl.lastPathComponent) {
            disabledTweaks.remove(tweakItem.fileUrl.lastPathComponent)
            disabledTweaks.insert(newUrl.lastPathComponent)
            do {
                try persistDisabledTweaks()
            } catch {
                errorShow = true
                errorInfo = error.localizedDescription
                return
            }
        }
        tweakItems.remove(at: indexToRename)
        let newTweakItem = LCTweakItem(fileUrl: newUrl, isFolder: tweakItem.isFolder, isFramework: tweakItem.isFramework, isTweak: tweakItem.isTweak)
        tweakItems.insert(newTweakItem, at: indexToRename)
        
        if isRoot {
            let indexToRename2 = tweakFolders.firstIndex(of: tweakItem.fileUrl.lastPathComponent)
            guard let indexToRename2 = indexToRename2 else {
                return
            }
            tweakFolders.remove(at: indexToRename2)
            tweakFolders.insert(newName, at: indexToRename2)
            
        }
    }
    
    func signAllTweaks() async {
        do {
            defer {
                isTweakSigning = false
            }
            
            try await LCUtils.signTweaks(tweakFolderUrl: self.baseUrl, force: true) { p in
                isTweakSigning = true
            }

        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }
    }

    func createNewFolder() async {
        guard let newName = await renameFileInput.open(), newName != "" else {
            return
        }
        let fm = FileManager()
        let dest = baseUrl.appendingPathComponent(newName)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        tweakItems.append(LCTweakItem(fileUrl: dest, isFolder: true, isFramework: false, isTweak: false))
        if isRoot {
            tweakFolders.append(newName)
        }
    }

    func importSelectedTweaks(_ urls: [URL]) async {
        do {
            let fm = FileManager.default
            for fileUrl in urls {
                if !fileUrl.isFileURL {
                    throw "lc.tweakView.notFileError %@".localizeWithFormat(fileUrl.lastPathComponent)
                }

                var didStartAccess = false
                if !fm.isReadableFile(atPath: fileUrl.path) {
                    didStartAccess = fileUrl.startAccessingSecurityScopedResource()
                    if !didStartAccess {
                        throw "lc.appList.ipaAccessError".loc
                    }
                }
                defer {
                    if didStartAccess {
                        fileUrl.stopAccessingSecurityScopedResource()
                    }
                }

                try await installDownloadedTweakArtifact(fileUrl)
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }
    }
    
    func startInstallTweak(_ urls: [URL]) async {
        do {
            let fm = FileManager()
            // we will sign later before app launch
            
            for fileUrl in urls {
                // handle deb file
                if(!fileUrl.isFileURL) {
                    throw "lc.tweakView.notFileError %@".localizeWithFormat(fileUrl.lastPathComponent)
                }
                let toPath = self.baseUrl.appendingPathComponent(fileUrl.lastPathComponent)
                try fm.moveItem(at: fileUrl, to: toPath)

                let isFramework = toPath.lastPathComponent.hasSuffix(".framework")
                let isTweak = toPath.lastPathComponent.hasSuffix(".dylib")
                if isTweak {
                    LCParseMachO((toPath.path as NSString).utf8String, false) { path, header, _, _ in
                        LCPatchAddRPath(path, header);
                    }
                }
                self.tweakItems.append(LCTweakItem(fileUrl: toPath, isFolder: isFramework, isFramework: isFramework, isTweak: isTweak))
            }
            reloadTweakItems()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true            
            return
        }
    }

    private func toggleTweakDisabled(_ tweakItem: LCTweakItem) {
        guard tweakItem.supportsDisableToggle else {
            return
        }
        let name = tweakItem.fileUrl.lastPathComponent
        let wasDisabled = disabledTweaks.contains(name)
        if disabledTweaks.contains(name) {
            disabledTweaks.remove(name)
        } else {
            disabledTweaks.insert(name)
        }
        do {
            try persistDisabledTweaks()
            triggerToggleHaptic(enabled: wasDisabled)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func triggerToggleHaptic(enabled: Bool) {
        if enabled {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        } else {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 1.0)
        }
    }

    private func movePendingItemHere() {
        guard let pendingURL = moveContext.pendingMoveItemURL else {
            return
        }
        moveTweakItem(from: pendingURL, toFolder: baseUrl)
        moveContext.clearMove()
    }

    private func moveTweakItem(from sourceURL: URL, toFolder destinationFolderURL: URL) {
        let sourceFolderURL = sourceURL.deletingLastPathComponent()
        if sourceFolderURL == destinationFolderURL {
            return
        }
        if sourceURL == destinationFolderURL {
            errorShow = true
            errorInfo = "lc.tweakView.error.cannotMoveIntoSelf".loc
            return
        }
        if destinationFolderURL.path.hasPrefix(sourceURL.path + "/") {
            errorShow = true
            errorInfo = "lc.tweakView.error.cannotMoveIntoSelf".loc
            return
        }
        let destinationURL = destinationFolderURL.appendingPathComponent(sourceURL.lastPathComponent)
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            errorShow = true
            errorInfo = "lc.tweakView.error.destinationExists %@".localizeWithFormat(sourceURL.lastPathComponent)
            return
        }
        do {
            try fm.moveItem(at: sourceURL, to: destinationURL)
            try Self.removeDisabledFlag(name: sourceURL.lastPathComponent, in: sourceFolderURL)
            if sourceFolderURL == baseUrl {
                disabledTweaks.remove(sourceURL.lastPathComponent)
            }
            reloadTweakItems()
            syncRootTweakFoldersIfNeeded()
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
        }
    }

    private func reloadTweakItems() {
        tweakItems = Self.loadTweakItems(baseUrl)
    }

    private static func loadTweakItems(_ folderURL: URL) -> [LCTweakItem] {
        var items: [LCTweakItem] = []
        let fm = FileManager.default
        do {
            let files = try fm.contentsOfDirectory(atPath: folderURL.path)
            for fileName in files {
                if fileName == "TweakInfo.plist" {
                    continue
                }
                let fileUrl = folderURL.appendingPathComponent(fileName)
                var isDirectory: ObjCBool = false
                fm.fileExists(atPath: fileUrl.path, isDirectory: &isDirectory)
                let isFramework = isDirectory.boolValue && fileUrl.lastPathComponent.hasSuffix(".framework")
                let isTweak = !isDirectory.boolValue && fileUrl.lastPathComponent.hasSuffix(".dylib")
                items.append(LCTweakItem(fileUrl: fileUrl, isFolder: isDirectory.boolValue, isFramework: isFramework, isTweak: isTweak))
            }
        } catch {
            NSLog("[LC] failed to load tweaks \(error.localizedDescription)")
        }
        return items.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder {
                return lhs.isFolder && !rhs.isFolder
            }
            return lhs.fileUrl.lastPathComponent.localizedCaseInsensitiveCompare(rhs.fileUrl.lastPathComponent) == .orderedAscending
        }
    }

    private static func loadDisabledTweaks(_ folderURL: URL) -> Set<String> {
        let infoPath = folderURL.appendingPathComponent("TweakInfo.plist").path
        guard let info = NSDictionary(contentsOfFile: infoPath),
              let disabled = info[lcDisabledTweaksKey] as? [String] else {
            return []
        }
        return Set(disabled)
    }

    private func persistDisabledTweaks() throws {
        let infoPath = baseUrl.appendingPathComponent("TweakInfo.plist").path
        let info = NSMutableDictionary(contentsOfFile: infoPath) ?? NSMutableDictionary()
        if disabledTweaks.isEmpty {
            info.removeObject(forKey: lcDisabledTweaksKey)
        } else {
            info[lcDisabledTweaksKey] = disabledTweaks.sorted()
        }
        if !info.write(toFile: infoPath, atomically: true) {
            throw "lc.tweakView.error.updateSettings".loc
        }
    }

    private static func removeDisabledFlag(name: String, in folderURL: URL) throws {
        let infoPath = folderURL.appendingPathComponent("TweakInfo.plist").path
        let info = NSMutableDictionary(contentsOfFile: infoPath) ?? NSMutableDictionary()
        guard var disabled = info[lcDisabledTweaksKey] as? [String] else {
            return
        }
        disabled.removeAll { $0 == name }
        if disabled.isEmpty {
            info.removeObject(forKey: lcDisabledTweaksKey)
        } else {
            info[lcDisabledTweaksKey] = disabled
        }
        if !info.write(toFile: infoPath, atomically: true) {
            throw "lc.tweakView.error.updateSettings".loc
        }
    }

    private func syncRootTweakFoldersIfNeeded() {
        guard isRoot else {
            return
        }
        let fm = FileManager.default
        do {
            let dirs = try fm.contentsOfDirectory(atPath: LCPath.tweakPath.path)
            tweakFolders = dirs.filter { name in
                if name == "TweakInfo.plist" || name == "TweakLoader.dylib" {
                    return false
                }
                let url = LCPath.tweakPath.appendingPathComponent(name)
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }.sorted()
        } catch {
            NSLog("[LC] failed to sync tweak folders \(error.localizedDescription)")
        }
    }

    nonisolated func decompress(_ path: String, _ destination: String, _ progress: Progress) async -> Int32 {
        extract(path, destination, progress)
    }

    private func startInstallFromUrl() async {
        guard let installUrlStr = await installUrlInput.open(), installUrlStr.count > 0 else {
            return
        }
        await installFromUrl(urlStr: installUrlStr)
    }

    private func installFromUrl(urlStr: String) async {
        if isInstallingFromURL {
            return
        }
        guard let installURL = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorInfo = "lc.appList.urlInvalidError".loc
            errorShow = true
            return
        }

        isInstallingFromURL = true
        defer {
            isInstallingFromURL = false
        }

        if installURL.isFileURL {
            let fm = FileManager.default
            var didStartAccess = false
            if !fm.isReadableFile(atPath: installURL.path) {
                didStartAccess = installURL.startAccessingSecurityScopedResource()
                if !didStartAccess {
                    errorInfo = "lc.appList.ipaAccessError".loc
                    errorShow = true
                    return
                }
            }
            defer {
                if didStartAccess {
                    installURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try await installDownloadedTweakArtifact(installURL)
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
            return
        }

        do {
            let fm = FileManager.default
            let filename = installURL.lastPathComponent.isEmpty ? "download_\(UUID().uuidString)" : installURL.lastPathComponent
            let destinationURL = fm.temporaryDirectory.appendingPathComponent(filename)
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }

            try await downloadHelper.download(url: installURL, to: destinationURL)
            if downloadHelper.cancelled {
                return
            }

            try await installDownloadedTweakArtifact(destinationURL)
            try? fm.removeItem(at: destinationURL)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    private func installDownloadedTweakArtifact(_ artifactURL: URL) async throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: artifactURL.path, isDirectory: &isDir) else {
            throw "lc.tweakView.error.downloadedNotFound".loc
        }

        if isDir.boolValue {
            if artifactURL.lastPathComponent.hasSuffix(".framework") {
                await startInstallTweak([artifactURL])
                return
            }
            let candidates = try collectTweakCandidates(in: artifactURL)
            if candidates.isEmpty {
                throw "lc.tweakView.error.noTweakInFolder".loc
            }
            await startInstallTweak(candidates)
            return
        }

        if artifactURL.lastPathComponent.hasSuffix(".dylib") {
            await startInstallTweak([artifactURL])
            return
        }

        if isDebPackageURL(artifactURL) {
            try await installDebPackage(artifactURL)
            return
        }

        // Try to treat remote artifact as archive package containing .dylib or .framework
        let extractionDir = fm.temporaryDirectory.appendingPathComponent("LCTweakExtract_\(UUID().uuidString)")
        try fm.createDirectory(at: extractionDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: extractionDir)
        }

        let extractionProgress = Progress.discreteProgress(totalUnitCount: 100)
        guard await decompress(artifactURL.path, extractionDir.path, extractionProgress) == 0 else {
            throw "lc.tweakView.error.unsupportedPackage".loc
        }

        let candidates = try collectTweakCandidates(in: extractionDir)
        if candidates.isEmpty {
            throw "lc.tweakView.error.noTweakInPackage".loc
        }
        await startInstallTweak(candidates)
    }

    private func isDebPackageURL(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("deb") == .orderedSame
    }

    private func installDebPackage(_ debURL: URL) async throws {
        let fm = FileManager.default
        let debRoot = fm.temporaryDirectory.appendingPathComponent("LCTweakDebExtract_\(UUID().uuidString)")
        try fm.createDirectory(at: debRoot, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: debRoot)
        }

        let debProgress = Progress.discreteProgress(totalUnitCount: 100)
        guard await decompress(debURL.path, debRoot.path, debProgress) == 0 else {
            throw "lc.tweakView.error.unsupportedPackage".loc
        }

        var candidates = try collectTweakCandidates(in: debRoot)
        let dataArchives = try findDebDataArchives(in: debRoot)

        if dataArchives.isEmpty && candidates.isEmpty {
            throw "lc.tweakView.error.unsupportedPackage".loc
        }

        for (index, dataArchive) in dataArchives.enumerated() {
            let payloadDir = debRoot.appendingPathComponent("payload_\(index)")
            try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)
            let payloadProgress = Progress.discreteProgress(totalUnitCount: 100)
            guard await decompress(dataArchive.path, payloadDir.path, payloadProgress) == 0 else {
                continue
            }
            candidates.append(contentsOf: try collectTweakCandidates(in: payloadDir))
        }

        let deduped = dedupCandidateURLs(candidates)
        if deduped.isEmpty {
            throw "lc.tweakView.error.noTweakInPackage".loc
        }
        await startInstallTweak(deduped)
    }

    private func findDebDataArchives(in rootURL: URL) throws -> [URL] {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return files.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasPrefix("data.tar")
        }.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func dedupCandidateURLs(_ candidates: [URL]) -> [URL] {
        var seen = Set<String>()
        var deduped: [URL] = []
        for url in candidates {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                deduped.append(url)
            }
        }
        return deduped.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func collectTweakCandidates(in rootURL: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var candidates: [URL] = []
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            if !fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
                continue
            }
            if isDir.boolValue {
                if fileURL.lastPathComponent.hasSuffix(".framework") {
                    candidates.append(fileURL)
                    enumerator.skipDescendants()
                }
                continue
            }
            if fileURL.lastPathComponent.hasSuffix(".dylib") {
                candidates.append(fileURL)
            }
        }
        return candidates.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}

struct LCTweaksView: View {
    @Binding var tweakFolders : [String]
    @StateObject private var moveContext = LCTweakMoveContext()
    
    var body: some View {
        NavigationView {
            LCTweakFolderView(baseUrl: LCPath.tweakPath, isRoot: true, tweakFolders: $tweakFolders)
        }
        .environmentObject(moveContext)
        .navigationViewStyle(StackNavigationViewStyle())

    }
}
