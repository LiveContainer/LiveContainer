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
    
    @State var errorShow = false
    @State var errorInfo = ""
    @State var previousSelectedTab : LCTabIdentifier = .apps
    
    @EnvironmentObject var sharedModel : SharedModel
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State var shouldToggleMainWindowOpen = false
    @Environment(\.scenePhase) var scenePhase
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)
    
 

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if sharedModel.selectedTab == .sources {
                    LCSourcesView()
                } else if sharedModel.selectedTab == .apps {
                    LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
                } else if sharedModel.selectedTab == .tweaks {
                    LCTweaksView(tweakFolders: $tweakFolderNames)
                } else if sharedModel.selectedTab == .settings {
                    LCSettingsView(appDataFolderNames: $appDataFolderNames)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            customToolbar 
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        
      .fullScreenCover(item: $sharedModel.pendingIPhoneApp) { appInfo in
    ZStack {
        Color.black.ignoresSafeArea()
        
        if #available(iOS 16.1, *) {
            
            if UserDefaults.standard.bool(forKey: "LCNativeFullscreen") {
                
                AppSceneViewSwiftUI(
                    show: .constant(true),
                    bundleId: appInfo.bundleId,
                    dataUUID: appInfo.dataUUID,
                    initSize: UIScreen.main.bounds.size,
                    onAppInitialize: { _, _ in }
                )
                .ignoresSafeArea()
                .id("tab_native_\(appInfo.bundleId)")
                
            } else if sharedModel.isiPhoneMode {
                
                IPhoneRunnerView(appInfo: appInfo)
                    .id("tab_iphone_\(appInfo.bundleId)")
                    
            } else {
                
                IPadRunnerView(appInfo: appInfo)
                    .id("tab_ipad_\(appInfo.bundleId)")
            }
        } else {
            Text("iOS 16.1+ Required")
                .foregroundColor(.white)
        }
        
        FloatingBackButton(isPresented: $sharedModel.pendingIPhoneApp)
            .zIndex(99)
    }
}

        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {})
            Button("lc.common.copy".loc, action: { copyError() })
        } message: { 
            Text(errorInfo) 
        }
        .task {
            closeDuplicatedWindow()
            checkLastLaunchError()
            checkTeamId()
            checkBundleId()
            checkGetTaskAllow()
            checkPrivateContainerBookmark()
            if let runningApp = sharedModel.apps.first(where: { $0.isAppRunning }) {
        print("[LC] 檢測到運行中狀態，正在嘗試接回視圖...")
        Task {
            do {
                try await runningApp.runApp() 
            } catch {
                print("[LC] 自動恢復失敗: \(error)")
            }
        }
    }
        }
        .onReceive(pub) { out in
            if let scene1 = sceneDelegate.window?.windowScene, 
               let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                if shouldToggleMainWindowOpen { 
                    DataManager.shared.model.mainWindowOpened = false 
                }
            }
        }
        .onOpenURL { url in 
            dispatchURL(url: url) 
        }
    }

    var customToolbar: some View {
        HStack(spacing: 30) {
            if DataManager.shared.model.multiLCStatus != 2 {
                tabItem(title: "lc.tabView.sources".loc, icon: "books.vertical", id: .sources)
            }
            tabItem(title: "lc.tabView.apps".loc, icon: "square.stack.3d.up.fill", id: .apps)
            if DataManager.shared.model.multiLCStatus != 2 {
                tabItem(title: "lc.tabView.tweaks".loc, icon: "wrench.and.screwdriver", id: .tweaks)
            }
            tabItem(title: "lc.tabView.settings".loc, icon: "gearshape.fill", id: .settings)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemBackground).shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1))
    }

    func tabItem(title: String, icon: String, id: LCTabIdentifier) -> some View {
        Button(action: { sharedModel.selectedTab = id }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(sharedModel.selectedTab == id ? .blue : .gray)
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
