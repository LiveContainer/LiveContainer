//
//  LaunchAppExtension.swift
//  LaunchAppExtension
//
//  Created by s s on 2026/1/23.
//

import AppIntents
import UIKit

private struct LaunchAppExtensionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct LaunchAppExtension: AppIntent {
    static var title: LocalizedStringResource { "Launch App" }
    static var description: IntentDescription { "This action directly launches an app in normal mode in LiveContainer. To get the launch URL, open LiveContainer, hold the app, tap \"Add to Home Screen\" -> \"Copy Launch URL\"" }
    @Parameter(title: "Launch URL")
    var launchURL: URL
    
    static var bookmarkResolved = false
    static var ext: NSExtension? = nil

    func forEachInstalledLC(isFree: Bool, block: (String, inout Bool) -> Void) {
        for scheme in [launchURL.scheme].compactMap({ $0 }) + LCSharedUtils.lcUrlSchemes() {
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
    
    func openURL(url: URL) async throws {
        var ext : NSExtension? = LaunchAppExtension.ext
        if ext == nil {
            do {
                ext = try NSExtension(identifier: ((Bundle.main.bundleIdentifier! as NSString).deletingPathExtension as NSString).appendingPathExtension("LaunchAppExtensionHelper") )
                LaunchAppExtension.ext = ext
            } catch {
                NSLog("Failed to start extension \(error)")
                throw LaunchAppExtensionError("Failed to start extension \(error). To use the Launch App shortcut, reinstall LiveContainer with LaunchAppExtension and LaunchAppExtensionHelper installed. If you use SideStore, choose \"Keep App Extensions (Use Main Profile)\". If you use Impactor, choose \"Only Register Main Bundle\". For other sideloaders, select keep all extensions, i.e. DO NOT Remove any extension.")
            }
            
        }
        let extensionItem = NSExtensionItem()
        extensionItem.userInfo = [
            "url": url,
        ]
        await ext?.beginRequest(withInputItems: [extensionItem])
    }
    
    func perform() async throws -> some IntentResult {
        // sanitize url
        guard let s = launchURL.scheme, (LCSharedUtils.lcUrlSchemes() + ["sidestore"]).contains(s) else {    
            throw LaunchAppExtensionError("Not a livecontainer URL!")
        }
        
        guard
            let appGroupId = LCSharedUtils.appGroupID(),
            let lcSharedDefaults = UserDefaults(suiteName: appGroupId)
        else {
            throw LaunchAppExtensionError("lcSharedDefaults failed to initialize, because no app group was found. Did you sign LiveContainer correctly?")
        }
        
        if launchURL.scheme == "sidestore" {
            lcSharedDefaults.set("builtinSideStore", forKey: "LCLaunchExtensionBundleID")
            lcSharedDefaults.set(Date.now, forKey: "LCLaunchExtensionLaunchDate")
            try await openURL(url: launchURL)
            return .result()
        }
        
        if launchURL.host != "livecontainer-launch" {
            throw LaunchAppExtensionError("Not a livecontainer launch URL!")
        }

        var bundleId: String? = nil
        var containerName: String? = nil
        var forceJIT: Bool = false
        guard var components = URLComponents(url: launchURL, resolvingAgainstBaseURL: false) else {
            throw LaunchAppExtensionError("URLComponents failed to initialize.")
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
            throw LaunchAppExtensionError("No bundle-name parameter found.")
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
            try await openURL(url: launchURL)
            return .result()
        }
        
        // check if the app is locked/hidden/require JIT, if so we don't directly set keys in lcSharedDefaults
        let appInfoURL = appBundle.url(forResource: "LCAppInfo", withExtension: "plist")
        guard let appInfoURL else {
            throw LaunchAppExtensionError("Failed to find AppInfo!")
        }

        let appInfo = try PropertyListSerialization.propertyList(from: try Data(contentsOf: appInfoURL), format: nil)
        guard let appInfo = appInfo as? [String:Any] else {
            throw LaunchAppExtensionError("Failed to load AppInfo!")
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
            try await openURL(url: launchURL)
            return .result()
        }
        
        if newLaunch && !forceJIT && !isHiden && !isLocked && !isJITNeeded {
            lcSharedDefaults.set(bundleId, forKey: "LCLaunchExtensionBundleID")
            lcSharedDefaults.set(containerName, forKey: "LCLaunchExtensionContainerName")
            lcSharedDefaults.set(Date.now, forKey: "LCLaunchExtensionLaunchDate")
        }

        components.scheme = schemeToLaunch
        guard let newURL = components.url else {
            throw LaunchAppExtensionError("unable to construct new url")
        }

        try await openURL(url: newURL)
        return .result()
    }
}
