import Combine
import SwiftUI
import UniformTypeIdentifiers

struct LCAppListView: View, LCAppBannerDelegate, LCAppModelDelegate {
    // MARK: - 狀態變數
    @State private var isEditMode = false
    @State private var selectedApps = Set<String>()
    @State private var showGroupPicker = false
    @State private var isGroupEditing = false
    @StateObject private var groupNameInput = InputHelper() 
    @State private var isSearchFieldVisible = false 
    @State private var isLiveContainerMode = true
    @State private var isiPhoneMode = false
    @Binding var appDataFolderNames: [String]
    @Binding var tweakFolderNames: [String]
    
    @State var didAppear = false
    @State var choosingIPA = false
    @State var errorShow = false
    @State var errorInfo = ""
    
    @State var installprogressVisible = false
    @State var installProgressPercentage: Float = 0.0
    @State var installObserver: NSKeyValueObservation?
    
    @State var installOptions: [AppReplaceOption] = []
    @StateObject var installReplaceAlert = AlertHelper<AppReplaceOption>()
    
    @State var webViewOpened = false
    @State var webViewURL: URL = URL(string: "about:blank")!
    @StateObject private var webViewUrlInput = InputHelper()
    
    @ObservedObject var downloadHelper = DownloadHelper()
    @StateObject private var installUrlInput = InputHelper()
    
    @State private var jitLog = ""
    @StateObject private var jitAlert = YesNoHelper()
    @StateObject private var runWhenMultitaskAlert = YesNoHelper()
    @StateObject private var generatedIconStyleSelector = AlertHelper<GeneratedIconStyle>()
    
    @State var safariViewOpened = false
    @State var safariViewURL = URL(string: "https://google.com")!
    
    @State private var helpPresent = false
    @State private var customSortViewPresent = false
    
    @EnvironmentObject private var sharedModel: SharedModel
    @EnvironmentObject private var sharedAppSortManager: LCAppSortManager
    
    @AppStorage("LCMultitaskMode", store: LCUtils.appGroupUserDefault) var multitaskMode: MultitaskMode = .virtualWindow
    @AppStorage("LCLaunchInMultitaskMode") var launchInMultitaskMode = false
    @AppStorage("LCNativeFullscreen") var isNativeMode = true 

    @State private var isViewAppeared = false
    @ObservedObject var searchContext = SearchContext()

    // MARK: - 初始化
    init(appDataFolderNames: Binding<[String]>, tweakFolderNames: Binding<[String]>) {
        self._appDataFolderNames = appDataFolderNames
        self._tweakFolderNames = tweakFolderNames
        
        let hasAnyMode = UserDefaults.standard.object(forKey: "LCNativeFullscreen") != nil ||
                         LCUtils.appGroupUserDefault.object(forKey: "LCRealIPhoneMode") != nil
        if !hasAnyMode {
            UserDefaults.standard.set(true, forKey: "LCNativeFullscreen")
        }
    }

    // MARK: - 主視圖
    var body: some View {
        NavigationView {
            List {
                searchSection        // 抽離至 Extension
                appGroupsList        // 抽離至 Extension
                hiddenAppsSection    // 抽離至 Extension
                footerSection        // 抽離至 Extension
            }
            .listStyle(.insetGrouped)
            .navigationBarProgressBar(show: $installprogressVisible, progress: $installProgressPercentage)
            .navigationTitle("lc.appList.myApps".loc)
            .toolbar {
                mainToolbarItems     // 抽離至 Extension
            }
        }
        .navigationViewStyle(.stack)
        // 呼叫封裝後的彈窗元件
        .allPopupModifiers(parent: self)
        .onAppear { onAppear() }
    }
}

extension LCAppListView {
    
    @ViewBuilder
    var searchSection: some View {
        if isSearchFieldVisible {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("lc.common.search".loc, text: $searchContext.query)
                        .textFieldStyle(.plain)
                    if !searchContext.query.isEmpty {
                        Button(action: { searchContext.query = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                        }
                    }
                }
            }
            .listRowBackground(Color(.secondarySystemBackground))
        }
    }

    @ViewBuilder
    var appGroupsList: some View {
        ForEach(groupedApps, id: \.key) { groupName, apps in
            Section(header: groupLabel(name: groupName, count: apps.count)) {
                ForEach(apps, id: \.self) { app in
                    let bid = app.appInfo.bundleIdentifier() ?? ""
                    HStack {
                        if isEditMode {
                            Image(systemName: selectedApps.contains(bid) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedApps.contains(bid) ? .accentColor : .gray)
                        }
                        LCAppBanner(appModel: app, delegate: self, appDataFolders: $appDataFolderNames, tweakFolders: $tweakFolderNames)
                            .disabled(isEditMode) 
                    }
                    .onTapGesture {
                        if isEditMode {
                            if selectedApps.contains(bid) { selectedApps.remove(bid) }
                            else { selectedApps.insert(bid) }
                        }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    var mainToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !installprogressVisible {
                Menu {
                    Button("lc.appList.installFromIpa".loc, systemImage: "doc.badge.plus") { choosingIPA = true }
                    Button("lc.appList.installFromUrl".loc, systemImage: "link.badge.plus") { Task { await startInstallFromUrl() } }
                } label: { Image(systemName: "plus") }
            } else {
                ProgressView().progressViewStyle(.circular)
            }
        }
        ToolbarItem(placement: .topBarLeading) { launchModeSelector }
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                Button { withAnimation { isSearchFieldVisible.toggle() } } label: { Image(systemName: "magnifyingglass") }
                Button { isGroupEditing = true } label: { Image(systemName: "folder.badge.gearshape") }
            }
        }
    }
}

extension View {
    func allPopupModifiers(parent: LCAppListView) -> some View {
        self.modifier(LCAppListViewPopupModifier(v: parent))
    }
}

struct LCAppListViewPopupModifier: ViewModifier {
    // 透過傳入主視圖物件來共享狀態
    @ObservedObject var v: LCAppListView
    
    func body(content: Content) -> some View {
        content
            // 1. 錯誤處理
            .alert("lc.common.error".loc, isPresented: $v.errorShow) {
                Button("lc.common.ok".loc) {}
                Button("lc.common.copy".loc) { v.copyError() }
            } message: { Text(v.errorInfo) }
            
            // 2. 檔案導入
            .betterFileImporter(isPresented: $v.choosingIPA, types: [.ipa, .tipa], multiple: false, callback: { urls in
                Task { await v.startInstallApp(urls[0]) }
            }, onDismiss: { v.choosingIPA = false })
            
            // 3. 群組命名 (修正 actionCancel 無參數閉包)
            .textFieldAlert(
                isPresented: $v.groupNameInput.show,
                title: "New Group",
                text: $v.groupNameInput.initVal,
                placeholder: "Name",
                action: { name in v.groupNameInput.close(result: name) },
                actionCancel: { v.groupNameInput.close(result: nil) }
            )
            
            // 4. 下載進度與 JIT
            .downloadAlert(helper: v.downloadHelper)
            .sheet(isPresented: $v.jitAlert.show) { v.JITEnablingModal }
            
            // 5. 瀏覽器與協助視窗
            .fullScreenCover(isPresented: $v.webViewOpened) {
                LCWebView(url: $v.webViewURL, isPresent: $v.webViewOpened, itmsServicesHandler: { urlStr in
                    await v.installFromPlist(urlStr: urlStr)
                })
            }
            .sheet(isPresented: $v.helpPresent) { LCHelpView(isPresent: $v.helpPresent) }
    }
}

extension LCAppListView {
    func onAppear() {
        for app in sharedModel.apps { app.delegate = self }
        for app in sharedModel.hiddenApps { app.delegate = self }
        
        isLiveContainerMode = UserDefaults.standard.bool(forKey: "LCNativeFullscreen")
        didAppear = true
    }

    func copyError() {
        UIPasteboard.general.string = errorInfo
    }
    func onOpenWebViewTapped() async {
        guard let urlToOpen = await webViewUrlInput.open(), urlToOpen != "" else {
            return
        }
        await openWebView(urlString: urlToOpen)
        
    }
    func onAppear() {
        for app in sharedModel.apps {
            app.delegate = self
        }
        for app in sharedModel.hiddenApps {
            app.delegate = self
        }
    let isNative = UserDefaults.standard.bool(forKey: "LCNativeFullscreen")
    let isRealIPhone = LCUtils.appGroupUserDefault.bool(forKey: "LCRealIPhoneMode")
    let isIPhone = UserDefaults.standard.bool(forKey: "LCIsIPhoneMode")

        
  

if isNative {
    isLiveContainerMode = true
    isiPhoneMode = false
} else if isRealIPhone { 
    isLiveContainerMode = false
    isiPhoneMode = false
}

        didAppear = true
    }
    
    
    func openWebView(urlString: String) async {
        guard var urlToOpen = URLComponents(string: urlString), urlToOpen.url != nil else {
            errorInfo = "lc.appList.urlInvalidError".loc
            errorShow = true
            return
        }
        if urlToOpen.scheme == nil || urlToOpen.scheme! == "" {
            urlToOpen.scheme = "https"
        }
        
        if urlToOpen.scheme?.lowercased() == "itms-services" {
            await installFromPlist(urlStr: urlString)
            return
        }
        
        if urlToOpen.scheme != "https" && urlToOpen.scheme != "http" {
            var appToLaunch : LCAppModel? = nil
            var appListsToConsider = [sharedModel.apps]
            if sharedModel.isHiddenAppUnlocked || !LCUtils.appGroupUserDefault.bool(forKey: "LCStrictHiding") {
                appListsToConsider.append(sharedModel.hiddenApps)
            }
        appLoop:
            for appList in appListsToConsider {
                for app in appList {
                    if let schemes = app.appInfo.urlSchemes() {
                        for scheme in schemes {
                            if let scheme = scheme as? String, scheme == urlToOpen.scheme {
                                appToLaunch = app
                                break appLoop
                            }
                        }
                    }
                }
            }
            
            
            guard let appToLaunch = appToLaunch else {
                errorInfo = "lc.appList.schemeCannotOpenError %@".localizeWithFormat(urlToOpen.scheme!)
                errorShow = true
                return
            }
            
            if appToLaunch.appInfo.isLocked && !sharedModel.isHiddenAppUnlocked {
                do {
                    if !(try await LCUtils.authenticateUser()) {
                        return
                    }
                } catch {
                    errorInfo = error.localizedDescription
                    errorShow = true
                    return
                }
            }
            
            UserDefaults.standard.setValue(urlToOpen.url!.absoluteString, forKey: "launchAppUrlScheme")
            do {
                try await appToLaunch.runApp(multitask: launchInMultitaskMode)
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
            
            return
        }
        webViewURL = urlToOpen.url!
        if webViewOpened {
            webViewOpened = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                webViewOpened = true
            })
        } else {
            webViewOpened = true
        }
    }
    
    
    
    func startInstallApp(_ fileUrl:URL) async {
        do {
            self.installprogressVisible = true
            try await installIpaFile(fileUrl)
            try FileManager.default.removeItem(at: fileUrl)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            self.installprogressVisible = false
        }
    }
    
    nonisolated func decompress(_ path: String, _ destination: String ,_ progress: Progress) async -> Int32 {
        extract(path, destination, progress)
    }
    
    func installIpaFile(_ url:URL) async throws {
        let fm = FileManager()
        
        let installProgress = Progress.discreteProgress(totalUnitCount: 100)
        self.installProgressPercentage = 0.0
        self.installObserver = installProgress.observe(\.fractionCompleted) { p, v in
            DispatchQueue.main.async {
                self.installProgressPercentage = Float(p.fractionCompleted)
            }
        }
        let decompressProgress = Progress.discreteProgress(totalUnitCount: 100)
        installProgress.addChild(decompressProgress, withPendingUnitCount: 80)
        let payloadPath = fm.temporaryDirectory.appendingPathComponent("Payload")
        if fm.fileExists(atPath: payloadPath.path) {
            try fm.removeItem(at: payloadPath)
        }
        
        // decompress
        guard await decompress(url.path, fm.temporaryDirectory.path, decompressProgress) == 0 else {
            throw "lc.appList.urlFileIsNotIpaError".loc
        }
        
        let payloadContents = try fm.contentsOfDirectory(atPath: payloadPath.path)
        var appBundleName : String? = nil
        for fileName in payloadContents {
            if fileName.hasSuffix(".app") {
                appBundleName = fileName
                break
            }
        }
        guard let appBundleName = appBundleName else {
            throw "lc.appList.bundleNotFondError".loc
        }
        
        let appFolderPath = payloadPath.appendingPathComponent(appBundleName)
        
        guard let newAppInfo = LCAppInfo(bundlePath: appFolderPath.path) else {
            throw "lc.appList.infoPlistCannotReadError".loc
        }
        
        var appRelativePath = "\(newAppInfo.bundleIdentifier()!.sanitizeNonACSII()).app"
        var outputFolder = LCPath.bundlePath.appendingPathComponent(appRelativePath)
        var appToReplace : LCAppModel? = nil
        // Folder exist! show alert for user to choose which bundle to replace
        var sameBundleIdApp = sharedModel.apps.filter { app in
            return app.appInfo.bundleIdentifier()! == newAppInfo.bundleIdentifier()
        }
        if sameBundleIdApp.count == 0 {
            sameBundleIdApp = sharedModel.hiddenApps.filter { app in
                return app.appInfo.bundleIdentifier()! == newAppInfo.bundleIdentifier()
            }
            
            // we found a hidden app, we need to authenticate before proceeding
            if sameBundleIdApp.count > 0 && !sharedModel.isHiddenAppUnlocked {
                do {
                    if !(try await LCUtils.authenticateUser()) {
                        self.installprogressVisible = false
                        return
                    }
                } catch {
                    errorInfo = error.localizedDescription
                    errorShow = true
                    self.installprogressVisible = false
                    return
                }
            }
            
        }
        
        if fm.fileExists(atPath: outputFolder.path) || sameBundleIdApp.count > 0 {
            appRelativePath = "\(newAppInfo.bundleIdentifier()!)_\(Int(CFAbsoluteTimeGetCurrent())).app"
            
            self.installOptions = [AppReplaceOption(isReplace: false, nameOfFolderToInstall: appRelativePath)]
            
            for app in sameBundleIdApp {
                self.installOptions.append(AppReplaceOption(isReplace: true, nameOfFolderToInstall: app.appInfo.relativeBundlePath, appToReplace: app))
            }
            
            guard let installOptionChosen = await installReplaceAlert.open() else {
                // user cancelled
                self.installprogressVisible = false
                try fm.removeItem(at: payloadPath)
                return
            }
            
            if let appToReplace = installOptionChosen.appToReplace, appToReplace.uiIsShared {
                outputFolder = LCPath.lcGroupBundlePath.appendingPathComponent(installOptionChosen.nameOfFolderToInstall)
            } else {
                outputFolder = LCPath.bundlePath.appendingPathComponent(installOptionChosen.nameOfFolderToInstall)
            }
            appRelativePath = installOptionChosen.nameOfFolderToInstall
            appToReplace = installOptionChosen.appToReplace
            if installOptionChosen.isReplace {
                try fm.removeItem(at: outputFolder)
            }
        }
        // Move it!
        try fm.moveItem(at: appFolderPath, to: outputFolder)
        let finalNewApp = LCAppInfo(bundlePath: outputFolder.path)
        finalNewApp?.relativeBundlePath = appRelativePath
        
        guard let finalNewApp else {
            errorInfo = "lc.appList.appInfoInitError".loc
            errorShow = true
            return
        }
        
        // patch and sign it
        var signError : String? = nil
        var signSuccess = false
        await withUnsafeContinuation({ c in
            if appToReplace?.uiDontSign ?? false || LCUtils.appGroupUserDefault.bool(forKey: "LCDontSignApp") {
                finalNewApp.dontSign = true
            }
            finalNewApp.patchExecAndSignIfNeed(completionHandler: { success, error in
                signError = error
                signSuccess = success
                c.resume()
            }, progressHandler: { signProgress in
                installProgress.addChild(signProgress!, withPendingUnitCount: 20)
            }, forceSign: false)
        })
        
        // we leave it unsigned even if signing failed
        if let signError {
            if signSuccess {
                errorInfo = "\("lc.appList.signSuccessWithError".loc)\n\n\(signError)"
            } else {
                errorInfo = signError.loc
            }
            errorShow = true
        }
        
        if let appToReplace {
            // copy previous configration to new app
            finalNewApp.autoSaveDisabled = true
            finalNewApp.isLocked = appToReplace.appInfo.isLocked
            finalNewApp.isHidden = appToReplace.appInfo.isHidden
            finalNewApp.isJITNeeded = appToReplace.appInfo.isJITNeeded
            finalNewApp.isShared = appToReplace.appInfo.isShared
            finalNewApp.spoofSDKVersion = appToReplace.appInfo.spoofSDKVersion
            finalNewApp.doSymlinkInbox = appToReplace.appInfo.doSymlinkInbox
            finalNewApp.containerInfo = appToReplace.appInfo.containerInfo
            finalNewApp.tweakFolder = appToReplace.appInfo.tweakFolder
            finalNewApp.selectedLanguage = appToReplace.appInfo.selectedLanguage
            finalNewApp.dataUUID = appToReplace.appInfo.dataUUID
            finalNewApp.orientationLock = appToReplace.appInfo.orientationLock
            finalNewApp.dontInjectTweakLoader = appToReplace.appInfo.dontInjectTweakLoader
            finalNewApp.hideLiveContainer = appToReplace.appInfo.hideLiveContainer
            finalNewApp.dontLoadTweakLoader = appToReplace.appInfo.dontLoadTweakLoader
            finalNewApp.doUseLCBundleId = appToReplace.appInfo.doUseLCBundleId
            finalNewApp.fixFilePickerNew = appToReplace.appInfo.fixFilePickerNew
            finalNewApp.fixLocalNotification = appToReplace.appInfo.fixLocalNotification
            finalNewApp.lastLaunched = appToReplace.appInfo.lastLaunched
            finalNewApp.jitLaunchScriptJs = appToReplace.appInfo.jitLaunchScriptJs
            finalNewApp.autoSaveDisabled = false
            finalNewApp.save()
        } else {
            // enable SDK version spoof by defalut
            finalNewApp.spoofSDKVersion = true
        }
        finalNewApp.installationDate = Date.now
        
        DispatchQueue.main.async {
            if let appToReplace {
                let newAppModel = LCAppModel(appInfo: finalNewApp, delegate: self)
                
                if appToReplace.uiIsHidden {
                    sharedModel.hiddenApps.removeAll { $0 == appToReplace }
                    sharedModel.hiddenApps.append(newAppModel)
                } else {
                    sharedModel.apps.removeAll { $0 == appToReplace }
                    sharedModel.apps.append(newAppModel)
                }
                
            } else {
                let newAppModel = LCAppModel(appInfo: finalNewApp, delegate: self)
                sharedModel.apps.append(newAppModel)
                
                // add url schemes
                if let urlSchemes = finalNewApp.urlSchemes(), urlSchemes.count > 0 {
                    UserDefaults.lcShared().mutableArrayValue(forKey: "LCGuestURLSchemes")
                        .addObjects(from: urlSchemes as! [Any])
                }
            }
            
            self.installprogressVisible = false
        }
    }
    
    func startInstallFromUrl() async {
        guard let installUrlStr = await installUrlInput.open(), installUrlStr.count > 0 else {
            return
        }
        if let url = URL(string:installUrlStr), url.scheme?.lowercased() == "itms-services" {
            await installFromPlist(urlStr: installUrlStr)
            return
        }
        await installFromUrl(urlStr: installUrlStr)
    }
    
    func installFromPlist(urlStr: String) async {
        if self.installprogressVisible {
            return
        }
        
        if sharedModel.multiLCStatus == 2 {
            errorInfo = "lc.appList.manageInPrimaryTip".loc
            errorShow = true
            return
        }
        
        var plistUrlStr = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if plistUrlStr.lowercased().hasPrefix("itms-services://") {
            if let urlComponents = URLComponents(string: plistUrlStr),
               let queryItems = urlComponents.queryItems,
               let urlParam = queryItems.first(where: { $0.name == "url" })?.value {
                plistUrlStr = urlParam
            } else {
                errorInfo = "lc.appList.plistInvalidError".loc
                errorShow = true
                return
            }
        }
        
        guard let plistUrl = URL(string: plistUrlStr) else {
            errorInfo = "lc.appList.urlInvalidError".loc
            errorShow = true
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: plistUrl)
            
            guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let items = plist["items"] as? [[String: Any]],
                  let firstItem = items.first,
                  let assets = firstItem["assets"] as? [[String: Any]] else {
                errorInfo = "lc.appList.plistParseError".loc
                errorShow = true
                return
            }
            
            var ipaUrlStr: String?
            for asset in assets {
                if let kind = asset["kind"] as? String, kind == "software-package",
                   let url = asset["url"] as? String {
                    ipaUrlStr = url
                    break
                }
            }
            
            guard let ipaUrlStr else {
                errorInfo = "lc.appList.plistNoIpaError".loc
                errorShow = true
                return
            }
            
            await installFromUrl(urlStr: ipaUrlStr)
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func installFromUrl(urlStr: String) async {
        // ignore any install request if we are installing another app
        if self.installprogressVisible {
            return
        }
        
        if sharedModel.multiLCStatus == 2 {
            errorInfo = "lc.appList.manageInPrimaryTip".loc
            errorShow = true
            return
        }
        
        guard let installUrl = URL(string: urlStr) else {
            errorInfo = "lc.appList.urlInvalidError".loc
            errorShow = true
            return
        }
        
        self.installprogressVisible = true
        defer {
            self.installprogressVisible = false
        }
        
        if installUrl.isFileURL {
            // install from local, we directly call local install method
            if !installUrl.lastPathComponent.hasSuffix(".ipa") && !installUrl.lastPathComponent.hasSuffix(".tipa") {
                errorInfo = "lc.appList.urlFileIsNotIpaError".loc
                errorShow = true
                return
            }
            
            let fm = FileManager.default
            if !fm.isReadableFile(atPath: installUrl.path) && !installUrl.startAccessingSecurityScopedResource() {
                errorInfo = "lc.appList.ipaAccessError".loc
                errorShow = true
                return
            }
            
            defer {
                installUrl.stopAccessingSecurityScopedResource()
            }
            
            do {
                try await installIpaFile(installUrl)
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
            
            do {
                // delete ipa if it's in inbox
                var shouldDelete = false
                if let documentsDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let inboxURL = documentsDirectory.appendingPathComponent("Inbox")
                    let fileURL = inboxURL.appendingPathComponent(installUrl.lastPathComponent)
                    
                    shouldDelete = fm.fileExists(atPath: fileURL.path)
                }
                if shouldDelete {
                    try fm.removeItem(at: installUrl)
                }
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
            return
        }
        
        do {
            let fileManager = FileManager.default
            let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(installUrl.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try await downloadHelper.download(url: installUrl, to: destinationURL)
            if downloadHelper.cancelled {
                return
            }
            try await installIpaFile(destinationURL)
            try fileManager.removeItem(at: destinationURL)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func removeApp(app: LCAppModel) {
        DispatchQueue.main.async {
            sharedModel.apps.removeAll { now in
                return app == now
            }
            sharedModel.hiddenApps.removeAll { now in
                return app == now
            }
            
        }
    }
    
    func changeAppVisibility(app: LCAppModel) {
        DispatchQueue.main.async {
            if app.appInfo.isHidden {
                sharedModel.apps.removeAll { now in
                    return app == now
                }
                if !sharedModel.hiddenApps.contains(app) {
                    sharedModel.hiddenApps.append(app)
                }
            } else {
                sharedModel.hiddenApps.removeAll { now in
                    return app == now
                }
                if !sharedModel.apps.contains(app) {
                    sharedModel.apps.append(app)
                }
            }
            
        }
    }
    
    func launchAppWithBundleId(bundleId : String, container : String?, forceJIT: Bool? = nil) async {
        if bundleId == "" {
            return
        }
        var appFound : LCAppModel? = nil
        var isFoundAppLocked = false
        for app in sharedModel.apps {
            if app.appInfo.relativeBundlePath == bundleId {
                appFound = app
                if app.appInfo.isLocked {
                    isFoundAppLocked = true
                }
                break
            }
        }
        if appFound == nil && !LCUtils.appGroupUserDefault.bool(forKey: "LCStrictHiding") {
            for app in sharedModel.hiddenApps {
                if app.appInfo.relativeBundlePath == bundleId {
                    appFound = app
                    isFoundAppLocked = true
                    break
                }
            }
        }
        
        if isFoundAppLocked && !sharedModel.isHiddenAppUnlocked {
            do {
                let result = try await LCUtils.authenticateUser()
                if !result {
                    return
                }
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
        }
        
        guard let appFound else {
            errorInfo = "lc.appList.appNotFoundError".loc
            errorShow = true
            return
        }
        
        let targetDataUUID = container ?? appFound.appInfo.dataUUID ?? ""

   
        
    if launchInMultitaskMode {
        do {
            try await appFound.runApp(multitask: true, containerFolderName: container, forceJIT: forceJIT)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    } else if UserDefaults.standard.bool(forKey: "LCNativeFullscreen") ||
          LCUtils.appGroupUserDefault.bool(forKey: "LCRealIPhoneMode") { 

        
        do {
            try await appFound.runApp(multitask: false, containerFolderName: container, forceJIT: forceJIT)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
}

    
    func authenticateUser() async {
        do {
            if !(try await LCUtils.authenticateUser()) {
                return
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }
    }
    
    func jitLaunch() async {
        await jitLaunch(withScript: "")
    }
    
    func jitLaunch(withScript script: String) async {
        await MainActor.run {
            jitLog = ""
        }
        let enableJITTask = Task {
            let _ = await LCUtils.askForJIT(withScript: script) { newMsg in
                Task { await MainActor.run {
                    self.jitLog += "\(newMsg)\n"
                }}
            }
            guard let _ = JITEnablerType(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCJITEnablerType")) else {
                return
            }
        }
        guard let result = await jitAlert.open(), result else {
            UserDefaults.standard.removeObject(forKey: "selected")
            enableJITTask.cancel()
            return
        }
        LCSharedUtils.launchToGuestApp()
        
    }
    
    func jitLaunch(withPID pid: Int, withScript script: String? = nil) async {
        await MainActor.run {
            let encoded = script?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                .map { "&script-data=\($0)" } ?? ""
            if let url = URL(string: "stikjit://enable-jit?bundle-id=\(Bundle.main.bundleIdentifier!)&pid=\(pid)\(encoded)") {
                if let jitEnabler = JITEnablerType(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCJITEnablerType")), jitEnabler == .StikJITLC {
                    if let app = sharedModel.apps.first(where: { app in
                        return app.appInfo.urlSchemes().contains("stikjit") &&
                        (sharedModel.multiLCStatus != 2 || app.appInfo.isShared)
                    }) {
                        Task { await openWebView(urlString: url.absoluteString) }
                    } else {
                        errorInfo = "StikDebug is not found. Please install it first and switch it to shared app."
                        errorShow = true
                        return
                    }
                } else {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
    
    func showRunWhenMultitaskAlert() async -> Bool? {
        return await runWhenMultitaskAlert.open()
    }
    
    func installMdm(data: Data) {
        safariViewURL = URL(string:"data:application/x-apple-aspen-config;base64,\(data.base64EncodedString())")!
        safariViewOpened = true
    }
    
    func openNavigationView(view: AnyView) {
        navigateTo = view
        isNavigationActive = true
    }
    
    func promptForGeneratedIconStyle() async -> GeneratedIconStyle? {
        if #available(iOS 18.0, *) {
            return await generatedIconStyleSelector.open()
        } else {
            return .Light
        }
        
    }
    
    func closeNavigationView() {
        isNavigationActive = false
        navigateTo = nil
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }
    
    func requestLaunchApp(bundleId: String, container: String?) {
        Task {
            await launchAppWithBundleId(bundleId: bundleId, container: container)
        }
    }
    
    func handleURL(url : URL) {
        if url.isFileURL {
            Task { await installFromUrl(urlStr: url.absoluteString) }
            return
        }
        
        if url.scheme == "sidestore" && UserDefaults.sideStoreExist() {
            UserDefaults.standard.setValue(url.absoluteString, forKey: "launchAppUrlScheme")
            LCUtils.openSideStore(delegate: self)
            return
        }
        
        if url.host == "open-web-page" || url.host == "open-url" {
            if let urlComponent = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItem = urlComponent.queryItems?.first {
                if queryItem.value?.isEmpty ?? true {
                    return
                }
                
                if let decodedData = Data(base64Encoded: queryItem.value ?? ""),
                   let decodedUrl = String(data: decodedData, encoding: .utf8) {
                    Task { await openWebView(urlString: decodedUrl) }
                }
            }
        } else if url.host == "livecontainer-launch" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var bundleId : String? = nil
                var containerName : String? = nil
                var forceJIT: Bool? = nil
                for queryItem in components.queryItems ?? [] {
                    if queryItem.name == "bundle-name", let bundleId1 = queryItem.value {
                        bundleId = bundleId1
                    } else if queryItem.name == "container-folder-name", let containerName1 = queryItem.value {
                        containerName = containerName1
                    } else if queryItem.name == "jit", let forceJIT1 = queryItem.value {
                        if forceJIT1 == "true" {
                            forceJIT = true
                        } else if forceJIT1 == "false" {
                            forceJIT = false
                        }
                    }
                }
                if let bundleId, bundleId != "ui"{
                    Task { await launchAppWithBundleId(bundleId: bundleId, container: containerName, forceJIT: forceJIT) }
                }
            }
        } else if url.host == "install" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var installUrl : String? = nil
                for queryItem in components.queryItems ?? [] {
                    if queryItem.name == "url", let installUrl1 = queryItem.value {
                        installUrl = installUrl1
                    }
                }
                if let installUrl {
                    Task { await installFromUrl(urlStr: installUrl) }
                }
            }
        }
    }
    // 將原本龐大的 installIpaFile, launchAppWithBundleId 等函數放在此處 ...
    // (由於程式碼過長，建議保持您原有的實作邏輯)
}

// 搜尋邏輯類別
class SearchContext: ObservableObject {
    @Published var query: String = ""
    @Published var debouncedQuery: String = ""
    @Published var isTyping: Bool = false
    private var cancellables = Set<AnyCancellable>()
    init() {
        $query.debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                self?.debouncedQuery = value
            }.store(in: &cancellables)
    }
}


