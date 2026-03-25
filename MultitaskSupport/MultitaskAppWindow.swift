//
//  MultitaskAppWindow.swift
//  LiveContainer
//
//  Created by s s on 2025/5/17.
//
import SwiftUI

@available(iOS 16.1, *)
struct MultitaskAppInfo {
    var displayName: String
    var dataUUID: String
    var bundleId: String
    
    init(displayName: String, dataUUID: String, bundleId: String) {
        self.displayName = displayName
        self.dataUUID = dataUUID
        self.bundleId = bundleId
    }
}

@available(iOS 16.1, *)
@objc class MultitaskWindowManager: NSObject {
    @Environment(\.openWindow) static var openWindow
    static var appDict: [String: MultitaskAppInfo] = [:]
    
    @objc class func openAppWindow(displayName: String, dataUUID: String, bundleId: String, pidCallback: ((NSNumber, Error?) -> Void)?) {
        DataManager.shared.model.enableMultipleWindow = true
        DataManager.shared.model.pidCallback = pidCallback
        appDict[dataUUID] = MultitaskAppInfo(displayName: displayName, dataUUID: dataUUID, bundleId: bundleId)
        openWindow(id: "appView", value: dataUUID)
    }
    
    @objc class func openExistingAppWindow(dataUUID: String) -> Bool {
        for a in appDict {
            if a.value.dataUUID == dataUUID {
                openWindow(id: "appView", value: a.key)
                return true
            }
        }
        return false
    }
}

@available(iOS 16.1, *)
struct AppSceneViewSwiftUI: UIViewControllerRepresentable {
    @Binding var show: Bool
    let bundleId: String
    let dataUUID: String
    let initSize: CGSize
    let onAppInitialize: (Int32, Error?) -> Void
    
    class Coordinator: NSObject, AppSceneViewControllerDelegate {
        let onExit: () -> Void
        let onAppInitialize: (Int32, Error?) -> Void
        init(onAppInitialize: @escaping (Int32, Error?) -> Void, onExit: @escaping () -> Void) {
            self.onAppInitialize = onAppInitialize
            self.onExit = onExit
        }
        
        func appSceneVCAppDidExit(_: AppSceneViewController!) {
            onExit()
        }
        
        func appSceneVC(_ vc: AppSceneViewController!, didInitializeWithError error: (any Error)!) {
            DispatchQueue.main.async {
                (vc.view.window?.windowScene?.statusBarManager as? LCStatusBarManager)?.nativeWindowViewController = vc
            }
            onAppInitialize(vc.pid, error)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onAppInitialize: onAppInitialize, onExit: {
            show = false
        })
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        return AppSceneViewController(bundleId: bundleId, dataUUID: dataUUID, delegate: context.coordinator)
    }
    
    func updateUIViewController(_ vc: UIViewController, context _: Context) {
        if let vc = vc as? AppSceneViewController {
            if !show {
                vc.terminate()
            }
        }
    }
}

@available(iOS 16.1, *)
struct MultitaskAppWindow: View {
    @State var show = true
    @State var pid = 0
    @State var appInfo: MultitaskAppInfo? = nil
    @State var errorMessage: String? = nil
    @State private var hasScheduledAutoClose = false
    @State private var didRequestManualClose = false
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @Environment(\.openWindow) var openWindow
    @AppStorage("LCMultitaskMode", store: LCUtils.appGroupUserDefault) var multitaskMode: MultitaskMode = .virtualWindow
    @AppStorage("LCSkipTerminatedScreen", store: LCUtils.appGroupUserDefault) var skipTerminatedScreen = false
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)
    init(id: String) {
        guard let appInfo = MultitaskWindowManager.appDict[id] else {
            return
        }
        _appInfo = State(initialValue: appInfo)
    }
    
    var body: some View {
        let isVirtualWindowMode = multitaskMode == .virtualWindow
        if show, let appInfo {
            GeometryReader { geometry in
                AppSceneViewSwiftUI(show: $show, bundleId: appInfo.bundleId, dataUUID: appInfo.dataUUID, initSize: geometry.size,
                                    onAppInitialize: { pid, error in
                    DispatchQueue.main.async {
                        if error == nil {
                            self.pid = Int(pid)
                        } else {
                            self.errorMessage = error?.localizedDescription
                        }
                        DataManager.shared.model.pidCallback?(NSNumber(value: pid), error)
                        DataManager.shared.model.pidCallback = nil
                    }
                })
                .background(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.all, edges: .all)
            .navigationTitle(Text("\(appInfo.displayName) - \(String(pid))"))
            .onReceive(pub) { out in
                if let scene1 = sceneDelegate.window?.windowScene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                    show = false
                }
            }
            
        } else if skipTerminatedScreen && isVirtualWindowMode, appInfo != nil {
            Color.clear
                .ignoresSafeArea(.all, edges: .all)
                .onAppear {
                    guard !didRequestManualClose else { return }
                    if let appInfo {
                        MultitaskRelaunchManager.scheduleRelaunchIfNeeded(bundleId: appInfo.bundleId, dataUUID: appInfo.dataUUID, isManualTermination: false)
                    }
                    if !hasScheduledAutoClose {
                        hasScheduledAutoClose = true
                        DispatchQueue.main.async {
                            requestSceneDestruction(isManual: false)
                        }
                    }
                }
        } else {
            VStack {
                Text("lc.multitaskAppWindow.appTerminated".loc)
                    .font(.largeTitle)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.body, design: .monospaced))
                    Button("lc.common.copy".loc) {
                        UIPasteboard.general.string = errorMessage
                        requestSceneDestruction(isManual: true)
                    }
                    .buttonStyle(.bordered)
                }
                Button("lc.common.close".loc) {
                    requestSceneDestruction(isManual: true)
                }
                .buttonStyle(.bordered)
            }.onAppear {
                // appInfo == nil indicates this is the first scene opened in this launch. We don't want this so we open lc's main scene and close this view
                // however lc's main view may already be starting in another scene so we wait a bit before opening the main view
                // also we have to keep the view open for a little bit otherwise lc will be killed by iOS
                if appInfo == nil {
                    if DataManager.shared.model.mainWindowOpened {
                        requestSceneDestruction()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if !DataManager.shared.model.mainWindowOpened {
                                openWindow(id: "Main")
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                requestSceneDestruction()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func requestSceneDestruction(isManual: Bool = false) {
        if isManual {
            didRequestManualClose = true
        }
        guard let session = sceneDelegate.window?.windowScene?.session else { return }
        UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { error in
            print(error)
        }
    }
}

@objcMembers
class MultitaskRelaunchManager: NSObject {
    private static var pendingKeys: Set<String> = []
    private static let pendingLock = NSLock()
    
    static func scheduleRelaunchIfNeeded(bundleId: String, dataUUID: String, isManualTermination: Bool) {
        let defaults = LCUtils.appGroupUserDefault
        let multitaskMode = MultitaskMode(rawValue: defaults.integer(forKey: "LCMultitaskMode")) ?? .virtualWindow
        guard defaults.bool(forKey: "LCSkipTerminatedScreen"),
              defaults.bool(forKey: "LCRestartTerminatedApp"),
              multitaskMode == .virtualWindow,
              !isManualTermination else { return }
        
        let key = "\(bundleId)#\(dataUUID)"
        guard markPendingIfNeeded(key: key) else { return }
        
        Task {
            defer { clearPending(key: key) }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await relaunchApp(bundleId: bundleId, dataUUID: dataUUID)
        }
    }
    
    private static func markPendingIfNeeded(key: String) -> Bool {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        if pendingKeys.contains(key) {
            return false
        }
        pendingKeys.insert(key)
        return true
    }
    
    private static func clearPending(key: String) {
        pendingLock.lock()
        pendingKeys.remove(key)
        pendingLock.unlock()
    }
    
    private static func relaunchApp(bundleId: String, dataUUID: String) async {
        guard let appModel = await MainActor.run(body: { lookupAppModel(bundleId: bundleId) }),
              appModel.appInfo.lastLaunched.distance(to: .now) > 2
        else {
            return
        }
        
        do {
            try await appModel.runApp(multitask: true, containerFolderName: dataUUID)
        } catch {
            print("Failed to restart \(bundleId): \(error)")
        }
    }
    
    @MainActor private static func lookupAppModel(bundleId: String) -> LCAppModel? {
        let sharedModel = DataManager.shared.model
        if let app = sharedModel.apps.first(where: { $0.appInfo.relativeBundlePath == bundleId }) {
            return app
        }
        return sharedModel.hiddenApps.first(where: { $0.appInfo.relativeBundlePath == bundleId })
    }
}
