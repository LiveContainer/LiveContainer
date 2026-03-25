//
//  LCAppBanner.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

protocol LCAppBannerDelegate {
    func removeApp(app: LCAppModel)
    func installMdm(data: Data)
    func openNavigationView(view: AnyView)
    func promptForGeneratedIconStyle() async -> GeneratedIconStyle?
}

struct LCAppBanner : View {
    @State var appInfo: LCAppInfo
    var delegate: LCAppBannerDelegate
    
    @ObservedObject var model : LCAppModel
    
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    
    @StateObject private var appRemovalAlert = YesNoHelper()
    @StateObject private var appFolderRemovalAlert = YesNoHelper()
    
    @State private var saveIconExporterShow = false
    @State private var saveIconFile : ImageDocument?
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    @AppStorage("dynamicColors", store: LCUtils.appGroupUserDefault) var dynamicColors = true
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) var darkModeIcon = false
    @AppStorage("LCLaunchInMultitaskMode") var launchInMultitaskMode = false
    @State private var mainColor : Color
    @State private var icon: UIImage
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var sharedModel : SharedModel
    
    init(appModel: LCAppModel, delegate: LCAppBannerDelegate, appDataFolders: Binding<[String]>, tweakFolders: Binding<[String]>) {
        _appInfo = State(initialValue: appModel.appInfo)
        _appDataFolders = appDataFolders
        _tweakFolders = tweakFolders
        self.delegate = delegate
        
        _model = ObservedObject(wrappedValue: appModel)
        _mainColor = State(initialValue: Color.clear)
        _icon = State(initialValue: appModel.appInfo.iconIsDarkIcon(LCUtils.appGroupUserDefault.bool(forKey: "darkModeIcon")))
        _mainColor = State(initialValue: extractMainHueColor())

    }
    @State private var mainHueColor: CGFloat? = nil
    
    var body: some View {

        HStack {
            HStack {
                Image(uiImage: icon)
                    .resizable().resizable().frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width:16, height: 16)))

                VStack (alignment: .leading, content: {
                    let color = (dynamicColors ? mainColor : Color("FontColor"))
                    // note: keep this so the color updates when toggling dark mode
                    let textColor = colorScheme == .dark ? color.readableTextColor() : color.readableTextColor()
                    HStack {
                        Text(appInfo.displayName()).font(.system(size: 16)).bold()
                        if model.uiIsShared {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("BadgeColor"))
                                )
                        }
                        if model.uiIsJITNeeded {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("JITBadgeColor"))
                                )
                        }
#if is32BitSupported
                        if model.uiIs32bit {
                            Text("32")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("32BitBadgeColor"))
                                )
                        }
#endif
                        if model.uiIsLocked && !model.uiIsHidden {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("BadgeColor"))
                                )
                        }
                        if model.uiSpoofCamera {
                            Image(systemName: "camera.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.red)
                                    // .frame(width: 16, height: 16)
                            // Image(systemName: "camera.fill")
                            //     .font(.system(size: 10, weight: .bold))
                            //     .foregroundColor(.red)
                            //     .frame(width: 16, height:16)
                            //     .background(
                            //         Capsule().fill(Color.red)
                            //     )
                        }
                        if model.uiDeviceSpoofingEnabled {
                            Image(systemName: "iphone.gen3")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                        }
                    }
                    
                    HStack {
                        Text("\(appInfo.version() ?? "") - \(appInfo.bundleIdentifier()!)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    
                    // Container name
                    if let selectedContainer = model.uiSelectedContainer {
                        HStack {
                            Text(selectedContainer.name)
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Spacer()
                        }
                        
                        // GPS Location display
                        if model.uiSpoofGPS {
                            HStack {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.red)
                                
                                Text(locationDisplayText)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                appContentView
                                
                                Spacer()
                            }
                        }
                    }
                })
            }
            .allowsHitTesting(false)
            Spacer()
            Button {
                if #available(iOS 16.0, *), launchInMultitaskMode {
                     if let currentDataFolder = model.uiSelectedContainer?.folderName,
                        MultitaskManager.isUsing(container: currentDataFolder) {
                         var found = false
                         if #available(iOS 16.1, *) {
                             found = MultitaskWindowManager.openExistingAppWindow(dataUUID: currentDataFolder)
                         }
                         if !found {
                             found = MultitaskDockManager.shared.bringMultitaskViewToFront(uuid: currentDataFolder)
                         }
                         if found {
                             return
                         }
                     }
                     
                    Task{ await runApp(multitask: true) }
                } else {
                    Task{ await runApp(multitask: false) }
                }
            } label: {
                if !model.isSigningInProgress {
                    Text("lc.appBanner.run".loc).bold().foregroundColor(.white)
                        .lineLimit(1)
                        .frame(height:32)
                        .minimumScaleFactor(0.1)
                } else {
                    ProgressView().progressViewStyle(.circular)
                }

            }
            .buttonStyle(BasicButtonStyle())
            .padding()
            .frame(idealWidth: 70)
            .frame(height: 32)
            .fixedSize()
            .background(GeometryReader { g in
                if !model.isSigningInProgress {
                    Capsule().fill(dynamicColors ? mainColor : Color("FontColor"))
                } else {
                    let w = g.size.width
                    let h = g.size.height
                    Capsule()
                        .fill(dynamicColors ? mainColor : Color("FontColor")).opacity(0.2)
                    Circle()
                        .fill(dynamicColors ? mainColor : Color("FontColor"))
                        .frame(width: w * 2, height: w * 2)
                        .offset(x: (model.signProgress - 2) * w, y: h/2-w)
                }

            })
            .clipShape(Capsule())
            .disabled(model.isAppRunning)
        }
        .padding()
        .frame(height: 88)
        .background {
            RoundedRectangle(cornerSize: CGSize(width:22, height: 22)).fill(dynamicColors ? mainColor.opacity(0.5) : Color("AppBannerBG"))
                .onTapGesture(count: 2) {
                    openSettings()
                }
        }
        .fileExporter(
            isPresented: $saveIconExporterShow,
            document: saveIconFile,
            contentType: .image,
            defaultFilename: "\(appInfo.displayName()!) Icon.png",
            onCompletion: { result in
            
        })
        .betterContextMenu(menuProvider: makeContextMenu)
        .alert("lc.appBanner.confirmUninstallTitle".loc, isPresented: $appRemovalAlert.show) {
            Button(role: .destructive) {
                appRemovalAlert.close(result: true)
            } label: {
                Text("lc.appBanner.uninstall".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                appRemovalAlert.close(result: false)
            }
        } message: {
            Text("lc.appBanner.confirmUninstallMsg %@".localizeWithFormat(appInfo.displayName()!))
        }
        .alert("lc.appBanner.deleteDataTitle".loc, isPresented: $appFolderRemovalAlert.show) {
            Button(role: .destructive) {
                appFolderRemovalAlert.close(result: true)
            } label: {
                Text("lc.common.delete".loc)
            }
            Button("lc.common.no".loc, role: .cancel) {
                appFolderRemovalAlert.close(result: false)
            }
        } message: {
            Text("lc.appBanner.deleteDataMsg %@".localizeWithFormat(appInfo.displayName()!))
        }
        
        .alert("lc.common.error".loc, isPresented: $errorShow){
            Button("lc.common.ok".loc, action: {
            })
            Button("lc.common.copy".loc, action: {
                copyError()
            })
        } message: {
            Text(errorInfo)
        }
        .onChange(of: darkModeIcon) { newVal in
            icon = appInfo.iconIsDarkIcon(newVal)
            mainColor = extractMainHueColor()
        }
    }

    // MARK: - Computed Properties

    private var currentColor: Color {
        dynamicColors ? mainColor : Color("FontColor")
    }

    private var currentTextColor: Color {
        let color = currentColor
        return colorScheme == .dark ? color.readableTextColor() : color.readableTextColor()
    }

    @ViewBuilder
    private var appContentView: some View {
        // App name and badges
        appNameRow(textColor: currentTextColor)

        // Version and bundle ID
        Text("\(appInfo.version() ?? "?") - \(appInfo.bundleIdentifier() ?? "?")")
            .font(.system(size: 12))
            .foregroundColor(currentTextColor)

        // Remark if exists
        if !model.uiRemark.isEmpty {
            Text(model.uiRemark)
                .font(.system(size: 10))
                .foregroundColor(currentTextColor.opacity(0.8))
                .lineLimit(1)
        }

        // Container name
        Text(model.uiSelectedContainer?.name ?? "lc.appBanner.noDataFolder".loc)
            .font(.system(size: 8))
            .foregroundColor(currentTextColor)

        // Storage size
        Text("Uses \(appInfo.bundleSize()) of storage")
            .font(.system(size: 8))
            .foregroundColor(currentTextColor.opacity(0.7))
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func appNameRow(textColor: Color) -> some View {
        HStack {
            Text(appInfo.displayName()).font(.system(size: 16)).bold()
            if model.uiIsShared {
                badgeView(systemName: "arrowshape.turn.up.left.fill", color: "BadgeColor")
            }
            if model.uiIsJITNeeded {
                badgeView(systemName: "bolt.fill", color: "JITBadgeColor")
            }
#if is32BitSupported
            if model.uiIs32bit {
                Text("32")
                    .font(.system(size: 8))
                    .foregroundColor(.white)
                    .frame(width: 16, height:16)
                    .background(Capsule().fill(Color("32BitBadgeColor")))
            }
#endif
            if model.uiIsLocked && !model.uiIsHidden {
                badgeView(systemName: "lock.fill", color: "BadgeColor")
            }
        }
    }

    private func badgeView(systemName: String, color: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 8))
            .foregroundColor(.white)
            .frame(width: 16, height:16)
            .background(Capsule().fill(Color(color)))
    }

    func makeContextMenu() -> UIMenu {
        var menuChildren: [UIMenuElement] = []

        // 1. Containers Picker (Equivalent to a Menu with single selection)
        if model.uiContainers.count > 1 {
            let containerActions = model.uiContainers.map { container in
                UIAction(title: container.name,
                         state: container == model.uiSelectedContainer ? .on : .off) { _ in
                    model.uiSelectedContainer = container
                }
            }
            let containerMenu = UIMenu(title: "Containers", options: .displayInline, children: containerActions)
            menuChildren.append(containerMenu)
        }

        // 2. Main Section
        var sectionChildren: [UIMenuElement] = []

        // Open Data Folder
        if !model.uiIsShared, model.uiSelectedContainer != nil {
            let openFolder = UIAction(title: "lc.appBanner.openDataFolder".loc,
                                      image: UIImage(systemName: "folder")) { _ in
                openDataFolder()
            }
            sectionChildren.append(openFolder)
        }

        // Multitask Toggle
        if #available(iOS 16.0, *) {
            let runTitle = launchInMultitaskMode ? "lc.appBanner.run".loc : "lc.appBanner.multitask".loc
            let runImage = launchInMultitaskMode ? "play.fill" : "macwindow.badge.plus"

            let multitaskAction = UIAction(title: runTitle, image: UIImage(systemName: runImage)) { _ in
                Task { await runApp(multitask: !launchInMultitaskMode) }
            }
            sectionChildren.append(multitaskAction)
        }

        // Submenu: Add to Home Screen
        let subMenuActions = [
            UIAction(title: "lc.appBanner.copyLaunchUrl".loc, image: UIImage(systemName: "link")) { _ in
                copyLaunchUrl()
            },
            UIAction(title: "lc.appBanner.saveAppIcon".loc, image: UIImage(systemName: "square.and.arrow.down")) { _ in
                Task { await saveIcon() }
            },
            UIAction(title: "lc.appBanner.createAppClip".loc, image: UIImage(systemName: "appclip")) { _ in
                Task { await openSafariViewToCreateAppClip() }
            }
        ]
        let addToHomeMenu = UIMenu(title: "lc.appBanner.addToHomeScreen".loc,
                                   image: UIImage(systemName: "plus.app"),
                                   children: subMenuActions)
        sectionChildren.append(addToHomeMenu)

        // Settings
        let settingsAction = UIAction(title: "lc.tabView.settings".loc, image: UIImage(systemName: "gear")) { _ in
            openSettings()
        }
        sectionChildren.append(settingsAction)

        // Destructive Uninstall
        if !model.uiIsShared {
            let uninstallAction = UIAction(title: "lc.appBanner.uninstall".loc,
                                           image: UIImage(systemName: "trash"),
                                           attributes: .destructive) { _ in
                Task { await uninstall() }
            }
            sectionChildren.append(uninstallAction)
        }

        // Wrap the section in an inline menu to mimic SwiftUI Section behavior
        let mainSection = UIMenu(title: appInfo.relativeBundlePath, options: .displayInline, children: sectionChildren)
        menuChildren.append(mainSection)

        return UIMenu(title: "", children: menuChildren)
    }

    // MARK: - Functions
    
    func runApp(multitask: Bool) async {
        if appInfo.isLocked && !sharedModel.isHiddenAppUnlocked {
            do {
                if !(try await LCUtils.authenticateUser()) {
                    return
                }
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
                return
            }
        }

        do {
            try await model.runApp(multitask: multitask)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    
    func openSettings() {
        delegate.openNavigationView(view: AnyView(LCAppSettingsView(model: model, appDataFolders: $appDataFolders, tweakFolders: $tweakFolders)))
    }
    
    
    func openDataFolder() {
        let url = URL(string:"shareddocuments://\(LCPath.dataPath.path)/\(model.uiSelectedContainer!.folderName)")
        UIApplication.shared.open(url!)
    }
    

    
    func uninstall() async {
        do {
            if let result = await appRemovalAlert.open(), !result {
                return
            }
            
            var doRemoveAppFolder = false
            let containers = appInfo.containers
            if !containers.isEmpty {
                if let result = await appFolderRemovalAlert.open() {
                    doRemoveAppFolder = result
                }
                
            }
            
            let fm = FileManager()
            try fm.removeItem(atPath: self.appInfo.bundlePath()!)
            self.delegate.removeApp(app: self.model)
            if doRemoveAppFolder {
                for container in containers {
                    let dataUUID = container.folderName
                    let dataFolderPath = container.containerURL
                    if fm.fileExists(atPath: dataFolderPath.path) {
                        try fm.removeItem(at: dataFolderPath)
                    }
                    LCUtils.removeAppKeychain(dataUUID: dataUUID)
                    
                    DispatchQueue.main.async {
                        self.appDataFolders.removeAll(where: { f in
                            return f == dataUUID
                        })
                    }
                }
            }
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    
    func copyLaunchUrl() {
        if let fn = model.uiSelectedContainer?.folderName {
            UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(appInfo.relativeBundlePath!)&container-folder-name=\(fn)"
        } else {
            UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(appInfo.relativeBundlePath!)"
        }
        
    }
    
    func openSafariViewToCreateAppClip() async {
        guard let style = await delegate.promptForGeneratedIconStyle() else {
            return
        }
        
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: appInfo.generateWebClipConfig(withContainerId: model.uiSelectedContainer?.folderName, iconStyle: style)!, format: .xml, options: 0)
            delegate.installMdm(data: data)
        } catch  {
            errorShow = true
            errorInfo = error.localizedDescription
        }

    }
    
    func saveIcon() async {
        guard let style = await delegate.promptForGeneratedIconStyle() else {
            return
        }
        
        let img = appInfo.generateLiveContainerWrappedIcon(with: style)!
        self.saveIconFile = ImageDocument(uiImage: img)
        self.saveIconExporterShow = true
    }
    
    func extractMainHueColor() -> Color {
        if !darkModeIcon, let cachedColor = appInfo.cachedColor {
            return Color(uiColor: cachedColor)
        } else if darkModeIcon, let cachedColor = appInfo.cachedColorDark {
            return Color(uiColor: cachedColor)
        }
        
        guard let cgImage = appInfo.iconIsDarkIcon(darkModeIcon).cgImage else { return Color.clear }

        let width = 1
        let height = 1
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: 4)
        
        guard let context = CGContext(data: &pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return Color.clear
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let red = CGFloat(pixelData[0]) / 255.0
        let green = CGFloat(pixelData[1]) / 255.0
        let blue = CGFloat(pixelData[2]) / 255.0
        
        let averageColor = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        averageColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        if brightness < 0.1 && saturation < 0.1 {
            return Color.red
        }
        
        if brightness < 0.3 {
            brightness = 0.3
        }
        
        let ans = Color(hue: hue, saturation: saturation, brightness: brightness)
        if darkModeIcon {
            appInfo.cachedColorDark = UIColor(ans)
        } else {
            appInfo.cachedColor = UIColor(ans)
        }
        
        
        return ans
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }


    // MARK: - Export IPA Functions

    func exportIPA(includeData: Bool) async {
        do {
            let exportURL = try await createExportIPA(includeData: includeData)

            // Show share sheet
            await MainActor.run {
                let activityVC = UIActivityViewController(
                    activityItems: [exportURL],
                    applicationActivities: nil
                )

                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    activityVC.popoverPresentationController?.sourceView = rootVC.view
                    rootVC.present(activityVC, animated: true)
                }
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func createExportIPA(includeData: Bool) async throws -> URL {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("IPAExport-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let payloadDir = tmpDir.appendingPathComponent("Payload")
        try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        let appBundlePath = URL(fileURLWithPath: appInfo.bundlePath()!)
        let destAppPath = payloadDir.appendingPathComponent(appBundlePath.lastPathComponent)

        // Copy app bundle
        try fm.copyItem(at: appBundlePath, to: destAppPath)

        if includeData, let containerFolder = model.uiSelectedContainer?.folderName {
            // Create data folder inside app bundle
            let dataPath = LCPath.dataPath.appendingPathComponent(containerFolder)
            let destDataPath = destAppPath.appendingPathComponent("LCUserData")

            if fm.fileExists(atPath: dataPath.path) {
                try fm.copyItem(at: dataPath, to: destDataPath)
            }
        }

        // Zip it
        let ipaName = "\(appInfo.displayName()!)-\(includeData ? "WithData" : "AppOnly").ipa"
        let ipaPath = fm.temporaryDirectory.appendingPathComponent(ipaName)

        // Remove old IPA if exists
        try? fm.removeItem(at: ipaPath)

        // Create ZIP
        try await zipDirectory(sourceURL: tmpDir, destinationURL: ipaPath)

        // Cleanup
        try? fm.removeItem(at: tmpDir)

        return ipaPath
    }
    func zipDirectory(sourceURL: URL, destinationURL: URL) async throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            coordinator.coordinate(readingItemAt: sourceURL, options: [.forUploading], error: &coordinatorError) { zipURL in
                do {
                    // The zipURL is temporary, copy it before it gets deleted
                    try FileManager.default.copyItem(at: zipURL, to: destinationURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if let coordinatorError = coordinatorError {
                continuation.resume(throwing: coordinatorError)
            }
        }
    }

    
    private var locationDisplayText: String {
        if !model.uiSpoofLocationName.isEmpty && model.uiSpoofLocationName != "Unknown Location" {
            return model.uiSpoofLocationName
        } else {
            return String(format: "%.4f, %.4f", model.uiSpoofLatitude, model.uiSpoofLongitude)
        }
    }

}


struct LCAppSkeletonBanner: View {
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 60)
            
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 8)
            }
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 70, height: 32)
        }
        .padding()
        .frame(height: 88)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.gray.opacity(0.1)))
    }
    
}
