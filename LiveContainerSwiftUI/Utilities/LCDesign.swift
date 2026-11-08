//
//  LCDesign.swift
//  LiveContainerSwiftUI
//
//  Shared design tokens so the UIKit app banner and the SwiftUI screens stay in sync.
//

import SwiftUI
import UIKit

enum LCDesign {
    enum Radius {
        static let card: CGFloat = 20
        static let icon: CGFloat = 13.5      // ~ iOS squircle ratio for a 58pt icon
        static let chip: CGFloat = 7
    }

    enum Size {
        static let bannerHeight: CGFloat = 88
        static let icon: CGFloat = 58
        static let runButton = CGSize(width: 78, height: 34)
        static let badge: CGFloat = 18
    }

    enum Spacing {
        static let cardInset: CGFloat = 14
        static let iconToText: CGFloat = 12
        static let list: CGFloat = 10
    }

    /// Strength of the icon-colour wash on a card, left edge → right edge.
    static func washAlphas(isDark: Bool) -> (start: CGFloat, end: CGFloat) {
        isDark ? (0.34, 0.08) : (0.26, 0.05)
    }

    static var fallbackAccent: UIColor {
        UIColor(named: "FontColor") ?? .systemBlue
    }
}

/// Compact section label used between groups of cards (e.g. "Hidden Apps").
struct LCSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.6)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Card surface used by SwiftUI screens to match the UIKit app banner.
    func lcCard(tint: Color? = nil) -> some View {
        background {
            RoundedRectangle(cornerRadius: LCDesign.Radius.card, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: LCDesign.Radius.card, style: .continuous)
                            .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.06)],
                                                 startPoint: .leading, endPoint: .trailing))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LCDesign.Radius.card, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                }
        }
    }
}
