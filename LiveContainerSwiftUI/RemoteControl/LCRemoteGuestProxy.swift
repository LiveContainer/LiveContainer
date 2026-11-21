//
//  LCRemoteGuestProxy.swift
//  LiveContainerSwiftUI
//  Summary (EN): Forwards /api/v1/guest/* to the in-guest sidecar on 127.0.0.1:8850 (shared bearer token via app group).
//
//  Proxies /api/v1/guest/* to the sidecar inside the guest process (127.0.0.1:8850).
//  Running inside the guest process lets it tap the app's own controls and capture its own screen.
//  The bearer token is shared through an app-group file (host writes it, sidecar reads it).
//

import Foundation

enum LCRemoteGuestProxy {

    static let port: UInt16 = 8850

    static var tokenFileURL: URL {
        LCPath.lcGroupDocPath
            .appendingPathComponent("RemoteControl")
            .appendingPathComponent("guest-sidecar-token")
    }

    /// Called when the host starts the server: writes the shared token file the sidecar authenticates against
    static func writeTokenIfNeeded() {
        let fm = FileManager.default
        let dir = tokenFileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let token = LCRemoteConfig.token
        if let existing = try? String(contentsOf: tokenFileURL, encoding: .utf8),
           existing.trimmingCharacters(in: .whitespacesAndNewlines) == token {
            return
        }
        try? token.write(to: tokenFileURL, atomically: true, encoding: .utf8)
        // Readable by this process and same-group extensions only
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFileURL.path)
    }

    /// path looks like /api/v1/guest/ui/tree -> forwarded to http://127.0.0.1:8850/guest/ui/tree
    static func forward(_ req: LCRemoteRequest, path: String) async -> LCRemoteResponse {
        writeTokenIfNeeded()
        var suffix = String(path.dropFirst("/api/v1".count))
        // req.path carries no query (the framework already split it into req.query),
        // so it has to be rebuilt here; otherwise /guest/inspect?index=1, /guest/ocr?text=x and
        // /guest/screenshot?maxWidth= would reach the sidecar with empty parameters.
        if !req.query.isEmpty {
            let qs = req.query
                .map { key, value in
                    let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                    return "\(key)=\(v)"
                }
                .joined(separator: "&")
            suffix += (suffix.contains("?") ? "&" : "?") + qs
        }
        guard let url = URL(string: "http://127.0.0.1:\(port)\(suffix)") else {
            return .error("bad guest path", status: 400, code: "bad_request")
        }
        var request = URLRequest(url: url)
        request.httpMethod = req.method
        request.timeoutInterval = 60
        request.setValue("Bearer \(LCRemoteConfig.token)", forHTTPHeaderField: "Authorization")
        if let contentType = req.header("content-type") {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if req.method != "GET" && req.method != "HEAD" {
            request.httpBody = req.bodyData()
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 502
            let ctype = http?.value(forHTTPHeaderField: "Content-Type") ?? "application/json"
            if ctype.contains("json") {
                if let obj = try? JSONSerialization.jsonObject(with: data) {
                    return .json(obj, status: status)
                }
                return LCRemoteResponse(status: status, headers: ["Content-Type": ctype], body: data)
            }
            return LCRemoteResponse(status: status, headers: ["Content-Type": ctype], body: data)
        } catch {
            return .error("guest sidecar unreachable (is the guest app running?): \(error.localizedDescription)",
                          status: 502, code: "guest_unreachable")
        }
    }
}
