import Foundation
import Network
import os
import Security
import Darwin
import UIKit

enum RemoteAPISettings {
    static let enabledKey = "LCRemoteAPIEnabled"
    static let portKey = "LCRemoteAPIPort"
    static let maximumUploadMegabytesKey = "LCRemoteAPIMaximumUploadMegabytes"
    static let defaultPort = 8080
    static let defaultMaximumUploadMegabytes = 512
    static let lastJobKey = "LCRemoteAPILastJob"

    static var maximumUploadBytes: Int {
        let configured = (UserDefaults.lc() ?? .standard).integer(forKey: maximumUploadMegabytesKey)
        return max(configured == 0 ? defaultMaximumUploadMegabytes : configured, 1) * 1_048_576
    }
}

enum RemoteAPITokenStore {
    private static let service = "com.livecontainer.remote-api"
    private static let account = "bearer-token"
    private static var currentToken: String?

    static func token() -> String? {
        if let currentToken {
            return currentToken
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        currentToken = String(data: data, encoding: .utf8)
        return currentToken
    }

    @discardableResult
    static func regenerate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        let token = Data(bytes).base64EncodedString()
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
        currentToken = token
        return token
    }

    static func tokenCreatingIfNeeded() -> String {
        token() ?? regenerate()
    }
}

private struct RemoteAPIConflict: Codable {
    let bundleID: String
    let apps: [String]
}

private struct RemoteAPIJob: Codable {
    var status: String
    var progress: Int
    var error: String?
    var conflict: RemoteAPIConflict?
}

private actor RemoteAPIJobStore {
    static let shared = RemoteAPIJobStore()
    private var jobs: [String: RemoteAPIJob] = [:]
    private var conflictResolutions: [String: CheckedContinuation<String, Never>] = [:]

    func create() -> String {
        let id = UUID().uuidString.lowercased()
        jobs[id] = RemoteAPIJob(status: "queued", progress: 0, error: nil, conflict: nil)
        return id
    }

    func restore(_ id: String, status: String = "queued", progress: Int = 0) {
        jobs[id] = RemoteAPIJob(status: status, progress: progress, error: nil, conflict: nil)
    }

    func update(_ id: String, status: String, progress: Int, error: String? = nil) {
        jobs[id] = RemoteAPIJob(status: status, progress: progress, error: error, conflict: nil)
    }

    func job(_ id: String) -> RemoteAPIJob? {
        jobs[id]
    }

    func waitForConflictResolution(_ id: String, bundleID: String, apps: [String]) async -> String {
        jobs[id] = RemoteAPIJob(status: "conflict", progress: 80, error: nil, conflict: RemoteAPIConflict(bundleID: bundleID, apps: apps))
        return await withCheckedContinuation { continuation in
            conflictResolutions[id] = continuation
        }
    }

    func resolveConflict(_ id: String, action: String) -> Bool {
        guard let continuation = conflictResolutions.removeValue(forKey: id), var job = jobs[id] else {
            return false
        }
        job.status = "installing"
        job.conflict = nil
        jobs[id] = job
        continuation.resume(returning: action)
        return true
    }
}

private struct RemoteAPIRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

private struct RemoteAPIResponse {
    let status: Int
    let body: Data
    let contentType: String

    static func json(_ status: Int, _ object: Any) -> RemoteAPIResponse {
        RemoteAPIResponse(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), contentType: "application/json; charset=utf-8")
    }

    static func html(_ html: String) -> RemoteAPIResponse {
        RemoteAPIResponse(status: 200, body: Data(html.utf8), contentType: "text/html; charset=utf-8")
    }

    static func png(_ data: Data) -> RemoteAPIResponse {
        RemoteAPIResponse(status: 200, body: data, contentType: "image/png")
    }
}

final class RemoteAPIServer {
    static let shared = RemoteAPIServer()

    private let queue = DispatchQueue(label: "com.livecontainer.remote-api", qos: .userInitiated, attributes: .concurrent)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiveContainer", category: "RemoteAPI")
    private var listener: NWListener?
    private let lock = NSLock()

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listener != nil
    }

    static var localAddress: String {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return "localhost"
        }
        defer { freeifaddrs(interfaces) }
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let interfaceAddress = interface.pointee.ifa_addr else { continue }
            let address = interfaceAddress.pointee
            let flags = Int32(interface.pointee.ifa_flags)
            guard address.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0 else {
                continue
            }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var mutableAddress = address
            if getnameinfo(&mutableAddress, socklen_t(address.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: hostname)
            }
        }
        return "localhost"
    }

    func start(port: Int) throws {
        guard (1...65535).contains(port) else {
            throw "Port must be between 1 and 65535."
        }
        stop()
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: UInt16(port))!)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .global(qos: .userInitiated))
            self?.receive(connection, buffer: Data(), expectedLength: nil)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case let .failed(error) = state {
                self?.logger.error("server failed: \(error.localizedDescription, privacy: .public)")
                self?.stop()
            }
        }
        lock.lock()
        self.listener = listener
        lock.unlock()
        listener.start(queue: queue)
        logger.info("server started on port \(port)")
    }

    func stop() {
        lock.lock()
        let activeListener = listener
        listener = nil
        lock.unlock()
        activeListener?.cancel()
        if activeListener != nil {
            logger.info("server stopped")
        }
    }

    func resumePendingUpdateIfNeeded() {
        let defaults = UserDefaults.lc() ?? .standard
        guard let pending = defaults.dictionary(forKey: AppManagementService.pendingRemoteUpdateKey),
              let id = pending["job"] as? String,
              let bundleID = pending["bundleID"] as? String,
              let container = pending["container"] as? String,
              let ipaPath = pending["ipaPath"] as? String,
              FileManager.default.fileExists(atPath: ipaPath) else {
            return
        }
        Task {
            await RemoteAPIJobStore.shared.restore(id)
            await runInstallJob(id, uploadURL: URL(fileURLWithPath: ipaPath), replacingBundleIdentifier: bundleID, relaunchContainer: container)
        }
    }

    func restoreLastJobIfNeeded() {
        guard let job = (UserDefaults.lc() ?? .standard).dictionary(forKey: RemoteAPISettings.lastJobKey),
              let id = job["job"] as? String,
              let status = job["status"] as? String,
              let progress = job["progress"] as? Int else {
            return
        }
        Task { await RemoteAPIJobStore.shared.restore(id, status: status, progress: progress) }
    }

    private func receive(_ connection: NWConnection, buffer: Data, expectedLength: Int?) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if expectedLength == nil, buffer.count > 64 * 1024 {
                self.send(.json(400, ["error": "Request headers are too large."]), on: connection)
                return
            }

            var expectedLength = expectedLength
            if expectedLength == nil, let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                guard headerEnd.lowerBound <= 64 * 1024,
                      let headerText = String(data: Data(buffer[..<headerEnd.lowerBound]), encoding: .utf8) else {
                    self.send(.json(400, ["error": "Invalid request headers."]), on: connection)
                    return
                }
                let contentLength = self.headerValue("content-length", in: headerText).flatMap(Int.init) ?? 0
                guard contentLength >= 0, contentLength <= RemoteAPISettings.maximumUploadBytes else {
                    self.send(.json(400, ["error": "Upload exceeds the configured size limit."]), on: connection)
                    return
                }
                expectedLength = headerEnd.upperBound + contentLength
            }

            if let expectedLength, buffer.count >= expectedLength {
                guard let request = self.parseRequest(Data(buffer.prefix(expectedLength))) else {
                    self.send(.json(400, ["error": "Invalid HTTP request."]), on: connection)
                    return
                }
                Task {
                    let response = await self.route(request)
                    self.send(response, on: connection)
                }
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer, expectedLength: expectedLength)
            }
        }
    }

    private func parseRequest(_ data: Data) -> RemoteAPIRequest? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: Data(data[..<separator.lowerBound]), encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1)
            if pieces.count == 2 {
                headers[String(pieces[0]).lowercased()] = pieces[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return RemoteAPIRequest(method: String(requestLine[0]), path: String(requestLine[1]).removingPercentEncoding ?? String(requestLine[1]), headers: headers, body: Data(data[separator.upperBound...]))
    }

    private func headerValue(_ name: String, in headers: String) -> String? {
        headers.components(separatedBy: "\r\n").dropFirst().first { $0.lowercased().hasPrefix("\(name):") }?.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private func route(_ request: RemoteAPIRequest) async -> RemoteAPIResponse {
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        if request.method == "GET", path == "/" {
            return .html(RemoteAPIWebInterface.html)
        }

        guard let expectedToken = RemoteAPITokenStore.token(),
              request.headers["authorization"] == "Bearer \(expectedToken)" else {
            logger.warning("authentication failure")
            return .json(401, ["error": "Unauthorized"])
        }

        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 2, components[0] == "api", components[1] == "v1" else {
            return .json(404, ["error": "Not found."])
        }

        if request.method == "GET", components.count == 3, components[2] == "status" {
            return .json(200, [
                "server": "LiveContainer",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "apiVersion": 1,
                "authenticated": true
            ])
        }

        if request.method == "GET", components.count == 3, components[2] == "apps" {
            let apps = await MainActor.run { AppManagementService.shared.installedApps.map(Self.metadata) }
            return .json(200, apps)
        }

        if request.method == "GET", components.count == 5, components[2] == "apps", components[4] == "icon" {
            guard let icon = await MainActor.run(body: {
                AppManagementService.shared.app(bundleIdentifier: components[3])?.appInfo.iconIsDarkIcon(false)?.pngData()
            }) else {
                return .json(404, ["error": "App icon not found."])
            }
            return .png(icon)
        }

        if request.method == "GET", components.count == 4, components[2] == "apps" {
            guard let app = await MainActor.run(body: { AppManagementService.shared.app(bundleIdentifier: components[3]) }) else {
                return .json(404, ["error": "App not found."])
            }
            return .json(200, Self.metadata(app))
        }

        if request.method == "GET", components.count == 4, components[2] == "jobs" {
            guard let job = await RemoteAPIJobStore.shared.job(components[3]) else {
                return .json(404, ["error": "Job not found."])
            }
            return .json(200, Self.dictionary(job))
        }

        if request.method == "POST", components.count == 5, components[2] == "jobs", components[4] == "resolve" {
            guard let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
                  let action = body["action"], ["copy", "replace", "cancel"].contains(action) else {
                return .json(400, ["error": "Expected a copy, replace, or cancel action."])
            }
            guard await RemoteAPIJobStore.shared.resolveConflict(components[3], action: action) else {
                return .json(404, ["error": "Job is not waiting for a conflict decision."])
            }
            return .json(200, ["success": true])
        }

        if request.method == "DELETE", components.count == 4, components[2] == "apps" {
            do {
                try await MainActor.run { try AppManagementService.shared.removeApp(bundleIdentifier: components[3]) }
                logger.info("deleted app \(components[3], privacy: .public)")
                return .json(200, ["success": true])
            } catch AppManagementError.appNotFound {
                return .json(404, ["error": "App not found."])
            } catch {
                return .json(500, ["error": error.localizedDescription])
            }
        }

        if request.method == "POST", components.count == 4, components[2] == "apps", components[3] == "url" {
            guard let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
                  let urlString = body["url"], let url = URL(string: urlString),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                return .json(400, ["error": "Expected a valid HTTP or HTTPS IPA URL."])
            }
            let jobID = await RemoteAPIJobStore.shared.create()
            logger.info("starting URL install job \(jobID, privacy: .public)")
            Task {
                await self.runURLInstallJob(jobID, url: url)
            }
            return .json(202, ["job": jobID, "status": "installing"])
        }

        let isInstall = request.method == "POST" && components.count == 3 && components[2] == "apps"
        let isUpdate = request.method == "PUT" && components.count == 4 && components[2] == "apps"
        if isInstall || isUpdate {
            if isUpdate, await MainActor.run(body: { AppManagementService.shared.app(bundleIdentifier: components[3]) }) == nil {
                return .json(404, ["error": "App not found."])
            }
            guard let contentType = request.headers["content-type"],
                  let ipaData = multipartField(named: "ipa", contentType: contentType, body: request.body) else {
                return .json(400, ["error": "Expected multipart/form-data with an ipa field."])
            }
            let uploadURL = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteAPI-\(UUID().uuidString).ipa")
            do {
                try ipaData.write(to: uploadURL, options: .atomic)
            } catch {
                return .json(500, ["error": error.localizedDescription])
            }
            let jobID = await RemoteAPIJobStore.shared.create()
            logger.info("received upload for job \(jobID, privacy: .public)")
            let replacingBundleIdentifier = isUpdate ? components[3] : nil
            logger.info("starting \(isUpdate ? "update" : "install", privacy: .public) job \(jobID, privacy: .public)")
            Task {
                await self.runInstallJob(jobID, uploadURL: uploadURL, replacingBundleIdentifier: replacingBundleIdentifier)
            }
            return .json(202, ["job": jobID, "status": "installing"])
        }

        return .json(404, ["error": "Not found."])
    }

    private func runURLInstallJob(_ id: String, url: URL) async {
        await RemoteAPIJobStore.shared.update(id, status: "uploading", progress: 0)
        do {
            let (downloadURL, response) = try await URLSession.shared.download(from: url)
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                throw "The IPA server returned an invalid response."
            }
            if response.expectedContentLength > Int64(RemoteAPISettings.maximumUploadBytes) {
                throw "Download exceeds the configured size limit."
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: downloadURL.path)
            guard let fileSize = attributes[.size] as? NSNumber, fileSize.intValue <= RemoteAPISettings.maximumUploadBytes else {
                throw "Download exceeds the configured size limit."
            }
            let ipaURL = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteAPI-\(UUID().uuidString).ipa")
            try FileManager.default.moveItem(at: downloadURL, to: ipaURL)
            await runInstallJob(id, uploadURL: ipaURL, replacingBundleIdentifier: nil)
        } catch {
            await RemoteAPIJobStore.shared.update(id, status: "failed", progress: 0, error: error.localizedDescription)
            logger.error("URL install job failed \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func runInstallJob(_ id: String, uploadURL: URL, replacingBundleIdentifier: String?, relaunchContainer: String? = nil) async {
        defer { try? FileManager.default.removeItem(at: uploadURL) }
        await RemoteAPIJobStore.shared.update(id, status: "extracting", progress: 0)
        do {
            let installedApp = try await AppManagementService.shared.installIPA(at: uploadURL, replacingBundleIdentifier: replacingBundleIdentifier, restartRunningApp: true, remoteJobID: id, resolveConflict: { apps, suggestedPath in
                let bundleID = apps.first?.bundleIdentifier ?? suggestedPath.replacingOccurrences(of: ".app", with: "")
                let action = await RemoteAPIJobStore.shared.waitForConflictResolution(id, bundleID: bundleID, apps: apps.map { $0.displayName })
                if action == "copy" {
                    return AppInstallDecision(relativeBundlePath: suggestedPath, appToReplace: nil)
                }
                if action == "replace", let app = apps.first {
                    return AppInstallDecision(relativeBundlePath: app.appInfo.relativeBundlePath, appToReplace: app)
                }
                return nil
            }, progress: { stage, progress in
                Task { await RemoteAPIJobStore.shared.update(id, status: stage.rawValue, progress: progress) }
            })
            await RemoteAPIJobStore.shared.update(id, status: "complete", progress: 100)
            logger.info("install job completed \(id, privacy: .public)")
            if let relaunchContainer {
                let defaults = UserDefaults.lc() ?? .standard
                defaults.removeObject(forKey: AppManagementService.pendingRemoteUpdateKey)
                defaults.set(["job": id, "status": "complete", "progress": 100], forKey: RemoteAPISettings.lastJobKey)
                try? FileManager.default.removeItem(at: uploadURL)
                try await Task.sleep(nanoseconds: 500_000_000)
                var components = URLComponents()
                components.scheme = UserDefaults.lcAppUrlScheme()
                components.host = "livecontainer-launch"
                components.queryItems = [
                    URLQueryItem(name: "bundle-name", value: installedApp.appInfo.relativeBundlePath),
                    URLQueryItem(name: "container-folder-name", value: relaunchContainer)
                ]
                if let url = components.url {
                    await UIApplication.shared.open(url)
                }
            }
        } catch {
            if relaunchContainer != nil {
                (UserDefaults.lc() ?? .standard).removeObject(forKey: AppManagementService.pendingRemoteUpdateKey)
            }
            await RemoteAPIJobStore.shared.update(id, status: "failed", progress: 0, error: error.localizedDescription)
            logger.error("install job failed \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func multipartField(named name: String, contentType: String, body: Data) -> Data? {
        guard let boundary = contentType.components(separatedBy: "boundary=").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
              contentType.lowercased().contains("multipart/form-data") else {
            return nil
        }
        let fieldMarker = Data("name=\"\(name)\"".utf8)
        guard let fieldRange = body.range(of: fieldMarker),
              let headerEnd = body.range(of: Data("\r\n\r\n".utf8), in: fieldRange.upperBound..<body.endIndex) else {
            return nil
        }
        let closingBoundary = Data("\r\n--\(boundary)".utf8)
        guard let end = body.range(of: closingBoundary, in: headerEnd.upperBound..<body.endIndex) else {
            return nil
        }
        return Data(body[headerEnd.upperBound..<end.lowerBound])
    }

    private func send(_ response: RemoteAPIResponse, on connection: NWConnection) {
        let reason: String
        switch response.status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        default: reason = "Internal Server Error"
        }
        var data = Data("HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n".utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func metadata(_ app: LCAppModel) -> [String: Any] {
        [
            "bundleID": app.bundleIdentifier,
            "name": app.displayName,
            "version": app.version,
            "build": app.appInfo.info()["CFBundleVersion"] as? String ?? "",
            "locked": app.appInfo.isLocked
        ]
    }

    private static func dictionary(_ job: RemoteAPIJob) -> [String: Any] {
        var result: [String: Any] = ["status": job.status, "progress": job.progress]
        if let error = job.error {
            result["error"] = error
        }
        if let conflict = job.conflict {
            result["conflict"] = ["bundleID": conflict.bundleID, "apps": conflict.apps]
        }
        return result
    }
}

@_cdecl("LCStartRemoteAPI")
@MainActor
public func startRemoteAPIForGuestApp() {
    let defaults = UserDefaults.lc() ?? .standard
    guard defaults.bool(forKey: RemoteAPISettings.enabledKey) else {
        return
    }
    _ = AppManagementService.shared.reloadInstalledApps()
    let configuredPort = defaults.integer(forKey: RemoteAPISettings.portKey)
    let port = configuredPort == 0 ? RemoteAPISettings.defaultPort : configuredPort
    _ = RemoteAPITokenStore.tokenCreatingIfNeeded()
    try? RemoteAPIServer.shared.start(port: port)
    RemoteAPIServer.shared.restoreLastJobIfNeeded()
}
