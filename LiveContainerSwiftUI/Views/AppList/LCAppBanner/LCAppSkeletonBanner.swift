//
//  LCAppSkeletonBanner.swift
//  LiveContainerSwiftUI
//

import SwiftUI

/// Placeholder shown for hidden apps while they are locked. Mirrors LCAppBannerRootView's layout.
struct LCAppSkeletonBanner: View {
    private let fill = Color.primary.opacity(0.08)

    var body: some View {
        HStack(spacing: LCDesign.Spacing.iconToText) {
            RoundedRectangle(cornerRadius: LCDesign.Radius.icon, style: .continuous)
                .fill(fill)
                .frame(width: LCDesign.Size.icon, height: LCDesign.Size.icon)
                .overlay {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(fill).frame(width: 110, height: 14)
                Capsule().fill(fill).frame(width: 160, height: 10)
                RoundedRectangle(cornerRadius: LCDesign.Radius.chip, style: .continuous)
                    .fill(fill).frame(width: 80, height: 16)
            }

            Spacer(minLength: 0)

            Capsule()
                .fill(fill)
                .frame(width: LCDesign.Size.runButton.width, height: LCDesign.Size.runButton.height)
        }
        .padding(.horizontal, LCDesign.Spacing.cardInset)
        .frame(height: LCDesign.Size.bannerHeight)
        .lcCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("lc.appList.hiddenApps".loc)
    }
}
