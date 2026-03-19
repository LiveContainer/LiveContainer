//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

struct LCTabView: View {
    @Binding var appDataFolderNames: [String]
    @Binding var tweakFolderNames: [String]
    
    // --- 狀態儲存區 ---
    // 使用 @AppStorage，這樣使用者下次開啟 App 時會停留在上次的分頁
    @AppStorage("selectedTabKey") private var localSelectedTab: LCTabIdentifier = .apps
    
    @ObservedObject var sharedModel = DataManager.shared.model
    @State var errorShow = false
    @State var errorInfo = ""
    @EnvironmentObject var sceneDelegate: SceneDelegate
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. 內容區域
            ZStack {
                currentPage
            }
            // 關鍵：使用 localSelectedTab 作為 ID，確保狀態一變就強制刷新
            .id(localSelectedTab) 
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 2. iOS 26 風格透明 Toolbar
            ios26TransparentToolbar
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .task { await performInitialChecks() }
        // 當本地狀態改變時，同步回全域模型，確保 deepLink 等邏輯正常
        .onChange(of: localSelectedTab) { newValue in
            sharedModel.selectedTab = newValue
        }
    }

    @ViewBuilder
    private var currentPage: some View {
        switch localSelectedTab {
        case .sources: LCSourcesView()
        case .apps: LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
        case .tweaks: LCTweaksView(tweakFolders: $tweakFolderNames)
        case .explore: ExploreView()
        case .settings: LCSettingsView(appDataFolderNames: $appDataFolderNames)
        case .cache: LCCacheManagementView()
        default: LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
        }
    }
}

extension LCTabView {
    private var ios26TransparentToolbar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.15)
            
            HStack(spacing: 0) {
                // 左 3
                tabGroup([.sources, .apps, .tweaks])
                
                Spacer(minLength: 30) // 中間對稱空隙
                
                // 右 3
                tabGroup([.explore, .settings, .cache])
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 15)
        }
        // 🔴 iOS 26 透明背景關鍵：與頂部 Bar 一致的材質
        .background(.ultraThinMaterial) 
    }

    private func tabGroup(_ ids: [LCTabIdentifier]) -> some View {
        ForEach(ids, id: \.self) { id in
            let info = tabInfo(for: id)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                // 使用快彈簧動畫，解決「按了沒反應」的視覺感
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    localSelectedTab = id
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: info.icon)
                        .font(.system(size: 22, weight: localSelectedTab == id ? .semibold : .regular))
                        .scaleEffect(localSelectedTab == id ? 1.15 : 1.0)
                    Text(info.title)
                        .font(.system(size: 10, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(localSelectedTab == id ? .accentColor : .primary.opacity(0.5))
                .contentShape(Rectangle()) // 🔴 確保整個格子都是熱區
            }
        }
    }

    // 輔助函式：統一管理圖標與標題
    private func tabInfo(for id: LCTabIdentifier) -> (title: String, icon: String) {
        switch id {
        case .sources: return ("Sources", "books.vertical")
        case .apps: return ("Apps", "square.stack.3d.up.fill")
        case .tweaks: return ("Tweaks", "wrench.and.screwdriver")
        case .explore: return ("Explore", "safari.fill")
        case .settings: return ("Settings", "gearshape.fill")
        case .cache: return ("Manager", "internaldrive")
        default: return ("", "")
        }
    }
}







extension LCTabView {
    func performInitialChecks() async {
        closeDuplicatedWindow()
        checkLastLaunchError()
        checkTeamId()
        checkBundleId()
        checkGetTaskAllow()
        checkPrivateContainerBookmark()
    }

    func handleSceneDisconnect(_ notification: Notification) {
        if let scene1 = sceneDelegate.window?.windowScene, 
           let scene2 = notification.object as? UIWindowScene, scene1 == scene2 {
            if shouldToggleMainWindowOpen { 
                DataManager.shared.model.mainWindowOpened = false 
            }
        }
    }
    func dispatchURL(url: URL) {
        repeat {
            if url.isFileURL {
                sharedModel.selectedTab = .apps
                break
            }
            if url.scheme?.lowercased() == "sidestore" {
                sharedModel.selectedTab = .apps
                break
            }
            
            guard let host = url.host?.lowercased() else { return }
            
            switch host {
            case "livecontainer-launch", "install", "open-web-page", "open-url":
                sharedModel.selectedTab = .apps
            case "certificate":
                sharedModel.selectedTab = .settings
            case "source":
                sharedModel.selectedTab = .sources
            default:
                return
            }
        } while(false)

        sharedModel.deepLink = url
    }
    
    func closeDuplicatedWindow() {
        if let session = sceneDelegate.window?.windowScene?.session, DataManager.shared.model.mainWindowOpened {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { e in
                print(e)
            }
        } else {
            shouldToggleMainWindowOpen = true
        }
        DataManager.shared.model.mainWindowOpened = true
    }
    
    func checkLastLaunchError() {
        var errorStr = UserDefaults.standard.string(forKey: "error")
        if errorStr == nil && UserDefaults.standard.bool(forKey: "SigningInProgress") {
            errorStr = "lc.signer.crashDuringSignErr".loc
            UserDefaults.standard.removeObject(forKey: "SigningInProgress")
        }
        guard let errorStr else { return }
        UserDefaults.standard.removeObject(forKey: "error")
        errorInfo = errorStr
        errorShow = true
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }
    
    func checkTeamId() {
        if let certificateTeamId = UserDefaults.standard.string(forKey: "LCCertificateTeamId") {
            if DataManager.shared.model.multiLCStatus != 2 { return }
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else { return }
            if certificateTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
            }
            return
        }
        guard let currentTeamId = LCSharedUtils.teamIdentifier() else { return }
        if DataManager.shared.model.multiLCStatus == 2 {
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else { return }
            if currentTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
            }
        }
        UserDefaults.standard.set(currentTeamId, forKey: "LCCertificateTeamId")
    }
    
    func checkBundleId() {
        if UserDefaults.standard.bool(forKey: "LCBundleIdChecked") { return }
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "application-identifier" as CFString, nil), 
              let appIdentifier = value.takeRetainedValue() as? String else {
            errorInfo = "Unable to determine application-identifier"
            errorShow = true
            return
        }
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        var correctBundleId = ""
        if appIdentifier.count > 11 {
            let startIndex = appIdentifier.index(appIdentifier.startIndex, offsetBy: 11)
            correctBundleId = String(appIdentifier[startIndex...])
        }
        if(bundleId != correctBundleId) {
            errorInfo = "lc.settings.bundleIdMismatch %@ %@".localizeWithFormat(bundleId, correctBundleId)
            errorShow = true
        }
        UserDefaults.standard.set(true, forKey: "LCBundleIdChecked")
    }
    
    func checkGetTaskAllow() {
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "get-task-allow" as CFString, nil), 
              (value.takeRetainedValue() as? NSNumber)?.boolValue ?? false else {
            errorInfo = "lc.settings.notDevCert".loc
            errorShow = true
            return
        }
    }
    
    func checkPrivateContainerBookmark() {
        if sharedModel.multiLCStatus == 2 { return }
        if LCUtils.appGroupUserDefault.object(forKey: "LCLaunchExtensionPrivateDocBookmark") != nil { return }
        guard let bookmark = LCUtils.bookmark(for: LCPath.docPath) else {
            errorInfo = "Failed to create bookmark for Documents folder?"
            errorShow = true
            return
        }
        LCUtils.appGroupUserDefault.set(bookmark, forKey: "LCLaunchExtensionPrivateDocBookmark")
    }
    
}
extension View {
    func errorAlert(isPresented: Binding<Bool>, info: String, copyAction: @escaping () -> Void) -> some View {
        self.alert("lc.common.error".loc, isPresented: isPresented) {
            Button("lc.common.ok".loc, action: {})
            Button("lc.common.copy".loc, action: copyAction)
        } message: {
            Text(info)
        }
    }
}
