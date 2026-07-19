import UIKit
import SwiftUI
import Intents
import AppIntents
import CoreFoundation

private let lcActionButtonSwitchNotification = "com.kdt.livecontainer.actionButtonSwitch" as CFString

@available(iOS 16.0, *)
struct LCActionButtonSwitchIntent: AppIntent {
    static var title: LocalizedStringResource = "lc.launchMode.switchToLiveProcess"
    static var description = IntentDescription("Ask the active LiveContainer guest app to switch to LiveProcess. Run this shortcut three times to show the confirmation menu.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(lcActionButtonSwitchNotification),
            nil,
            nil,
            true
        )
        return .result()
    }
}

@available(iOS 16.0, *)
struct LCAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LCActionButtonSwitchIntent(),
            phrases: ["Switch \(.applicationName) to LiveProcess"],
            shortTitle: "lc.launchMode.switchToLiveProcess",
            systemImageName: "arrow.left.arrow.right"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .blue
}

enum LCLaunchModeSwitchDefaults {
    static let pendingBundleID = "LCPendingLiveProcessBundleID"
    static let pendingDataUUID = "LCPendingLiveProcessDataUUID"
}

@MainActor
enum LCLaunchModeSwitchManager {
    private static var isLaunching = false

    static func launchPendingLiveProcessAppIfNeeded() {
        guard !isLaunching else { return }

        let defaults = UserDefaults.standard
        guard let bundleID = defaults.string(forKey: LCLaunchModeSwitchDefaults.pendingBundleID),
              let dataUUID = defaults.string(forKey: LCLaunchModeSwitchDefaults.pendingDataUUID)
        else {
            return
        }

        let model = DataManager.shared.model
        guard let app = (model.apps + model.hiddenApps).first(where: {
            $0.appInfo.relativeBundlePath == bundleID
        }) else {
            defaults.removeObject(forKey: LCLaunchModeSwitchDefaults.pendingBundleID)
            defaults.removeObject(forKey: LCLaunchModeSwitchDefaults.pendingDataUUID)
            defaults.set("Unable to find the app requested for LiveProcess: \(bundleID)", forKey: "error")
            return
        }

        isLaunching = true
        defaults.removeObject(forKey: LCLaunchModeSwitchDefaults.pendingBundleID)
        defaults.removeObject(forKey: LCLaunchModeSwitchDefaults.pendingDataUUID)
        NSLog("[LC][LaunchModeSwitch] relaunching \(bundleID) with container \(dataUUID) in LiveProcess")

        Task {
            defer { isLaunching = false }
            do {
                try await app.runApp(multitask: true, containerFolderName: dataUUID)
            } catch {
                NSLog("[LC][LaunchModeSwitch] LiveProcess relaunch failed: \(error.localizedDescription)")
                defaults.set(error.localizedDescription, forKey: "error")
            }
        }
    }
}

@objc class AppDelegate: UIResponder, UIApplicationDelegate {
        
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? ) -> Bool {
        application.shortcutItems = nil
        UserDefaults.standard.removeObject(forKey: "LCNeedToAcquireJIT")
        
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            // Fix launching app if user opens JIT waiting dialog and kills the app. Won't trigger normally.
            if DataManager.shared.model.isJITModalOpen && !UserDefaults.standard.bool(forKey: "LCKeepSelectedWhenQuit"){
                UserDefaults.standard.removeObject(forKey: "selected")
                UserDefaults.standard.removeObject(forKey: "selectedContainer")
            }
        }
        
        // allow new scene pop up as a new fullscreen window
        method_exchangeImplementations(
            class_getInstanceMethod(UIApplication.self, #selector(UIApplication.requestSceneSessionActivation(_ :userActivity:options:errorHandler:)))!,
            class_getInstanceMethod(UIApplication.self, #selector(UIApplication.hook_requestSceneSessionActivation(_:userActivity:options:errorHandler:)))!)

        // remove symbol caches if user upgraded iOS
        if let lastIOSBuildVersion = LCUtils.appGroupUserDefault.string(forKey: "LCLastIOSBuildVersion"),
           let currentVersion = UIDevice.current.buildVersion,
           lastIOSBuildVersion == currentVersion {
            
        } else {
            LCUtils.appGroupUserDefault.removeObject(forKey: "symbolOffsetCache")
            LCUtils.appGroupUserDefault.setValue(UIDevice.current.buildVersion, forKey: "LCLastIOSBuildVersion")
        }
        
        return true
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
    
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        switch intent {
        case is ViewAppIntent: return ViewAppIntentHandler()
        default:
            return nil
        }
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject { // Make SceneDelegate conform ObservableObject
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        self.window = (scene as? UIWindowScene)?.keyWindow
    }
    
}


@objc extension UIApplication {
    
    func hook_requestSceneSessionActivation(
        _ sceneSession: UISceneSession?,
        userActivity: NSUserActivity?,
        options: UIScene.ActivationRequestOptions?,
        errorHandler: ((any Error) -> Void)? = nil
    ) {
        var newOptions = options
        if newOptions == nil {
            newOptions = UIScene.ActivationRequestOptions()
        }
        newOptions!._setRequestFullscreen(UIScreen.main.bounds == self.keyWindow!.bounds)
        self.hook_requestSceneSessionActivation(sceneSession, userActivity: userActivity, options: newOptions, errorHandler: errorHandler)
    }
    
}

public class ViewAppIntentHandler: NSObject, ViewAppIntentHandling
{
    public func provideAppOptionsCollection(for intent: ViewAppIntent, with completion: @escaping (INObjectCollection<App>?, Error?) -> Void)
    {
        completion(INObjectCollection(items:[]), nil)
    }
}
