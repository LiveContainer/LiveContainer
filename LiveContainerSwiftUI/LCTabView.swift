//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import SwiftUI
import Foundation
enum LCTabID: Hashable {
    case sources
    case apps
    case tweaks
    case settings
    case cache
    case search
    case explore
}
// --- 修正 1: 補齊 LCTabIdentifier 的屬性擴充 ---
extension LCTabID {
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
    @State private var selectedTab: LCTabID = .apps
    @ObservedObject var sharedModel = DataManager.shared.model
    @EnvironmentObject var sceneDelegate: SceneDelegate
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 內容區域
            mainContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // iOS 26 懸浮導航欄
            modernTabBar
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }
    
    // --- 視圖分拆 ---
    
    private var mainContentView: some View {
        Group {
            switch selectedTab {
            case .sources: LCSourcesView()
            case .apps: LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
            case .tweaks: LCTweaksView(tweakFolders: $tweakFolderNames)
            case .explore, .search: ExploreView()
            case .settings: LCSettingsView(appDataFolderNames: $appDataFolderNames)
            case .cache: LCCacheManagementView()
            }
        }
        .id(selectedTab)
    }
    
    private var modernTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // 左側三個按鈕
                HStack(spacing: 4) {
                    modernTabButton(tab: .sources)
                    modernTabButton(tab: .apps)
                    modernTabButton(tab: .tweaks)
                }
                
                // 中央過渡間隔 (仿 iOS 26 導航風格)
                Spacer(minLength: 40)
                
                // 右側三個按鈕
                HStack(spacing: 4) {
                    modernTabButton(tab: .explore)
                    modernTabButton(tab: .settings)
                    modernTabButton(tab: .cache)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, safeAreaBottom + 4)
            .background(
                // iOS 26 招牌：超薄玻璃與細膩描邊
                RoundedRectangle(cornerRadius: 0) // 滿版底部導航
                    .fill(.ultraThinMaterial)
                    .overlay(
                        VStack {
                            Divider().opacity(0.2) // 頂部細線
                            Spacer()
                        }
                    )
            )
        }
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: -2)
    }
    
    private func modernTabButton(tab: LCTabID) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // 選中時的發光背板
                    if selectedTab == tab {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Image(systemName: tab.icon)
                        .font(.system(size: 20, weight: selectedTab == tab ? .bold : .medium))
                        .symbolVariant(selectedTab == tab ? .fill : .none)
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                }
                .frame(height: 30)
                
                Text(tab.title)
                    .font(.system(size: 10, weight: selectedTab == tab ? .bold : .regular))
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(StaticButtonStyle()) // 自定義 ButtonStyle 避免點擊閃爍
    }

    private var safeAreaBottom: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.bottom ?? 12
    }
}

// --- 輔助組件 ---

struct StaticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}


    


    
       
// MARK: - 邏輯擴展




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
