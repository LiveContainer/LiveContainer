//
//  LaunchAppExtension.swift
//  LaunchAppExtension
//
//  Created by s s on 2026/1/23.
//

import AppIntents
import UIKit

extension String: @retroactive Error {}

struct LaunchAppExtension: AppIntent {
    static var title: LocalizedStringResource { "Launch App" }
    static var description: IntentDescription { "Please note that this shortcut does not launch the app directly due to iOS limitations. Instead, it setups the launch config and returns an URL. To actually launch the app, add a \"Open URLs\" action that opens the URL it returns." }
    @Parameter(title: "Launch URL")
    var launchURL: URL
    
    static var bookmarkResolved = false

    func forEachInstalledLC(isFree: Bool, block: (String, inout Bool) -> Void) {
        for scheme in LCSharedUtils.lcUrlSchemes() {
            // Check if the app is installed
            guard let url = URL(string: "\(scheme)://"),
                  lsApplicationWorkspaceCanOpenURL(url) else {
                continue
            }
            
            // Check shared utility logic
            if isFree && LCSharedUtils.isLCScheme(inUse: scheme) {
                continue
            }
            
            var shouldBreak = false
            block(scheme, &shouldBreak)
            
            if shouldBreak {
                break
            }
        }
    }
    
    func perform() async throws -> some ReturnsValue<URL> {
        // sanitize url
        if launchURL.scheme != "livecontainer" && launchURL.scheme != "sidestore" {
            throw "Not a livecontainer URL!"
        }
        
        guard
            let appGroupId = LCSharedUtils.appGroupID(),
            let lcSharedDefaults = UserDefaults(suiteName: appGroupId)
        else {
            throw "lcSharedDefaults failed to initialize, because no app group was found. Did you sign LiveContainer correctly?"
        }
        
        if launchURL.scheme == "sidestore" {
            lcSharedDefaults.set("builtinSideStore", forKey: "LCLaunchExtensionBundleID")
            lcSharedDefaults.set(Date.now, forKey: "LCLaunchExtensionLaunchDate")
            return.result(value: launchURL)
        }
        
        if launchURL.host != "livecontainer-launch" {
            throw "Not a livecontainer launch URL!"
        }

        var bundleId: String? = nil
        var containerName: String? = nil
        var forceJIT: Bool = false
        guard var components = URLComponents(url: launchURL, resolvingAgainstBaseURL: false) else {
            throw "URLComponents failed to initialize."
        }
        
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
        guard let bundleId else {
            throw "No bundle-name parameter found."
        }
                
        // resolve private Documents bookmark
        if !LaunchAppExtension.bookmarkResolved, let bookmarkData = lcSharedDefaults.data(forKey: "LCLaunchExtensionPrivateDocBookmark") {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
                let access = url.startAccessingSecurityScopedResource()
                if access {
                    setenv("LC_HOME_PATH", (url.deletingLastPathComponent().path as NSString).utf8String, 1)
                } else {
                    print("Failed to startAccessingSecurityScopedResource")
                    lcSharedDefaults.set(nil, forKey: "LCLaunchExtensionPrivateDocBookmark")
                }
            } catch {
                print("Failed to resolve bookmark")
                lcSharedDefaults.set(nil, forKey: "LCLaunchExtensionPrivateDocBookmark")
            }
            LaunchAppExtension.bookmarkResolved = true

        }
        
        // launch app
        var isSharedApp = false
        let appBundle = LCSharedUtils.findBundle(withBundleId: bundleId, isSharedAppOut: &isSharedApp)
        guard let appBundle else {
            // app bundle cannot be found, we pass the url as-is in case it can only be handled by lc1
            return .result(value: launchURL)
        }
        
        // check if the app is locked/hidden/require JIT, if so we don't directly set keys in lcSharedDefaults
        let appInfoURL = appBundle.url(forResource: "LCAppInfo", withExtension: "plist")
        guard let appInfoURL else {
            throw "Failed to find AppInfo!"
        }

        let appInfo = try PropertyListSerialization.propertyList(from: try Data(contentsOf: appInfoURL), format: nil)
        guard let appInfo = appInfo as? [String:Any] else {
            throw "Failed to load AppInfo!"
        }
        let isHiden = appInfo["isHidden"] as? Bool ?? false
        let isLocked = appInfo["isLocked"] as? Bool ?? false
        let isJITNeeded = appInfo["isJITNeeded"] as? Bool ?? false
        
        
        var schemeToLaunch: String? = nil
        // if containerName is not specified, use LCDataUUID as default
        if containerName == nil {
            containerName = appInfo["LCDataUUID"] as? String
        }
        
        var newLaunch = false
        // if the container is running in a lc, use its scheme, otherwise find free one
        if var runningScheme = LCSharedUtils.getContainerUsingLCScheme(withFolderName: containerName) {
            if(runningScheme.hasSuffix("liveprocess")) {
                runningScheme = (runningScheme as NSString).deletingPathExtension
            }
            schemeToLaunch = runningScheme
        } else {
            newLaunch = true
            if isSharedApp {
                forEachInstalledLC(isFree: true) { scheme, stop in
                    schemeToLaunch = scheme
                    stop = true
                }
            } else {
                if !LCSharedUtils.isLCScheme(inUse: "livecontainer") {
                    schemeToLaunch = "livecontainer"
                }
            }
        }

        guard let schemeToLaunch else {
            // no free lc, we just open the lc1 and let the user to decide what to do
            return .result(value: launchURL)
        }
        
        if newLaunch && !forceJIT && !isHiden && !isLocked && !isJITNeeded {
            lcSharedDefaults.set(bundleId, forKey: "LCLaunchExtensionBundleID")
            lcSharedDefaults.set(containerName, forKey: "LCLaunchExtensionContainerName")
            lcSharedDefaults.set(Date.now, forKey: "LCLaunchExtensionLaunchDate")
        }

        components.scheme = schemeToLaunch
        guard let newURL = components.url else {
            throw "unable to construct new url"
        }
        return .result(value: newURL)
    }
}
