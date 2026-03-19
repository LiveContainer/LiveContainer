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
    @State var previousSelectedTab: LCTabIdentifier = .apps
    
    @EnvironmentObject var sharedModel: SharedModel
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State var shouldToggleMainWindowOpen = false
    @Environment(\.scenePhase) var scenePhase
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)

    var body: some View {
        VStack(spacing: 0) {
            
            ZStack {
                
                Group {
                    switch sharedModel.selectedTab {
                    case .sources:
                        LCSourcesView()
                    case .apps:
                        LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
                    case .tweaks:
                        LCTweaksView(tweakFolders: $tweakFolderNames)
                    case .explore:
                        
                        ExploreView() 
                    case .settings:
                        LCSettingsView(appDataFolderNames: $appDataFolderNames)
                    case .cache:
                        LCCacheManagementView()
                    default:
                        LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
                    }
                }
            }
            .id(sharedModel.selectedTab) 
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            
            ios26TransparentToolbar
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {})
            Button("lc.common.copy".loc, action: { copyError() })
        } message: { 
            Text(errorInfo) 
        }
        .task { await performInitialChecks() }
        .onOpenURL { url in dispatchURL(url: url) }
    }
}


extension LCTabView {
    private var ios26TransparentToolbar: some View {
        VStack(spacing: 0) {
            
            Divider().opacity(0.15)
            
            HStack(spacing: 0) {
                
                Group {
                    tabItem(title: "Sources", icon: "books.vertical", id: .sources)
                    tabItem(title: "Apps", icon: "square.stack.3d.up.fill", id: .apps)
                    tabItem(title: "Tweaks", icon: "wrench.and.screwdriver", id: .tweaks)
                }
                
                Spacer(minLength: 25) 
                
                
                Group {
                    tabItem(title: "Explore", icon: "safari.fill", id: .explore)
                    tabItem(title: "Settings", icon: "gearshape.fill", id: .settings)
                    tabItem(title: "Manager", icon: "internaldrive", id: .cache)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 15)
        }
        
        .background(.ultraThinMaterial) 
        
        .background(Color(UIColor.systemBackground).opacity(0.01))
    }

    private func tabItem(title: String, icon: String, id: LCTabIdentifier) -> some View {
        Button(action: {
            
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            
            withAnimation(.snappy(duration: 0.25)) {
                sharedModel.selectedTab = id
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: sharedModel.selectedTab == id ? .semibold : .regular))
                    .symbolVariant(sharedModel.selectedTab == id ? .fill : .none)
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(sharedModel.selectedTab == id ? .accentColor : .primary.opacity(0.5))
            .contentShape(Rectangle()) 
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
