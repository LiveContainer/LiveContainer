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

    func forEachInstalledLC(schemes: [String] = LCSharedUtils.lcUrlSchemes(), isFree: Bool, block: (String, inout Bool) -> Void) {
        for scheme in schemes {
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

    func firstFreeInstalledLC(preferredScheme: String?) -> String? {
        var schemeToLaunch: String? = nil
        
        var schemes = LCSharedUtils.lcUrlSchemes()!
        if let preferredScheme {
            schemes.removeAll { $0 == preferredScheme }
            schemes.insert(preferredScheme, at: 0)
        }
        
        forEachInstalledLC(schemes: schemes, isFree: true) { scheme, stop in
            schemeToLaunch = scheme
            stop = true
        }
        return schemeToLaunch
    }

    func openURL(launchOptions: [String: Any]) async throws {
        var ext : NSExtension? = LaunchAppExtension.ext
        if ext == nil {
            do {
                ext = try NSExtension(identifier: ((Bundle.main.bundleIdentifier! as NSString).deletingPathExtension as NSString).appendingPathExtension("ShareExtension") )
                LaunchAppExtension.ext = ext
            } catch {
                NSLog("Failed to start extension \(error)")
                throw LaunchAppExtensionError("Failed to start extension \(error). To use the Launch App shortcut, reinstall LiveContainer with LaunchAppExtension and ShareExtension installed. If you use SideStore, choose \"Keep App Extensions (Use Main Profile)\". If you use Impactor, choose \"Only Register Main Bundle\". For other sideloaders, select keep all extensions, i.e. DO NOT Remove any extension.")
            }
            
        }
        let extensionItem = NSExtensionItem()
        extensionItem.userInfo = launchOptions
        await ext?.beginRequest(withInputItems: [extensionItem])
    }
    
    func perform() async throws -> some IntentResult {
        // sanitize url
        let normalizedLaunchScheme = launchURL.scheme?.lowercased()
        var isLiveContainerURL = normalizedLaunchScheme == "livecontainer"
        let preferredScheme = isLiveContainerURL ? nil : (normalizedLaunchScheme == "livecontainer1" ? "livecontainer" : normalizedLaunchScheme)
        
        if let preferredScheme, let schemes = LCSharedUtils.lcUnorderedUrlSchemes() {
            isLiveContainerURL = schemes.contains(preferredScheme)
        }
        
        if !isLiveContainerURL && normalizedLaunchScheme != "sidestore" {
            throw LaunchAppExtensionError("Not a livecontainer URL!")
        }
        
        guard
            let appGroupId = LCSharedUtils.appGroupID(),
            let lcSharedDefaults = UserDefaults(suiteName: appGroupId)
        else {
            throw LaunchAppExtensionError("lcSharedDefaults failed to initialize, because no app group was found. Did you sign LiveContainer correctly?")
        }
        
        if normalizedLaunchScheme == "sidestore" {
            lcSharedDefaults.set("livecontainer", forKey: "LCLaunchExtensionScheme")
            lcSharedDefaults.set("builtinSideStore", forKey: "LCLaunchExtensionBundleID")
            lcSharedDefaults.set(Date.now, forKey: "LCLaunchExtensionLaunchDate")
            try await openURL(launchOptions: ["url": launchURL])
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
            try await openURL(launchOptions: ["url": launchURL])
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
        var allowClassicMode = false
        // if the container is running in a lc, use its scheme, otherwise find free one
        if var runningScheme = LCSharedUtils.getContainerUsingLCScheme(withFolderName: containerName) {
            if(runningScheme.hasSuffix("liveprocess")) {
                runningScheme = (runningScheme as NSString).deletingPathExtension
            }
            schemeToLaunch = runningScheme
            allowClassicMode = true
        } else {
            newLaunch = true
            if isSharedApp {
                schemeToLaunch = firstFreeInstalledLC(preferredScheme: preferredScheme)
                allowClassicMode = schemeToLaunch != nil
            } else {
                schemeToLaunch = "livecontainer"
                allowClassicMode = !LCSharedUtils.isLCScheme(inUse: "livecontainer")
            }
        }

        guard let schemeToLaunch else {
            // no free lc, we just open the lc1 and let the user to decide what to do
            try await openURL(launchOptions: ["url": launchURL])
            return .result()
        }
        
        if newLaunch && !forceJIT && !isHiden && !isLocked && !isJITNeeded {
            lcSharedDefaults.set(schemeToLaunch, forKey: "LCLaunchExtensionScheme")
            lcSharedDefaults.set(bundleId, forKey: "LCLaunchExtensionBundleID")
            lcSharedDefaults.set(containerName, forKey: "LCLaunchExtensionContainerName")
            lcSharedDefaults.set(Date.now, forKey: "LCLaunchExtensionLaunchDate")
        }

        components.scheme = schemeToLaunch
        guard let newURL = components.url else {
            throw LaunchAppExtensionError("unable to construct new url")
        }

        var launchOptions: [String: Any] = ["url": newURL]
        if allowClassicMode {
            let cachedClassicMode = (appInfo["classicMode"] as? Bool ?? false)
                ? ((appInfo["LCClassicModeCache"] as? [String: Any])?["defaultClassicMode"] as? NSNumber)?.uintValue ?? 0
                : 0
            launchOptions["classicMode"] = cachedClassicMode
        }
        try await openURL(launchOptions: launchOptions)
        return .result()
    }
}
