//
//  LCAppShortcuts.swift
//  LiveContainer
//
//  Vends one parameterised App Shortcut covering every indexed guest app.
//  This is what makes guest apps show up in Spotlight and Siri with no
//  per-app setup: no shortcut to build, no launch URL to paste, no icon to
//  save, no configuration profile to install.
//
//  Every phrase has to contain the app name token, hence `\(.applicationName)`
//  in all of them.
//

import AppIntents

@available(iOS 17.0, *)
struct LCAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LCOpenGuestAppIntent(),
            phrases: [
                "Open \(\.$app) in \(.applicationName)",
                "Launch \(\.$app) in \(.applicationName)",
                "Run \(\.$app) in \(.applicationName)",
                "Start \(\.$app) in \(.applicationName)",
                "\(.applicationName) \(\.$app)"
            ],
            shortTitle: "Open App",
            systemImageName: "square.stack.3d.up.fill"
        )
    }
}
