//
//  LCRemoteConfig.swift
//  LiveContainerSwiftUI
//
//  Remote-control preferences: enabled flag / port / bearer token, stored in the app-group UserDefaults.
//

import Foundation
import Security

enum LCRemoteConfig {
    static let enabledKey = "LCRemoteEnabled"
    static let portKey = "LCRemotePort"
    static let tokenKey = "LCRemoteToken"
    static let defaultPort: UInt16 = 8848

    static var store: UserDefaults {
        LCUtils.appGroupUserDefault
    }

    static var isEnabled: Bool {
        get { store.bool(forKey: enabledKey) }
        set { store.set(newValue, forKey: enabledKey) }
    }

    static var port: UInt16 {
        get {
            let v = store.integer(forKey: portKey)
            guard v >= 1024, v <= 65535 else { return defaultPort }
            return UInt16(v)
        }
        set { store.set(Int(newValue), forKey: portKey) }
    }

    /// Generated on first access, then kept. Rotating it invalidates every connected client immediately.
    static var token: String {
        if let t = store.string(forKey: tokenKey), !t.isEmpty {
            return t
        }
        let t = randomToken()
        store.set(t, forKey: tokenKey)
        return t
    }

    static func regenerateToken() -> String {
        let t = randomToken()
        store.set(t, forKey: tokenKey)
        return t
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for i in 0..<bytes.count {
                bytes[i] = UInt8(truncatingIfNeeded: Int.random(in: 0...255))
            }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
