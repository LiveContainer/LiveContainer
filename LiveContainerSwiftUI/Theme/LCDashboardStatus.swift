//
//  LCDashboardStatus.swift
//  LiveContainerSwiftUI
//
//  LiveContainer Extended — Certificate + LocalDevVPN status
//

import Foundation
import NetworkExtension
import SwiftUI
import Combine
import Darwin

// MARK: - Certificate Status

struct LCCertificateStatus {
    enum State {
        case notImported
        case valid(daysLeft: Int, expiration: Date, teamId: String?)
        case expiringSoon(daysLeft: Int, expiration: Date, teamId: String?) // < 3 days
        case expired(expiration: Date, teamId: String?)
        case error(String)
    }
    
    let state: State
    
    var isImported: Bool {
        switch state {
        case .notImported: return false
        default: return true
        }
    }
    
    var title: String {
        switch state {
        case .notImported: return "No Certificate"
        case .valid: return "Certificate Valid"
        case .expiringSoon: return "Expiring Soon"
        case .expired: return "Certificate Expired"
        case .error: return "Certificate Error"
        }
    }
    
    var subtitle: String {
        switch state {
        case .notImported:
            return "Import a certificate to sign apps"
        case .valid(let days, let date, let team):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let teamStr = team.map { " · \($0)" } ?? ""
            return "\(days) day\(days == 1 ? "" : "s") left · \(formatter.string(from: date))\(teamStr)"
        case .expiringSoon(let days, let date, let team):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let teamStr = team.map { " · \($0)" } ?? ""
            return "\(days) day\(days == 1 ? "" : "s") left · \(formatter.string(from: date))\(teamStr)"
        case .expired(let date, let team):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let teamStr = team.map { " · \($0)" } ?? ""
            return "Expired \(formatter.string(from: date))\(teamStr)"
        case .error(let msg):
            return msg
        }
    }
    
    var indicatorColor: Color {
        let theme = LCTheme.shared
        switch state {
        case .notImported: return theme.secondaryText
        case .valid: return theme.success
        case .expiringSoon: return theme.warning
        case .expired, .error: return theme.danger
        }
    }
}

// MARK: - LocalDevVPN Status

struct LCLocalDevVPNStatus {
    enum State {
        case connected
        case disconnected
        case connecting
        case unknown
    }
    
    let state: State
    
    var isConnected: Bool { state == .connected }
    
    var title: String {
        switch state {
        case .connected: return "LocalDevVPN Connected"
        case .disconnected: return "LocalDevVPN Off"
        case .connecting: return "LocalDevVPN Connecting…"
        case .unknown: return "LocalDevVPN"
        }
    }
    
    var subtitle: String {
        switch state {
        case .connected: return "Ready to refresh apps"
        case .disconnected: return "Turn on to enable Refresh All"
        case .connecting: return "Establishing tunnel…"
        case .unknown: return "Unable to detect status"
        }
    }
    
    var indicatorColor: Color {
        let theme = LCTheme.shared
        switch state {
        case .connected: return theme.success
        case .disconnected: return theme.secondaryText
        case .connecting: return theme.warning
        case .unknown: return theme.secondaryText
        }
    }
}

// MARK: - Status Manager

@MainActor
final class LCDashboardStatusManager: ObservableObject {
    static let shared = LCDashboardStatusManager()
    
    @Published var certificate = LCCertificateStatus(state: .notImported)
    @Published var localDevVPN = LCLocalDevVPNStatus(state: .unknown)
    
    private var vpnObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    
    // Official LocalDevVPN identifiers
    private let localDevVPNBundleId = "com.jkcoxson.LocalDevVPN"
    private let localDevVPNTunnelId = "com.jkcoxson.LocalDevVPN.TunnelProv"
    
    init() {
        refresh()
        startObservation()
    }
    
    deinit {
        if let vpnObserver {
            NotificationCenter.default.removeObserver(vpnObserver)
        }
        refreshTask?.cancel()
    }
    
    func refresh() {
        refreshCertificate()
        refreshLocalDevVPN()
    }
    
    // MARK: Certificate
    
    private func refreshCertificate() {
        guard LCSharedUtils.certificatePassword() != nil,
              LCUtils.certificateData() != nil else {
            certificate = LCCertificateStatus(state: .notImported)
            return
        }
        
        _ = LCUtils.validateCertificate { [weak self] (status: Int32, expirationDate: Date?, organizationalUnitName: String?, error: String?) in
            Task { @MainActor in
                guard let self else { return }
                
                if let error, !error.isEmpty {
                    self.certificate = LCCertificateStatus(state: .error(error))
                    return
                }
                
                guard let expirationDate else {
                    if status == 0 {
                        self.certificate = LCCertificateStatus(state: .valid(daysLeft: 7, expiration: Date().addingTimeInterval(7*86400), teamId: organizationalUnitName))
                    } else {
                        self.certificate = LCCertificateStatus(state: .error("Unable to read certificate expiry"))
                    }
                    return
                }
                
                let days = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
                let team = organizationalUnitName
                
                if days < 0 {
                    self.certificate = LCCertificateStatus(state: .expired(expiration: expirationDate, teamId: team))
                } else if days < 3 {
                    self.certificate = LCCertificateStatus(state: .expiringSoon(daysLeft: max(days, 0), expiration: expirationDate, teamId: team))
                } else {
                    self.certificate = LCCertificateStatus(state: .valid(daysLeft: days, expiration: expirationDate, teamId: team))
                }
            }
        }
    }
    
    // MARK: LocalDevVPN detection
    
    private func startObservation() {
        vpnObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLocalDevVPN()
            }
        }
        
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    self?.refreshLocalDevVPN()
                }
            }
        }
    }
    
    private func refreshLocalDevVPN() {
        // Primary: detect LocalDevVPN tunnel by interface + 10.7.x.x address
        // (does not require Network Extension entitlement)
        if hasLocalDevVPNInterface() {
            localDevVPN = LCLocalDevVPNStatus(state: .connected)
            return
        }
        
        // Secondary: try NEVPNManager / NETunnelProviderManager (best-effort)
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            Task { @MainActor in
                guard let self else { return }
                
                if let managers {
                    for manager in managers {
                        if self.isLocalDevVPN(manager: manager) {
                            self.localDevVPN = LCLocalDevVPNStatus(state: self.mapStatus(manager.connection.status))
                            return
                        }
                    }
                }
                
                // Re-check interface (race)
                if self.hasLocalDevVPNInterface() {
                    self.localDevVPN = LCLocalDevVPNStatus(state: .connected)
                } else {
                    self.localDevVPN = LCLocalDevVPNStatus(state: .disconnected)
                }
            }
        }
    }
    
    /// Detect LocalDevVPN by looking for utun interfaces with 10.7.x.x addresses
    private func hasLocalDevVPNInterface() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return false }
        defer { freeifaddrs(ifaddr) }
        
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            
            let name = String(cString: current.pointee.ifa_name)
            // LocalDevVPN uses utun*
            guard name.hasPrefix("utun") else { continue }
            guard let addr = current.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            
            // LocalDevVPN default ranges: 10.7.0.x / 10.7.1.x
            if ip.hasPrefix("10.7.") {
                return true
            }
        }
        return false
    }
    
    private func isLocalDevVPN(manager: NEVPNManager) -> Bool {
        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
            let providerId = proto.providerBundleIdentifier ?? ""
            if providerId == localDevVPNTunnelId || providerId.hasPrefix(localDevVPNBundleId) {
                return true
            }
            if let server = proto.serverAddress,
               server.localizedCaseInsensitiveContains("LocalDevVPN") {
                return true
            }
        }
        if let desc = manager.localizedDescription,
           desc.localizedCaseInsensitiveContains("LocalDevVPN") ||
           desc.localizedCaseInsensitiveContains("Local Dev VPN") {
            return true
        }
        return false
    }
    
    private func mapStatus(_ status: NEVPNStatus) -> LCLocalDevVPNStatus.State {
        switch status {
        case .connected: return .connected
        case .connecting, .reasserting: return .connecting
        case .disconnecting, .disconnected, .invalid: return .disconnected
        @unknown default: return .unknown
        }
    }
    
    func openLocalDevVPN() {
        if let url = URL(string: "localdevvpn://") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
