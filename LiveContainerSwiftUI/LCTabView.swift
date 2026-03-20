//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import SwiftUI
import Foundation


struct LiquidGlass<Content: View>: View {
    var appearance: LiquidGlassAppearance
    var cornerRadius: CGFloat
    var padding: EdgeInsets
    @ViewBuilder var content: Content
    
    init(
        appearance: LiquidGlassAppearance = .clear,
        cornerRadius: CGFloat = 999,
        padding: EdgeInsets = .init(top: 5, leading: 5, bottom: 5, trailing: 5),
        @ViewBuilder content: () -> Content
    ) {
        self.appearance = appearance
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background {
                LiquidGlassBackground(appearance: appearance, cornerRadius: cornerRadius)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    
    
}
enum LiquidGlassAppearance {
    case clear   
    case tinted  
}
struct LiquidGlassBackground: View {
    var appearance: LiquidGlassAppearance
    var cornerRadius: CGFloat
    
    
    private var fillColor: Color {
        switch appearance {
        case .clear:  return .white.opacity(0.01)
        case .tinted: return Color(red: 0.12, green: 0.12, blue: 0.25).opacity(0.05)
        }
    }
    private var saturation: Double { appearance == .clear ? 1.8 : 1.4 }
    private var brightness: Double { appearance == .clear ? 0.0 : -0.08 }
    private var strokeOpacity: Double { appearance == .clear ? 0.28 : 0.18 }
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            
            //shape.fill(.ultraThinMaterial)
                
                //.saturation(saturation)
                //.brightness(brightness)
            
            
            shape.fill(fillColor)
            .saturation(saturation)
            .brightness(brightness)
            
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.1), .white.opacity(0)],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.45)
                )
            )
            
            
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.2), .clear, .white.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.3), .clear, .white.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(strokeOpacity), .white.opacity(strokeOpacity * 0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)
    }
    
    
}
enum LCTabID: Hashable {
    case sources
    case apps
    case tweaks
    case settings
    case cache
    case search
    case explore
}

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
    
    @State var errorShow = false
    @State var errorInfo = ""
    @State var shouldToggleMainWindowOpen = false 
    @EnvironmentObject var sceneDelegate: SceneDelegate

       var body: some View {
        
        ZStack(alignment: .bottom) {
            
            
            Group {
                switch selectedTab {
                case .sources:
                    LCSourcesView()
                case .apps:
                    LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
                case .tweaks:
                    LCTweaksView(tweakFolders: $tweakFolderNames)
                case .explore, .search:
                    ExploreView()
                case .settings:
                    LCSettingsView(appDataFolderNames: $appDataFolderNames)
                case .cache:
                    LCCacheManagementView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            .id(selectedTab)
            
        
            customBottomBar
            .background(.clear)
        }
        .ignoresSafeArea(.keyboard) 
        .background(Color(UIColor.systemBackground))
        .task {
            await performInitialChecks()
        }
    }

    private var customBottomBar: some View {
        VStack(spacing: 0) {
            
            HStack(spacing: 0) {
                LiquidGlass{
                HStack{
                tabButton(tab: .sources)
                tabButton(tab: .apps)
                tabButton(tab: .tweaks)
                }.frame(maxWidth:160)
                }
                Spacer()
                LiquidGlass{
                HStack{
                tabButton(tab: .explore)
                tabButton(tab: .settings)
                tabButton(tab: .cache)
                }.frame(maxWidth:160)
                }
            }
            .padding(10)
              .background(.clear)
        }
        .background(.clear)
        
        .zIndex(999) 
    }

    

    
        private func tabButton(tab: LCTabID) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            print("Button tapped: \(tab)") 
            self.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: selectedTab == tab ? .semibold : .regular))
                    .frame(height: 20)
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            
            .contentShape(Rectangle()) 
            .foregroundColor(selectedTab == tab ? .accentColor : .primary.opacity(0.45))
        }
        .buttonStyle(.plain) 
    }
}






extension LCTabView {
    
    
    
    private func triggerError(message: String) {
        self.errorInfo = message
        self.errorShow = true
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
