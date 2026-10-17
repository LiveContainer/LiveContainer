//
//  LCTheme.swift
//  LiveContainerSwiftUI
//
//  LiveContainer Extended — Theme & Accent system (Cloudflare-inspired)
//

import SwiftUI
import UIKit

// MARK: - Accent Color

enum LCAccentPreset: String, CaseIterable, Identifiable {
    case orange = "Orange"
    case blue = "Blue"
    case indigo = "Indigo"
    case teal = "Teal"
    case green = "Green"
    case pink = "Pink"
    case purple = "Purple"
    case red = "Red"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .orange: return Color(red: 1.0, green: 0.42, blue: 0.21)      // Cloudflare-ish orange
        case .blue:   return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .indigo: return Color(red: 0.35, green: 0.40, blue: 0.95)
        case .teal:   return Color(red: 0.10, green: 0.72, blue: 0.68)
        case .green:  return Color(red: 0.18, green: 0.72, blue: 0.40)
        case .pink:   return Color(red: 0.92, green: 0.30, blue: 0.55)
        case .purple: return Color(red: 0.62, green: 0.35, blue: 0.95)
        case .red:    return Color(red: 0.92, green: 0.28, blue: 0.28)
        }
    }
    
    var uiColor: UIColor {
        UIColor(color)
    }
}

// MARK: - Theme Manager

final class LCTheme: ObservableObject {
    static let shared = LCTheme()
    
    @AppStorage("LCAccentPreset", store: LCUtils.appGroupUserDefault)
    var accentPresetRaw: String = LCAccentPreset.orange.rawValue
    
    @AppStorage("LCDoubleTapStatusBarToExit", store: LCUtils.appGroupUserDefault)
    var doubleTapStatusBarToExit: Bool = true
    
    var accentPreset: LCAccentPreset {
        get { LCAccentPreset(rawValue: accentPresetRaw) ?? .orange }
        set { accentPresetRaw = newValue.rawValue }
    }
    
    var accent: Color { accentPreset.color }
    var accentUIColor: UIColor { accentPreset.uiColor }
    
    // Cloudflare-inspired surface colors
    var cardBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1)   // near-black card
                : UIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)   // almost white
        })
    }
    
    var cardBorder: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.08)
                : UIColor(white: 0, alpha: 0.06)
        })
    }
    
    var secondaryText: Color {
        Color(UIColor.secondaryLabel)
    }
    
    var success: Color { Color(red: 0.18, green: 0.72, blue: 0.40) }
    var warning: Color { Color(red: 0.95, green: 0.65, blue: 0.15) }
    var danger:  Color { Color(red: 0.92, green: 0.28, blue: 0.28) }
}

// MARK: - View helpers

struct LCCardModifier: ViewModifier {
    @ObservedObject var theme = LCTheme.shared
    
    func body(content: Content) -> some View {
        content
            .background(theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func lcCard() -> some View {
        modifier(LCCardModifier())
    }
}
