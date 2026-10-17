//
//  LCDashboardHeaderView.swift
//  LiveContainerSwiftUI
//
//  LiveContainer Extended — Dashboard header (status cards + quick actions)
//  Cloudflare-inspired clean dashboard style
//

import SwiftUI

struct LCDashboardHeaderView: View {
    @ObservedObject private var statusManager = LCDashboardStatusManager.shared
    @ObservedObject private var theme = LCTheme.shared
    @EnvironmentObject var sharedModel: SharedModel
    
    // Callbacks into existing LCAppListView logic
    var onRefreshAll: () -> Void
    var onOpenSideStore: () -> Void
    var onImportIPA: () -> Void
    var onOpenSettings: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title row
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LiveContainer")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Extended")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.accent)
                }
                Spacer()
                Button {
                    statusManager.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(theme.cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(theme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            
            // Status cards
            HStack(spacing: 10) {
                statusCard(
                    icon: "checkmark.seal.fill",
                    title: statusManager.certificate.title,
                    subtitle: statusManager.certificate.subtitle,
                    color: statusManager.certificate.indicatorColor,
                    action: onOpenSettings
                )
                
                statusCard(
                    icon: statusManager.localDevVPN.isConnected ? "network" : "network.slash",
                    title: statusManager.localDevVPN.title,
                    subtitle: statusManager.localDevVPN.subtitle,
                    color: statusManager.localDevVPN.indicatorColor,
                    action: {
                        if !statusManager.localDevVPN.isConnected {
                            statusManager.openLocalDevVPN()
                        }
                    }
                )
            }
            
            // Quick actions
            HStack(spacing: 10) {
                quickActionButton(
                    title: "Refresh All",
                    icon: "arrow.triangle.2.circlepath",
                    enabled: statusManager.localDevVPN.isConnected,
                    primary: true,
                    action: onRefreshAll
                )
                
                quickActionButton(
                    title: "SideStore",
                    icon: "shippingbox",
                    enabled: true,
                    primary: false,
                    action: onOpenSideStore
                )
                
                quickActionButton(
                    title: "Import",
                    icon: "plus.rectangle.on.folder",
                    enabled: true,
                    primary: false,
                    action: onImportIPA
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .onAppear {
            statusManager.refresh()
        }
    }
    
    // MARK: - Status Card
    
    @ViewBuilder
    private func statusCard(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                    Spacer(minLength: 0)
                }
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .lcCard()
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Quick Action Button
    
    @ViewBuilder
    private func quickActionButton(title: String, icon: String, enabled: Bool, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            guard enabled else { return }
            action()
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(buttonForeground(enabled: enabled, primary: primary))
            .background(buttonBackground(enabled: enabled, primary: primary))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(enabled && !primary ? theme.cardBorder : Color.clear, lineWidth: 1)
            )
            .opacity(enabled ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
    
    private func buttonForeground(enabled: Bool, primary: Bool) -> Color {
        if !enabled { return theme.secondaryText }
        if primary { return .white }
        return .primary
    }
    
    private func buttonBackground(enabled: Bool, primary: Bool) -> Color {
        if !enabled {
            return theme.cardBackground
        }
        if primary {
            return theme.accent
        }
        return theme.cardBackground
    }
}
