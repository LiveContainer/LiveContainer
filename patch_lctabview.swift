import Foundation
import SwiftUI

struct LCTabView: View {
@Binding var appDataFolderNames: [String]
@Binding var tweakFolderNames: [String]

@State var errorShow = false
@State var crashReportShow = false
@State var errorInfo = ""

@State var previousSelectedTab : LCTabIdentifier = .apps

@EnvironmentObject var sharedModel : SharedModel
@EnvironmentObject var sceneDelegate: SceneDelegate
@State var shouldToggleMainWindowOpen = false
@Environment(\.scenePhase) var scenePhase
@StateObject var downloadHelper = DownloadHelper()
let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)

private var appListView: LCAppListView {
LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
}

private var sourcesView: LCSourcesView {
LCSourcesView()
}

var body: some View {
Group {
if #available(iOS 19.0, *), SharedModel.isLiquidGlassSearchEnabled {
TabView(selection: $sharedModel.selectedTab) {
if DataManager.shared.model.multiLCStatus \!= 2 {
Tab("lc.tabView.sources".loc, systemImage: "books.vertical", value: LCTabIdentifier.sources) {
sourcesView
}
}
Tab("lc.tabView.apps".loc, systemImage: "square.stack.3d.up.fill", value: LCTabIdentifier.apps) {
appListView
}
if DataManager.shared.model.multiLCStatus \!= 2 {
Tab("lc.tabView.tweaks".loc, systemImage: "wrench.and.screwdriver", value: LCTabIdentifier.tweaks) {
LCTweaksView(tweakFolders: $tweakFolderNames)
}
}
Tab("lc.tabView.settings".loc, systemImage: "gearshape.fill", value: LCTabIdentifier.settings) {
LCSettingsView(appDataFolderNames: $appDataFolderNames)
}
Tab("Search".loc, systemImage: "magnifyingglass", value: LCTabIdentifier.search, role: .search) {
if previousSelectedTab == .sources {
sourcesView
.searchable(text: sourcesView.$searchContext.query)
} else {
appListView
.searchable(text: appListView.$searchContext.query)
}
}
}
} else {
TabView(selection: $sharedModel.selectedTab) {
if DataManager.shared.model.multiLCStatus \!= 2 {
sourcesView
.tabItem {
Label("lc.tabView.sources".loc, systemImage: "books.vertical")
}
.tag(LCTabIdentifier.sources)
}
appListView
.tabItem {
Label("lc.tabView.apps".loc, systemImage: "square.stack.3d.up.fill")
}
.tag(LCTabIdentifier.apps)
if DataManager.shared.model.multiLCStatus \!= 2 {
LCTweaksView(tweakFolders: $tweakFolderNames)
.tabItem{
Label("lc.tabView.tweaks".loc, systemImage: "wrench.and.screwdriver")
}
.tag(LCTabIdentifier.tweaks)
}

LCSettingsView(appDataFolderNames: $appDataFolderNames)
.tabItem {
Label("lc.tabView.settings".loc, systemImage: "gearshape.fill")
}
.tag(LCTabIdentifier.settings)
}
}
}
.downloadAlert(helper: downloadHelper)
.environmentObject(downloadHelper)
.alert("lc.common.error".loc, isPresented: $errorShow){
Button("lc.common.ok".loc, action: {
})
Button("lc.common.copy".loc, action: {
copyError()
})
} message: {
Text(errorInfo)
}
.sheet(isPresented: $crashReportShow) {
NavigationView {
ScrollView {
Text(errorInfo)
.font(.system(size: 12).monospaced())
.fixedSize(horizontal: false, vertical: false)
.textSelection(.enabled)
}
.frame(maxWidth: .infinity)
.padding(.horizontal)
.toolbar {
ToolbarItem(placement: .topBarLeading) {
Button("lc.common.copy".loc, action: {
copyError()
})
}
ToolbarItem(placement: .topBarTrailing) {
Button("lc.common.ok".loc, action: {
crashReportShow = false
})
}
}
.navigationTitle("lc.common.error".loc)
.navigationBarTitleDisplayMode(.inline)
}
}
.task {
closeDuplicatedWindow()
checkLastLaunchError()
checkTeamId()
checkBundleId()
checkGetTaskAllow()
checkPrivateContainerBookmark()
}
.onReceive(pub) { out in
if let scene1 = sceneDelegate.window?.windowScene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
if shouldToggleMainWindowOpen {
DataManager.shared.model.mainWindowOpened = false
}
}
}
.onChange(of: sharedModel.selectedTab) { newValue in
if newValue \!= LCTabIdentifier.search {
previousSelectedTab = newValue
}
}
.onOpenURL { url in
dispatchURL(url: url)
}
}
}
