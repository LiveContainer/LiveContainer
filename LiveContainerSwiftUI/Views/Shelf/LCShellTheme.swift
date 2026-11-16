//  LCShellTheme.swift
//  Gives LiveContainer's own screens (tab bar, app list, Sources, Tweaks, Settings) the look of S2Arm's iOS shell, so
//  the shelf and the classic screens read as one app. Every value comes from ShellUI/ShellStyle.swift, which is
//  S2Arm's file copied unchanged: near-black page (ShellPalette.background), surface cards with a 1 pt hairline,
//  cream accent, muted grey for idle items, Manrope for all type, small cream capitals for section headings.
import SwiftUI
import UIKit

enum LCShellTheme {
    static let background = UIColor(ShellPalette.background)
    static let surface = UIColor(ShellPalette.surface)
    static let cream = UIColor(ShellPalette.cream)
    static let muted = UIColor(ShellPalette.muted)
    static let hairline = UIColor.white.withAlphaComponent(0.08)

    /// Manrope at a fixed size and weight for UIKit. Falls back to the system font if the face did not register.
    @MainActor static func font(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        _ = ShellFonts.fixed(size) // the first call registers the bundled Manrope.ttf
        guard let base = UIFont(name: "Manrope", size: size) else {
            return .systemFont(ofSize: size, weight: weight)
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// True when black type reads better than white on `color` (used for the cream Run pill).
    static func prefersDarkText(on color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.6
    }

    /// Navigation bar and tab bar look. Call once at launch, before any bar is created.
    @MainActor static func applyAppearance() {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: font(17, .bold), .foregroundColor: UIColor.white
        ]
        // ShellType.pageTitle: heavy 26, tracking -0.6.
        let largeTitleAttributes: [NSAttributedString.Key: Any] = [
            .font: font(30, .heavy), .foregroundColor: UIColor.white, .kern: -0.6
        ]

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.shadowColor = hairline
        standard.titleTextAttributes = titleAttributes
        standard.largeTitleTextAttributes = largeTitleAttributes

        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = titleAttributes
        edge.largeTitleTextAttributes = largeTitleAttributes

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = standard
        navBar.compactAppearance = standard
        navBar.scrollEdgeAppearance = edge
        navBar.tintColor = cream

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.shadowColor = hairline
        let idle: [NSAttributedString.Key: Any] = [.font: font(10, .semibold), .foregroundColor: muted]
        let selected: [NSAttributedString.Key: Any] = [.font: font(10, .bold), .foregroundColor: cream]
        for layout in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            layout.normal.iconColor = muted
            layout.normal.titleTextAttributes = idle
            layout.selected.iconColor = cream
            layout.selected.titleTextAttributes = selected
        }
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tab
        tabBar.scrollEdgeAppearance = tab
        tabBar.tintColor = cream
        tabBar.unselectedItemTintColor = muted
    }
}

extension View {
    /// S2Arm's look for everything below: dark, cream tint (toggles, links, buttons). Put it on the root.
    func lcShellTheme() -> some View {
        self.preferredColorScheme(.dark).tint(ShellPalette.cream)
    }

    /// A classic screen's page: S2Arm's near-black behind a List, Form or ScrollView. Row cards keep the system's
    /// dark grouped colour, which is within a few percent of ShellPalette.surface.
    func lcShellScreen() -> some View {
        self.scrollContentBackground(.hidden)
            .background(ShellPalette.background.ignoresSafeArea())
    }
}
