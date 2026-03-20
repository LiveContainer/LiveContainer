//
//  LCMultiLCManagementView.swift
//  LiveContainer
//
//  Created by s s on 2025/9/1.
//

import SwiftUI

protocol InstallAnotherLCButtonDelegate {
    func installAnotherLC(name: String) async
}

struct InstallAnotherLCButton : View {
    @State var lcName : String
    @State var detected = false
    let delegate : InstallAnotherLCButtonDelegate
    
    init(lcName: String, delegate: InstallAnotherLCButtonDelegate) {
        self._lcName = State(initialValue: lcName)
        self._detected = State(initialValue: UIApplication.shared.canOpenURL(URL(string: "\(lcName.lowercased())://")!))
        self.delegate = delegate
    }
    
    var body: some View {
        Button {
            Task { await delegate.installAnotherLC(name: lcName)}
        } label: {
            HStack {
                Text(lcName)
                Spacer()
                if detected {
                    Text("✓")
                        .foregroundStyle(.green)
                } else {
                    Text("✗")
                        .foregroundStyle(.gray)
                }

            }
        }
        .onForeground {
            updateInstallStatus()
        }
    }
    
    func updateInstallStatus() {
        detected = UIApplication.shared.canOpenURL(URL(string: "\(lcName.lowercased())://")!)
    }
}

struct LCMultiLCManagementView : View, InstallAnotherLCButtonDelegate {
    @AppStorage("LCMultiAllowGameCategory") var useGameCategory = false
    @AppStorage("LCMultiAllowGameMode") var allowGameMode = false
    @State var errorShow = false
    @State var errorInfo = ""
    @State var successShow = false
    @State var successInfo = ""
    
    @State private var showShareSheet = false
    @State private var shareURL : URL? = nil
    @StateObject private var installLC2Alert = AlertHelper<Int>()
    
    let storeName = LCUtils.getStoreName()
    
    var body: some View {
        List {
            Section {
                Toggle(isOn: $useGameCategory) {
                    Text("lc.settings.multiLCInstall.useGameCategory".loc)
                }
                Toggle(isOn: $allowGameMode) {
                    Text("lc.settings.multiLCInstall.allowGameMode".loc)
                }
            }
            InstallAnotherLCButton(lcName: "LiveContainer2", delegate: self)
            InstallAnotherLCButton(lcName: "LiveContainer3", delegate: self)
        }
        .alert("lc.settings.multiLCInstall".loc, isPresented: $installLC2Alert.show) {
            if(UserDefaults.sideStoreExist()) {
                Button {
                    installLC2Alert.close(result: 2)
                } label: {
                    Text("lc.settings.multiLCInstall.installWithBuiltInSideStore".loc)
                }
            }
            
            Button {
                installLC2Alert.close(result: 1)
            } label: {
                Text("lc.common.continue".loc)
            }
            
            Button("lc.common.cancel".loc, role: .cancel) {
                installLC2Alert.close(result: 0)
            }
        } message: {
            Text("lc.settings.multiLCInstallAlertDesc %@".localizeWithFormat(storeName))
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL = shareURL {
                ActivityViewController(activityItems: [shareURL])
            }
        }
        .navigationTitle("lc.settings.multiLC".loc)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func installAnotherLC(name: String) async {
        if !LCUtils.isAppGroupAltStoreLike() {
            errorInfo = "lc.settings.unsupportedInstallMethod".loc
            errorShow = true
            return;
        }
        
        guard let result = await installLC2Alert.open(), result != 0 else {
            return
        }
        
        do {
            var extraInfo: [String : Any] = [:]
            if useGameCategory {
                extraInfo["LSApplicationCategoryType"] = "public.app-category.games"
            }
            if allowGameMode {
                extraInfo["GCSupportsGameMode"] = true
                extraInfo["LSSupportsGameMode"] = true
            }
            let packedIpaUrl = try LCUtils.archiveIPA(withBundleName: name, includingExtraInfoDict: extraInfo)
            
            shareURL = packedIpaUrl
            
            if(result == 2) {
                let launchURLStr = packedIpaUrl.absoluteString
                UserDefaults.standard.setValue(launchURLStr, forKey: "launchAppUrlScheme")
                LCUtils.openSideStore()
                return
            }
            
            showShareSheet = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
}
