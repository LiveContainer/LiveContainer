import UIKit
import SwiftUI
import Intents

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
        
        // Capture incoming custom scheme URL and set up instant-boot
        if let url = launchOptions?[.url] as? URL, let scheme = url.scheme?.lowercased() {
            if !["livecontainer", "livecontainer2", "livecontainer3", "sidestore", "file", "http", "https"].contains(scheme) {
                // Find which app handles this custom scheme
                if let docPath = ProcessInfo.processInfo.environment["HOME"] {
                    let appsPath = "\(docPath)/Documents/Applications"
                    let fm = FileManager.default
                    
                    if let apps = try? fm.contentsOfDirectory(atPath: appsPath) {
                        for appFolder in apps {
                            let infoPath = "\(appsPath)/\(appFolder)/LCAppInfo.plist"
                            if let appInfoDict = NSDictionary(contentsOfFile: infoPath),
                               let customSchemes = appInfoDict["LCCustomUrlSchemes"] as? [String] {
                                
                                if customSchemes.contains(scheme) {
                                    // Write launch target
                                    UserDefaults.standard.set(appFolder, forKey: "selected")
                                    
                                    if let containers = appInfoDict["LCContainers"] as? [[String:Any]],
                                       let defaultUUID = appInfoDict["LCDataUUID"] as? String,
                                       containers.contains(where: { ($0["folderName"] as? String) == defaultUUID }) {
                                        UserDefaults.standard.set(defaultUUID, forKey: "selectedContainer")
                                    }
                                    
                                    // Save full URL so LCBootstrap can pass it via base64 later
                                    UserDefaults.standard.set(url.absoluteString, forKey: "launchAppUrlScheme")
                                    
                                    // Instantly boot the guest app!
                                    LCSharedUtils.launchToGuestApp()
                                    break
                                }
                            }
                        }
                    }
                }
            }
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
