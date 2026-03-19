//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import SwiftUI
import Foundation

// 🔹 1. 透過 Extension 補齊現有 Enum 的屬性
extension LCTabIdentifier {
    var title: String {
        switch self {
        case .sources: return "lc.tabView.sources".loc
        case .apps: return "lc.tabView.apps".loc
        case .tweaks: return "lc.tabView.tweaks".loc
        case .explore: return "Explore"
        case .settings: return "lc.tabView.settings".loc
        case .cache: return "Manager"
        case .search: return "Search"
        }
    }
    
    var icon: String {
        switch self {
        case .sources: return "books.vertical"
        case .apps: return "square.stack.3d.up.fill"
        case .tweaks: return "wrench.and.screwdriver"
        case .explore: return "safari.fill"
        case .settings: return "gearshape.fill"
        case .cache: return "internaldrive"
        case .search: return "magnifyingglass"
        }
    }
}

struct LCTabView: View {
    @Binding var appDataFolderNames: [String]
    @Binding var tweakFolderNames: [String]
    
    // 🟢 核心：使用本地 State 驅動
    @State private var selectedTab: LCTabIdentifier
    
    @ObservedObject var sharedModel = DataManager.shared.model
    @State var errorShow = false
    @State var errorInfo = ""
    @State var shouldToggleMainWindowOpen = false 
    @EnvironmentObject var sceneDelegate: SceneDelegate
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)

    init(appDataFolderNames: Binding<[String]>, tweakFolderNames: Binding<[String]>) {
        self._appDataFolderNames = appDataFolderNames
        self._tweakFolderNames = tweakFolderNames
        // 從全域模型讀取初始值
        self._selectedTab = State(initialValue: DataManager.shared.model.selectedTab)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 🔥 2. 確保 Switch 窮舉所有 Case (包含 .search)
            VStack {
                switch selectedTab {
                case .sources:
                    LCSourcesView()
                case .apps:
                    LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
                case .tweaks:
                    LCTweaksView(tweakFolders: $tweakFolderNames)
                case .explore, .search: // 將 search 暫時指向 explore 或建立新 View
                    ExploreView()
                case .settings:
                    LCSettingsView(appDataFolderNames: $appDataFolderNames)
                case .cache:
                    LCCacheManagementView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 🔧 3. 自訂底部工具欄
            customBottomBar
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {})
            Button("lc.common.copy".loc, action: { copyError() })
        } message: {
            Text(errorInfo)
        }
        .task {
            await performInitialChecks()
        }
        .onChange(of: selectedTab) { newValue in
            sharedModel.selectedTab = newValue
        }
        .onChange(of: sharedModel.selectedTab) { newValue in
            if selectedTab != newValue {
                selectedTab = newValue
            }
        }
        .onReceive(pub) { out in
            handleSceneDisconnect(out)
        }
        .onOpenURL { url in
            dispatchURL(url: url)
        }
    }
    
    private var customBottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.1)
            HStack(spacing: 0) {
                // 左側功能組
                tabButton(tab: .sources)
                tabButton(tab: .apps)
                tabButton(tab: .tweaks)
                
                Spacer(minLength: 25)
                
                // 右側功能組
                tabButton(tab: .explore)
                tabButton(tab: .settings)
                tabButton(tab: .cache)
            }
            .padding(.top, 10)
            .padding(.bottom, (UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 20) > 0 ? (UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 20) : 12)
        }
        .background(.ultraThinMaterial)
    }
    
    private func tabButton(tab: LCTabIdentifier) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.snappy(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 21, weight: selectedTab == tab ? .semibold : .regular))
                    .scaleEffect(selectedTab == tab ? 1.1 : 1.0)
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .foregroundColor(selectedTab == tab ? .accentColor : .primary.opacity(0.45))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 邏輯檢查擴展
extension LCTabView {
    
    
    // 解決 Immutable 賦值報錯的輔助方法
    private func triggerError(message: String) {
        self.errorInfo = message
        self.errorShow = true
    }

    
    
    
}


// MARK: - 邏輯擴展

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
