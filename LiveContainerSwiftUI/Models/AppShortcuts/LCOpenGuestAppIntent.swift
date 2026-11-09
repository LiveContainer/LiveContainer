//
//  LCOpenGuestAppIntent.swift
//  LiveContainerSwiftUI
//
//  The entity-backed sibling of `LaunchAppExtension`. Same idea, but the app is
//  picked from the catalog instead of being pasted in as a URL, which is what
//  lets the system vend one App Shortcut covering every guest app.
//
//  This deliberately lives in LiveContainerSwiftUI rather than in
//  LaunchAppExtension. iOS instantiates an App Shortcut's intent in the *app*
//  process, not in the extension, so a type compiled only into the extension
//  fails with "the type with this mangled name does not exist in the process's
//  memory space". SideStore's intents work in the combined build for exactly
//  this reason: they resolve into SideStoreSupport.framework, which is loaded
//  into the app. This framework is too.
//
//  Because we are already inside LiveContainer when this runs, there is no need
//  for LaunchAppExtension's cross-process trick. We use LiveContainer's own
//  launch path: write the LCLaunchExtension* keys into the shared app group and
//  open the target container's URL scheme. LCBootstrap.m picks those up on
//  launch (within a 3 second window) and loads the guest app directly.
//

import AppIntents
import Foundation
import UIKit

@available(iOS 17.0, *)
struct LCOpenGuestAppIntent: AppIntent {
    static var title: LocalizedStringResource { "Open App in LiveContainer" }
    static var description: IntentDescription {
        IntentDescription("Opens an app installed in LiveContainer. Apps appear here automatically, so there is no launch URL to copy.")
    }

    // Must be true. An intent running in the background cannot call
    // UIApplication.open(), so the tap silently does nothing. OpenURLIntent
    // would avoid needing the foreground but is iOS 18+.
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "App")
    var app: LCGuestApp

    init() {}

    func perform() async throws -> some IntentResult {
        let defaults = LCUtils.appGroupUserDefault

        // Prefer a container already running this app's data folder, otherwise
        // take the first free LiveContainer, otherwise fall back to the primary
        // one and let it sort the conflict out.
        var schemeToLaunch = "livecontainer"
        if var running = LCSharedUtils.getContainerUsingLCScheme(withFolderName: app.containerFolderName) {
            if running.hasSuffix("liveprocess") {
                running = (running as NSString).deletingPathExtension
            }
            schemeToLaunch = running
        } else {
            LCUtils.forEachInstalledLC(isFree: true) { free, shouldBreak in
                schemeToLaunch = free
                shouldBreak = true
            }
        }

        defaults.set(schemeToLaunch, forKey: "LCLaunchExtensionScheme")
        defaults.set(app.bundleFolderName, forKey: "LCLaunchExtensionBundleID")
        if let container = app.containerFolderName {
            defaults.set(container, forKey: "LCLaunchExtensionContainerName")
        } else {
            defaults.removeObject(forKey: "LCLaunchExtensionContainerName")
        }
        // LCBootstrap rejects anything older than 3 seconds, so this has to be
        // the last thing set before the open.
        defaults.set(Date.now, forKey: "LCLaunchExtensionLaunchDate")

        var components = app.launchURLComponents
        components.scheme = schemeToLaunch
        guard let url = components.url else {
            throw "Could not build a launch URL for \(app.displayName)."
        }

        // We are foregrounded by now, so this is allowed. The URL goes through
        // LCTabView.dispatchURL, the same path a web clip or the old Launch App
        // shortcut uses, which is well tested.
        await UIApplication.shared.open(url)
        return .result()
    }
}
