//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import SwiftUI // 必須確保這行在最上方
import Foundation

struct LCTabView: View {
    @Binding var appDataFolderNames: [String]
    @Binding var tweakFolderNames: [String]
    
    // 🔴 核心修復 1：使用本地 State 確保 UI 刷新優先權最高
    @State private var localSelectedTab: LCTabIdentifier = .apps
    
    @ObservedObject var sharedModel = DataManager.shared.model
    @State var errorShow = false
    @State var errorInfo = ""
    @State var shouldToggleMainWindowOpen = false 
    
    @EnvironmentObject var sceneDelegate: SceneDelegate
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)

        var body: some View {
        VStack(spacing: 0) {
            // --- 內容區域 ---
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // --- iOS 26 透明風格 Toolbar ---
            ios26TransparentToolbar
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        // 修正：將 Alert 移到最外層，避免干擾內部切換
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {})
            Button("lc.common.copy".loc, action: { copyError() })
        } message: {
            Text(errorInfo)
        }
        .task {
            // 確保初始化同步是瞬間完成的
            localSelectedTab = sharedModel.selectedTab
            await performInitialChecks()
        }
        .onChange(of: localSelectedTab) { newValue in
            sharedModel.selectedTab = newValue
        }
        .onChange(of: sharedModel.selectedTab) { newValue in
            // 如果是外部（如 URL）觸發的，強制更新本地狀態
            if localSelectedTab != newValue {
                withAnimation(.snappy) {
                    localSelectedTab = newValue
                }
            }
        }
        .onReceive(pub) { out in
            handleSceneDisconnect(out)
        }
        .onOpenURL { url in
            dispatchURL(url: url)
        }
    }

    // 🔴 核心修復：將視圖生成獨立出來，並強制加上 transition
    @ViewBuilder
    private var mainContent: some View {
        ZStack {
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
        .transition(.opacity.combined(with: .scale(scale: 0.98))) // 增加切換感
        .id(localSelectedTab) // 🔴 必須是這個，不要加字串前綴，確保類型一致
    }


// MARK: - Toolbar 實作
extension LCTabView {
    private var ios26TransparentToolbar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.12)
            
            HStack(spacing: 0) {
                tabItem(title: "Sources", icon: "books.vertical", id: .sources)
                tabItem(title: "Apps", icon: "square.stack.3d.up.fill", id: .apps)
                tabItem(title: "Tweaks", icon: "wrench.and.screwdriver", id: .tweaks)
                
                Spacer(minLength: 25) // iOS 26 的寬間距美學
                
                tabItem(title: "Explore", icon: "safari.fill", id: .explore)
                tabItem(title: "Settings", icon: "gearshape.fill", id: .settings)
                tabItem(title: "Manager", icon: "internaldrive", id: .cache)
            }
            .padding(.top, 12)
            .padding(.bottom, (UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 20) > 0 ? (UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 20) : 12)
        }
        .background(.ultraThinMaterial) // 透明磨砂質感
    }

        private func tabItem(title: String, icon: String, id: LCTabIdentifier) -> some View {
        // 使用底層的 contentShape 確保整塊區域都能點擊
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: localSelectedTab == id ? .semibold : .regular))
                .scaleEffect(localSelectedTab == id ? 1.1 : 1.0)
            Text(title)
                .font(.system(size: 10, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle()) // 🔴 這行非常重要
        .foregroundColor(localSelectedTab == id ? .accentColor : .primary.opacity(0.45))
        .onTapGesture {
            // 🔴 使用 TapGesture 替代 Button 有時能解決複雜自定義 Bar 的響應問題
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.snappy(duration: 0.2)) {
                self.localSelectedTab = id
            }
            print("Tab switched to: \(id)") // 檢查 Debug Console 是否有印出
        }
    }

}




// MARK: - 邏輯檢查 (修復 self is immutable 錯誤)











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
