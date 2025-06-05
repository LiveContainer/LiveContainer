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
    
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @EnvironmentObject var model: SharedModel
    @State var shouldToggleMainWindowOpen = false
    @Environment(\.scenePhase) var scenePhase
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)
    
    var body: some View {
        TabView(selection: $model.selectedTab) {
            LCSourcesView()
                .tabItem {
                    Label("lc.tabView.sources".loc, systemImage: "tray.and.arrow.down")
                }
                .tag(0)
            LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
                .tabItem {
                    Label("lc.tabView.apps".loc, systemImage: "square.stack.3d.up.fill")
                }
                .tag(1)
            if DataManager.shared.model.multiLCStatus != 2 {
                LCTweaksView(tweakFolders: $tweakFolderNames)
                    .tabItem{
                        Label("lc.tabView.tweaks".loc, systemImage: "wrench.and.screwdriver")
                    }
                    .tag(2)

                LCSettingsView(appDataFolderNames: $appDataFolderNames)
                    .tabItem {
                        Label("lc.tabView.settings".loc, systemImage: "gearshape.fill")
                    }
                    .tag(3)
            } else {
                LCSettingsView(appDataFolderNames: $appDataFolderNames)
                    .tabItem {
                        Label("lc.tabView.settings".loc, systemImage: "gearshape.fill")
                    }
                    .tag(2)
            }
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
        .onAppear() {
            closeDuplicatedWindow()
            checkLastLaunchError()
            checkTeamId()
        }
        .onReceive(pub) { out in
            if let scene1 = sceneDelegate.window?.windowScene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                if shouldToggleMainWindowOpen {
                    DataManager.shared.model.mainWindowOpened = false
                }
            }
        }
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
        
        guard let errorStr else {
            return
        }
        UserDefaults.standard.removeObject(forKey: "error")
        errorInfo = errorStr
        errorShow = true
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }
    
    func checkTeamId() {
        if let certificateTeamId = UserDefaults.standard.string(forKey: "LCCertificateTeamId") {
            if DataManager.shared.model.multiLCStatus != 2 {
                return
            }
            
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if certificateTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
            return
        }
        
        guard let currentTeamId = LCUtils.teamIdentifier() else {
            print("Failed to determine team id.")
            return
        }
        
        if DataManager.shared.model.multiLCStatus == 2 {
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if currentTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
        }
        UserDefaults.standard.set(currentTeamId, forKey: "LCCertificateTeamId")
    }
}
