//
//  LCRemoteAPI.swift
//  LiveContainerSwiftUI
//  Summary (EN): REST route table: apps, IPAs, tweaks, windows, logs, screenshots, UI automation and the guest proxy.
//
//  Routes and handlers: read operations, install/uninstall, tweaks, logs, windows and UI automation.
//  Convention: every route except /health requires `Authorization: Bearer <token>`.
//

import Foundation

enum LCRemoteAPI {

    static func handle(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let path = req.path

        // No auth: exposes liveness only, for probes
        if path == "/api/v1/health" && req.method == "GET" {
            return .json([
                "ok": true,
                "server": "LiveContainer-Remote/1",
                "version": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "",
                "port": Int(LCRemoteConfig.port)
            ])
        }

        guard let token = req.bearerToken, equalsConstTime(token, LCRemoteConfig.token) else {
            return .error("missing or invalid bearer token", status: 401, code: "unauthorized")
        }

        do {
            switch (req.method, path) {
            case (_, let p) where p.hasPrefix("/api/v1/guest/"):
                return await LCRemoteGuestProxy.forward(req, path: p)

            case ("GET", "/api/v1/self"):
                return await selfInfo()

            case ("GET", "/api/v1/config"):
                let keepAlive = await MainActor.run { LCRemoteKeepAlive.shared.status }
                return .json([
                    "enabled": LCRemoteConfig.isEnabled,
                    "port": Int(LCRemoteConfig.port),
                    "keepAlive": keepAlive,
                    "apps": await MainActor.run { DataManager.shared.model.apps.count }
                ])

            case ("POST", "/api/v1/keepalive"):
                return await keepAlive(req)

            case ("GET", "/api/v1/apps"):
                return try await listApps()

            case ("POST", "/api/v1/apps"):
                return try await install(req)

            case ("GET", "/api/v1/logs"):
                return await logs(req)

            case ("POST", "/api/v1/logs"):
                // Push: the container, a tweak inside the guest, or an external script can append a line
                // body {"msg":"...","src":"tweak"} or ?msg=
                let obj = jsonBody(req)
                let msg = (obj["msg"] as? String) ?? req.query["msg"] ?? ""
                let src = (obj["src"] as? String) ?? req.query["src"] ?? "push"
                guard !msg.isEmpty else {
                    return .error("msg is required", status: 400, code: "bad_request")
                }
                LCRemoteLogStore.shared.append(msg, src: src)
                return .json(["pushed": true, "src": src, "latest": LCRemoteLogStore.shared.latestSeq])

            case ("GET", "/api/v1/logs/guest"):
                return guestLogs(req)

            case ("DELETE", "/api/v1/logs/guest"):
                let removed = LCRemoteGuestLogs.clear(name: req.query["name"])
                return .json(["removed": removed])

            case ("GET", "/api/v1/macho"):
                // ?path=/abs/path/to/binary   (read-only static inspection)
                let raw = req.query["path"] ?? ""
                guard !raw.isEmpty else {
                    return .error("path is required (absolute path to a Mach-O file)", status: 400, code: "bad_request")
                }
                let path = raw.removingPercentEncoding ?? raw
                return .json(LCRemoteMachO.inspect(path: path))

            case ("GET", let p) where p.hasPrefix("/api/v1/apps/") && !p.contains("/launch"):
                var bundleId = String(p.dropFirst("/api/v1/apps/".count))
                guard !bundleId.isEmpty, !bundleId.contains("/") else {
                    return .error("GET /api/v1/apps/{bundleId} takes a bundle id", status: 400, code: "bad_request")
                }
                bundleId = bundleId.removingPercentEncoding ?? bundleId
                return await appDetail(bundleId: bundleId)

            case ("PATCH", let p) where p.hasPrefix("/api/v1/apps/"):
                let bundleId = String(p.dropFirst("/api/v1/apps/".count)).removingPercentEncoding ?? ""
                return await appConfig(req, bundleId: bundleId)

            case ("DELETE", let p) where p.hasPrefix("/api/v1/apps/"):
                let bundleId = String(p.dropFirst("/api/v1/apps/".count)).removingPercentEncoding ?? ""
                return try await uninstall(bundleId: bundleId, keepData: req.query["keepData"] == "1" || req.query["keepData"] == "true")

            case ("POST", "/api/v1/apps/open"):
                return await openApp(req)

            case ("POST", "/api/v1/apps/from-url"):
                return await installFromURL(req)

            case ("GET", "/api/v1/jobs"):
                return await jobsList()

            case ("GET", let p) where p.hasPrefix("/api/v1/jobs/"):
                return await jobStatus(String(p.dropFirst("/api/v1/jobs/".count)))

            case ("POST", let p) where p.hasPrefix("/api/v1/apps/") && p.hasSuffix("/launch"):
                let bundleId = String(p.dropFirst("/api/v1/apps/".count).dropLast("/launch".count))
                return try await launch(req, bundleId: bundleId)

            case ("GET", "/api/v1/tweaks"):
                return try await tweakList(folder: req.query["folder"])

            case ("POST", "/api/v1/tweaks"):
                return try await tweakImport(req, folder: req.query["folder"])

            case ("PATCH", "/api/v1/tweaks"):
                return try await tweakSetEnabled(req)

            case ("DELETE", "/api/v1/tweaks"):
                return try await tweakDelete(req)

            case ("POST", "/api/v1/tweaks/sign"):
                return try await tweakSign(req)

            case ("POST", "/api/v1/tweakfolders"):
                return try await tweakCreateFolder(req)

            case ("GET", let p) where p.hasPrefix("/api/v1/windows/"):
                // GET /api/v1/windows/{id}/chrome -> selectors bound to the three title-bar buttons
                let parts = p.dropFirst("/api/v1/windows/".count).split(separator: "/")
                guard parts.count == 2, parts[1] == "chrome" else {
                    return .error("unknown endpoint \(p)", status: 404, code: "not_found")
                }
                return await windowChrome(String(parts[0]))

            case ("GET", "/api/v1/windows"):
                return await windowList(req)

            case ("POST", let p) where p.hasPrefix("/api/v1/windows/"):
                return try await windowAction(req, path: p)

            case ("GET", "/api/v1/screenshot"):
                return await screenshot(req)

            case ("GET", "/api/v1/ui/tree"):
                return await uiTree()

            case ("POST", "/api/v1/ui/activate"):
                return await uiActivate(req)

            case ("POST", "/api/v1/ui/taps"):
                return await uiTaps(req)

            case ("POST", "/api/v1/ui/tap"):
                return await uiTap(req)

            case ("POST", "/api/v1/ui/tab"):
                return await uiTab(req)

            case ("POST", "/api/v1/ui/text"):
                return await uiText(req)

            default:
                return .error("no route for \(req.method) \(path)", status: 404, code: "not_found")
            }
        } catch {
            LCRemoteLogStore.shared.append("\(req.method) \(path) failed: \(error.localizedDescription)", src: "api")
            return .error(error.localizedDescription, status: 500, code: "internal")
        }
    }

    // MARK: - List apps

    private static func listApps() async throws -> LCRemoteResponse {
        let items: [[String: Any]] = await MainActor.run {
            DataManager.shared.model.apps.map { LCAppInstaller.summary(of: $0) }
        }
        return .json(["count": items.count, "apps": items])
    }

    // MARK: - Install

    private static func install(_ req: LCRemoteRequest) async throws -> LCRemoteResponse {
        let upload = try LCRemoteUpload.extract(req)
        defer { try? FileManager.default.removeItem(at: upload.url) }

        guard upload.filename.lowercased().hasSuffix(".ipa") else {
            return .error("only .ipa is accepted (got \(upload.filename))", status: 400, code: "bad_extension")
        }
        let replace = !(req.query["replace"] == "0" || req.query["replace"] == "false")
        LCRemoteLogStore.shared.append("installing \(upload.filename) (\(replace ? "replace" : "keep") )", src: "api")

        let info = try await LCAppInstaller.install(ipa: upload.url, replaceExisting: replace)
        return .json([
            "bundleId": info.bundleIdentifier() ?? "",
            "name": info.displayName() ?? "",
            "version": info.version() ?? "",
            "relativePath": info.relativeBundlePath ?? ""
        ], status: 201)
    }

    // MARK: - Uninstall

    private static func uninstall(bundleId: String, keepData: Bool) async throws -> LCRemoteResponse {
        guard !bundleId.isEmpty else {
            return .error("bundleId is empty", status: 400, code: "bad_request")
        }
        let result = try await MainActor.run {
            try LCAppInstaller.uninstall(bundleId: bundleId, removeData: !keepData)
        }
        return .json(result)
    }

    /// GET /api/v1/apps/{bundleId}: everything needed to reason about one app before launching it:
    /// AppInfo flags, its tweaks split local/shared with enabled state, and a static Mach-O summary of the
    /// main executable (architecture, tweak-loader linkage, code-signature validity).
    @MainActor
    private static func appDetail(bundleId: String) async -> LCRemoteResponse {
        let model = (DataManager.shared.model.apps + DataManager.shared.model.hiddenApps)
            .first { $0.appInfo.bundleIdentifier() == bundleId }
        guard let model else {
            return .error("app not found: \(bundleId)", status: 404, code: "not_found")
        }
        let info = model.appInfo
        var out = LCAppInstaller.summary(of: model)
        out["dataUUID"] = info.dataUUID ?? ""
        out["tweakFolder"] = info.tweakFolder ?? ""
        out["flags"] = [
            "classicMode": info.classicMode,
            "multitaskSpecified": Int(info.multitaskSpecified.rawValue),
            "isJITNeeded": info.isJITNeeded,
            "isLocked": info.isLocked,
            "isHidden": info.isHidden,
            "dontLoadTweakLoader": info.dontLoadTweakLoader,
            "dontInjectTweakLoader": info.dontInjectTweakLoader,
            "isShared": info.isShared
        ]

        // tweaks: local folder vs shared library
        var local: [[String: Any]] = []
        var shared: [[String: Any]] = []
        if let folder = info.tweakFolder, !folder.isEmpty {
            local = (try? LCTweakManager.list(folder: folder))?.map { $0.json } ?? []
        }
        shared = (try? LCTweakManager.list(folder: ""))?.map { $0.json } ?? []
        out["localTweaks"] = local
        out["sharedTweaks"] = shared

        // static Mach-O summary of the executable
        if let bundlePath = info.bundlePath() {
            let execPath = (bundlePath as NSString).appendingPathComponent(
                (info.info()["CFBundleExecutable"] as? String) ?? "")
            if FileManager.default.fileExists(atPath: execPath) {
                let macho = LCRemoteMachO.inspect(path: execPath)
                let slices = macho["slices"] as? [[String: Any]] ?? []
                out["executable"] = execPath
                out["machO"] = [
                    "fat": macho["fat"] ?? false,
                    "architectures": slices.compactMap { $0["cpu"] as? String },
                    "fileType": slices.first?["fileType"] ?? "",
                    "tweakLoaderLinked": slices.contains { ($0["tweakLoaderLinked"] as? Bool) == true },
                    "signatureValid": slices.allSatisfy { (($0["codeSignature"] as? [String: Any])?["valid"] as? Bool) == true },
                    "adhoc": slices.allSatisfy { (($0["codeSignature"] as? [String: Any])?["adhoc"] as? Bool) == true },
                    "cdhash": (slices.first?["codeSignature"] as? [String: Any])?["cdhash"] ?? ""
                ]
            }
        }
        return .json(out)
    }

    /// PATCH /api/v1/apps/{bundleId}: flip the AppInfo switches the UI exposes (launch mode, JIT, lock, hidden,
    /// per-app tweak folder) and persist them.
    @MainActor
    private static func appConfig(_ req: LCRemoteRequest, bundleId: String) async -> LCRemoteResponse {
        let obj = jsonBody(req)
        guard !bundleId.isEmpty else { return .error("bundleId is empty", status: 400, code: "bad_request") }
        let model = (DataManager.shared.model.apps + DataManager.shared.model.hiddenApps)
            .first { $0.appInfo.bundleIdentifier() == bundleId }
        guard let model else {
            return .error("app not found: \(bundleId)", status: 404, code: "not_found")
        }
        let info = model.appInfo
        var applied: [String] = []
        func bool(_ key: String) -> Bool? {
            if let b = obj[key] as? Bool { return b }
            if let s = obj[key] as? String { return s == "1" || s.lowercased() == "true" }
            if let q = req.query[key] { return q == "1" || q.lowercased() == "true" }
            return nil
        }
        if let v = bool("classicMode") { info.classicMode = v; applied.append("classicMode") }
        if let v = bool("isJITNeeded") { info.isJITNeeded = v; applied.append("isJITNeeded") }
        if let v = bool("isLocked") { info.isLocked = v; applied.append("isLocked") }
        if let v = bool("isHidden") { info.isHidden = v; applied.append("isHidden") }
        if let v = bool("dontLoadTweakLoader") { info.dontLoadTweakLoader = v; applied.append("dontLoadTweakLoader") }
        if let v = bool("dontInjectTweakLoader") { info.dontInjectTweakLoader = v; applied.append("dontInjectTweakLoader") }
        if let raw = (obj["multitask"] as? String) ?? req.query["multitask"] {
            let map: [String: Int] = ["default": 0, "no": 1, "yes": 2]
            if let rawValue = map[raw.lowercased()],
               let m = MultitaskSpecified(rawValue: rawValue) {
                info.multitaskSpecified = m
                applied.append("multitaskSpecified")
            }
        }
        if let folder = (obj["tweakFolder"] as? String) ?? req.query["tweakFolder"] {
            info.tweakFolder = folder.isEmpty ? nil : folder
            applied.append("tweakFolder")
        }
        guard !applied.isEmpty else {
            return .error("nothing to change: send classicMode / multitask / isJITNeeded / isLocked / isHidden / tweakFolder",
                          status: 400, code: "bad_request")
        }
        info.save()
        LCRemoteLogStore.shared.append("app \(bundleId) config updated: \(applied.joined(separator: ","))", src: "api")
        return await appDetail(bundleId: bundleId)
    }

    /// One-shot: open an installed app in a multitask window, wait for the guest sidecar, return window + guest pid.
    /// Usage: {"bundleId":"com.xxx","container":"<optional>","url":"<optional>"} or ?bundleId=
    @MainActor
    private static func openApp(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let obj = jsonBody(req)
        guard let bundleId = ((obj["bundleId"] as? String) ?? req.query["bundleId"]), !bundleId.isEmpty else {
            return .error("bundleId is required", status: 400, code: "bad_request")
        }
        let model = (DataManager.shared.model.apps + DataManager.shared.model.hiddenApps)
            .first { $0.appInfo.bundleIdentifier() == bundleId }
        guard let model else {
            return .error("app not found: \(bundleId)", status: 404, code: "not_found")
        }
        let container = (obj["container"] as? String) ?? req.query["container"]
        let urlStr = (obj["url"] as? String) ?? req.query["url"]
        do {
            try await model.runApp(multitask: true, containerFolderName: container, urlStr: urlStr)
        } catch {
            return .error("launch failed: \(error.localizedDescription)", status: 500, code: "launch_failed")
        }

        // Wait for the guest sidecar (up to ~10 s) and return the window info along the way
        var guest: [String: Any]?
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let probe = await LCRemoteGuestProxy.forward(
                LCRemoteRequest(method: "GET", path: "/api/v1/guest/info"), path: "/api/v1/guest/info")
            if probe.status == 200, let o = try? JSONSerialization.jsonObject(with: probe.body) as? [String: Any] {
                guest = o
                break
            }
        }
        let windows = LCWindowManager.windows()
            .filter { $0.bundleId.hasPrefix(bundleId) }
            .map { $0.json }
        return .json([
            "opened": true,
            "bundleId": bundleId,
            "windows": windows,
            "guest": guest ?? NSNull(),
            "guestReady": guest != nil
        ])
    }

    // MARK: - Async jobs (device-side IPA download)

    @MainActor
    private static func installFromURL(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let obj = (try? JSONSerialization.jsonObject(with: req.bodyData())) as? [String: Any]
        guard let raw = ((obj?["url"] as? String) ?? req.query["url"]), !raw.isEmpty else {
            return .error("url is required", status: 400, code: "bad_request")
        }
        let nameHint = (obj?["filename"] as? String) ?? req.query["filename"]
        let replace: Bool = {
            if let b = obj?["replace"] as? Bool { return b }
            if let s = req.query["replace"] { return s != "0" && s.lowercased() != "false" }
            return true
        }()
        var urlString = raw
        if !urlString.contains(".") , let hint = nameHint, !hint.isEmpty {
            urlString += "/" + hint
        }
        let job = LCRemoteJobs.shared.create(kind: "install_ipa_from_url")
        job.message = "queued \(urlString)"
        Task { @MainActor in
            await LCRemoteJobs.shared.runInstall(job, urlString: urlString, replaceExisting: replace)
        }
        return .json(job.json, status: 202)
    }

    @MainActor
    private static func jobsList() async -> LCRemoteResponse {
        let items = LCRemoteJobs.shared.all().map { $0.json }
        return .json(["count": items.count, "jobs": items])
    }

    @MainActor
    private static func jobStatus(_ id: String) async -> LCRemoteResponse {
        guard let job = LCRemoteJobs.shared.get(id) else {
            return .error("no such job: \(id)", status: 404, code: "not_found")
        }
        return .json(job.json)
    }

    // MARK: - Launch

    @MainActor
    private static func launch(_ req: LCRemoteRequest, bundleId: String) async throws -> LCRemoteResponse {
        let model = (DataManager.shared.model.apps + DataManager.shared.model.hiddenApps)
            .first { $0.appInfo.bundleIdentifier() == bundleId }
        guard let model else {
            return .error("app not found: \(bundleId)", status: 404, code: "not_found")
        }
        let container = req.query["container"].flatMap { $0.isEmpty ? nil : $0 }
        let urlStr = req.query["url"].flatMap { $0.isEmpty ? nil : $0 }
        // multitask=1 -> run inside a LiveContainer multitask window so the host UI stays up and the HTTP server keeps serving
        let multitask: Bool? = req.query["multitask"].map { $0 == "1" || $0.lowercased() == "true" }
        LCRemoteLogStore.shared.append("launch \(bundleId) (container=\(container ?? "-"), url=\(urlStr ?? "-"))", src: "api")
        do {
            try await model.runApp(multitask: multitask, containerFolderName: container, urlStr: urlStr)
        } catch {
            return .error("launch failed: \(error.localizedDescription)", status: 500, code: "launch_failed")
        }
        return .json(["launched": true, "bundleId": bundleId,
                      "multitask": multitask.map { $0 } ?? NSNull(),
                      "isAppRunning": model.isAppRunning])
    }

    // MARK: - Tweaks

    @MainActor
    private static func tweakList(folder: String?) async throws -> LCRemoteResponse {
        let items = try LCTweakManager.list(folder: folder)
        let folders: [String] = DataManager.shared.model.tweakFolderNames
        return .json(["folder": folder ?? "", "count": items.count,
                      "tweaks": items.map { $0.json }, "folders": folders])
    }

    @MainActor
    private static func tweakImport(_ req: LCRemoteRequest, folder: String?) async throws -> LCRemoteResponse {
        let ctype = (req.header("content-type") ?? "").lowercased()
        if ctype.hasPrefix("application/json") {
            return .error("POST /api/v1/tweaks expects a multipart file; to toggle a tweak use PATCH /api/v1/tweaks {name,enabled,folder}",
                          status: 400, code: "bad_request")
        }
        let upload = try LCRemoteUpload.extract(req)
        // Import is a move: the body already sits in a temp file, the manager relocates it
        let name = req.query["filename"] ?? upload.filename
        let summary = try await LCTweakManager.importTweak(from: upload.url, folder: folder, filename: name)
        return .json(summary.json, status: 201)
    }

    @MainActor
    private static func tweakSetEnabled(_ req: LCRemoteRequest) async throws -> LCRemoteResponse {
        let body = req.bodyData()
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let name = (obj?["name"] as? String) ?? req.query["name"] ?? ""
        let enabled: Bool = {
            if let b = obj?["enabled"] as? Bool { return b }
            if let s = obj?["enabled"] as? String { return s == "1" || s.lowercased() == "true" }
            return req.query["enabled"] == "1" || req.query["enabled"] == "true"
        }()
        let folder = (obj?["folder"] as? String) ?? req.query["folder"]
        guard !name.isEmpty else {
            return .error("name is required", status: 400, code: "bad_request")
        }
        let summary = try LCTweakManager.setEnabled(folder: folder, name: name, enabled: enabled)
        return .json(summary.json)
    }

    @MainActor
    private static func tweakDelete(_ req: LCRemoteRequest) async throws -> LCRemoteResponse {
        guard let name = req.query["name"], !name.isEmpty else {
            return .error("name is required", status: 400, code: "bad_request")
        }
        try LCTweakManager.delete(folder: req.query["folder"], name: name)
        return .json(["deleted": name])
    }

    @MainActor
    private static func tweakSign(_ req: LCRemoteRequest) async throws -> LCRemoteResponse {
        let force = req.query["force"] == "1" || req.query["force"] == "true"
        let result = try await LCTweakManager.sign(folder: req.query["folder"], force: force)
        return .json(result)
    }

    @MainActor
    private static func tweakCreateFolder(_ req: LCRemoteRequest) async throws -> LCRemoteResponse {
        let body = req.bodyData()
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let name = (obj?["name"] as? String) ?? req.query["name"] ?? ""
        guard !name.isEmpty else {
            return .error("name is required", status: 400, code: "bad_request")
        }
        let created = try LCTweakManager.createFolder(name)
        return .json(["created": created], status: 201)
    }

    @MainActor
    private static func windowChrome(_ id: String) async -> LCRemoteResponse {
        let buttons = LCWindowManager.chromeButtons(id)
        return .json(["id": id, "count": buttons.count, "buttons": buttons])
    }

    // MARK: - Multitask windows / screenshots

    @MainActor
    private static func windowList(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let all = LCWindowManager.windows()
        // Closed windows stay in the controller list (running=false); they are omitted unless ?all=1
        let includeClosed = req.query["all"] == "1" || req.query["all"]?.lowercased() == "true"
        let infos = includeClosed ? all : all.filter { $0.isRunning }
        return .json(["count": infos.count, "windows": infos.map { $0.json },
                      "closed": all.count - infos.count])
    }

    /// POST /api/v1/windows/{id}/{scale|pip|maximize|close}
    /// Parameters via query or JSON body: scale=<0.4-3.0>, enabled=true/false
    @MainActor
    private static func windowAction(_ req: LCRemoteRequest, path: String) async throws -> LCRemoteResponse {
        let rest = String(path.dropFirst("/api/v1/windows/".count))
        let parts = rest.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return .error("usage: /api/v1/windows/{id}/scale|pip|maximize|close|press", status: 400, code: "bad_request")
        }
        let id = parts[0].removingPercentEncoding ?? parts[0]
        let action = parts[1]
        let body = req.bodyData()
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]

        func boolValue(_ key: String, default def: Bool) -> Bool {
            if let b = obj?[key] as? Bool { return b }
            if let s = obj?[key] as? String { return s == "1" || s.lowercased() == "true" }
            if let q = req.query[key] { return q == "1" || q.lowercased() == "true" }
            return def
        }
        func doubleValue(_ key: String) -> Double? {
            if let d = obj?[key] as? Double { return d }
            if let s = obj?[key] as? String { return Double(s) }
            if let q = req.query[key] { return Double(q) }
            return nil
        }

        do {
            switch action {
            case "scale":
                guard let v = doubleValue("scale") ?? doubleValue("value") else {
                    return .error("scale needs a number", status: 400, code: "bad_request")
                }
                try LCWindowManager.setScale(id, CGFloat(v))
            case "pip":
                try LCWindowManager.setPiP(id, enabled: boolValue("enabled", default: true))
            case "maximize":
                try LCWindowManager.setMaximized(id, maximized: boolValue("enabled", default: true))
            case "close":
                return await terminateWindow(id)
            case "press":
                guard let sel = (obj?["selector"] as? String) ?? req.query["selector"], !sel.isEmpty else {
                    return .error("press needs a selector, e.g. closeWindow / maximizeWindow / minimizeWindow",
                                  status: 400, code: "bad_request")
                }
                do {
                    let r = try LCWindowManager.pressChrome(id, selector: sel)
                    return .json(["ok": true, "action": "press", "id": id, "result": r,
                                  "windows": LCWindowManager.windows().filter { $0.isRunning }.map { $0.json }])
                } catch {
                    return .error(error.localizedDescription, status: 400, code: "press_failed")
                }
            default:
                return .error("unknown action \(action)", status: 400, code: "bad_request")
            }
        } catch {
            return .error(error.localizedDescription, status: 400, code: "window_action_failed")
        }
        let infos = LCWindowManager.windows()
        return .json(["ok": true, "action": action, "id": id,
                      "windows": infos.map { $0.json }])
    }

    /// Closing a window really kills the guest process.
    /// Device-tested pitfall: AppSceneViewController.terminate() sends SIGTERM then SIGKILL after 3 s,
    /// and a dataUUID lookup can return the previous (zombie) controller, so the signal hits nothing.
    /// This therefore polls the pid after terminate and falls back to kill(SIGKILL) while it is still alive.
    @MainActor
    private static func terminateWindow(_ id: String) async -> LCRemoteResponse {
        let before = LCWindowManager.windows().first { $0.id == id }
        let pid = before?.pid ?? 0
        do {
            try LCWindowManager.close(id)
        } catch {
            return .error("close failed: \(error.localizedDescription)", status: 400, code: "close_failed")
        }

        var alive = pid > 0
        var waited = 0
        while waited < 6000 && alive {
            try? await Task.sleep(nanoseconds: 250_000_000)
            waited += 250
            alive = pid > 0 && kill(pid_t(pid), 0) == 0
        }
        var forced = false
        if alive && pid > 0 {
            forced = kill(pid_t(pid), SIGKILL) == 0
            try? await Task.sleep(nanoseconds: 300_000_000)
            alive = kill(pid_t(pid), 0) == 0
        }
        LCRemoteLogStore.shared.append("window \(id) close: pid=\(pid) alive=\(alive) forced=\(forced)", src: "api")
        let live = LCWindowManager.windows().filter { $0.isRunning }
        return .json(["ok": !alive, "action": "close", "id": id, "pid": pid,
                      "killed": !alive, "forcedKill": forced, "waitedMs": waited,
                      "windows": live.map { $0.json }])
    }

    @MainActor
    private static func screenshot(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let windowId = req.query["windowId"] ?? req.query["id"]
        let quality = min(max((Double(req.query["quality"] ?? "70") ?? 70) / 100.0, 0.1), 1.0)
        let maxWidth = CGFloat(Double(req.query["maxWidth"] ?? "1290") ?? 1290)
        guard let data = LCScreenshot.capture(windowId: windowId, maxWidth: maxWidth, quality: CGFloat(quality)) else {
            return .error("capture failed (window hidden or view empty)", status: 500, code: "capture_failed")
        }
        return LCRemoteResponse(status: 200,
                                headers: ["Content-Type": "image/jpeg",
                                          "X-Window-Id": windowId ?? "key"],
                                body: data)
    }

    // MARK: - Keep-alive

    @MainActor
    private static func keepAlive(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let body = req.bodyData()
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let raw = (obj?["mode"] as? String) ?? req.query["mode"]
        guard let raw, let mode = LCRemoteKeepAliveMode(rawValue: raw) else {
            let allowed = LCRemoteKeepAliveMode.allCases.map { $0.rawValue }
            return .error("mode must be one of \(allowed.joined(separator: " / "))", status: 400, code: "bad_request")
        }
        LCRemoteKeepAlive.shared.apply(mode)
        return .json(["ok": true, "keepAlive": LCRemoteKeepAlive.shared.status])
    }

    // MARK: - Self info (diagnosing install issues such as a missing extension)

    @MainActor
    private static func selfInfo() async -> LCRemoteResponse {
        let fm = FileManager.default
        let main = Bundle.main
        var plugins: [[String: Any]] = []
        if let dir = main.builtInPlugInsURL {
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names.sorted() {
                let url = dir.appendingPathComponent(name)
                let bundle = Bundle(url: url)
                let exec = bundle?.executableURL
                plugins.append([
                    "name": name,
                    "bundleId": bundle?.bundleIdentifier ?? "",
                    "executable": exec?.lastPathComponent ?? "",
                    "executableExists": exec.map { fm.fileExists(atPath: $0.path) } ?? false
                ])
            }
        }
        var frameworks: [String] = []
        if let fwDir = main.privateFrameworksURL {
            frameworks = ((try? fm.contentsOfDirectory(atPath: fwDir.path)) ?? []).sorted()
        }
        return .json([
            "bundlePath": main.bundlePath,
            "bundleId": main.bundleIdentifier ?? "",
            "version": (main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "",
            "build": (main.infoDictionary?["CFBundleVersion"] as? String) ?? "",
            "pluginsPath": main.builtInPlugInsURL?.path ?? "",
            "plugins": plugins,
            "frameworks": frameworks
        ])
    }

    // MARK: - UI automation

    private static func jsonBody(_ req: LCRemoteRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: req.bodyData())) as? [String: Any] ?? [:]
    }

    @MainActor
    private static func uiTree() async -> LCRemoteResponse {
        let items = LCRemoteUIAutomation.tree()
        return .json(["count": items.count, "elements": items.map { $0.json }])
    }

    /// {"index":12} or {"label":"App"} / {"identifier":"xxx"} / {"text":"..."}
    @MainActor
    private static func uiActivate(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let obj = jsonBody(req)
        if let raw = obj["index"] as? Int {
            let r = LCRemoteUIAutomation.activate(index: raw)
            return .json(["ok": r.ok, "detail": r.detail, "index": raw])
        }
        if let rawStr = obj["index"] as? String, let raw = Int(rawStr) {
            let r = LCRemoteUIAutomation.activate(index: raw)
            return .json(["ok": r.ok, "detail": r.detail, "index": raw])
        }
        let label = (obj["label"] as? String) ?? req.query["label"] ?? ""
        let ident = (obj["identifier"] as? String) ?? req.query["identifier"] ?? ""
        // Activate by visible text (does not rely on a11y labels)
        let text = (obj["text"] as? String) ?? req.query["text"] ?? ""
        if label.isEmpty && ident.isEmpty && !text.isEmpty {
            let r = LCRemoteUIAutomation.activate(text: text)
            return .json(["ok": r.ok, "detail": r.detail, "text": text])
        }
        guard !label.isEmpty || !ident.isEmpty else {
            return .error("need one of index / text / label / identifier", status: 400, code: "bad_request")
        }
        let r = LCRemoteUIAutomation.activate(label: label, identifier: ident)
        return .json(["ok": r.ok, "detail": r.detail, "label": label, "identifier": ident])
    }

    /// {"x":120,"y":300}
    @MainActor
    private static func uiTap(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let obj = jsonBody(req)
        func number(_ key: String) -> Double? {
            if let d = obj[key] as? Double { return d }
            if let i = obj[key] as? Int { return Double(i) }
            if let s = obj[key] as? String { return Double(s) }
            if let q = req.query[key] { return Double(q) }
            return nil
        }
        guard let x = number("x"), let y = number("y") else {
            return .error("x / y are required", status: 400, code: "bad_request")
        }
        let r = LCRemoteUIAutomation.tap(x: CGFloat(x), y: CGFloat(y))
        return .json(["ok": r.ok, "detail": r.detail, "x": x, "y": y])
    }

    /// {"index":1} or {"name":"App"}
    @MainActor
    private static func uiTab(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let obj = jsonBody(req)
        var index: Int?
        if let i = obj["index"] as? Int { index = i }
        else if let s = obj["index"] as? String { index = Int(s) }
        else if let q = req.query["index"] { index = Int(q) }
        if index == nil, let name = (obj["name"] as? String) ?? req.query["name"], !name.isEmpty {
            // By name: use accessibility activation (tab buttons always carry labels)
            let r = LCRemoteUIAutomation.activate(label: name, identifier: "")
            return .json(["ok": r.ok, "detail": r.detail, "name": name])
        }
        let r = LCRemoteUIAutomation.tab(index: index)
        return .json(["ok": r.ok, "detail": r.detail, "index": index ?? -1])
    }

    /// {"steps":[{"label":"Launch"},{"x":200,"y":300,"delayMs":800}], "detectChange":true, "captureAfter":true}
    @MainActor
    private static func uiTaps(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let obj = jsonBody(req)
        guard let steps = obj["steps"] as? [[String: Any]], !steps.isEmpty else {
            return .error("steps array is required", status: 400, code: "bad_request")
        }
        let detect = (obj["detectChange"] as? Bool) ?? true
        let results = await LCRemoteUIAutomation.runSequence(steps, detectChange: detect)
        var payload: [String: Any] = ["count": results.count, "steps": results]
        if (obj["captureAfter"] as? Bool) ?? false,
           let data = LCScreenshot.capture(windowId: obj["windowId"] as? String,
                                           maxWidth: 600, quality: 0.6) {
            payload["screenshotB64"] = data.base64EncodedString()
            payload["screenshotBytes"] = data.count
        }
        return .json(payload)
    }

    /// {"text":"hello"}
    @MainActor
    private static func uiText(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let obj = jsonBody(req)
        let text = (obj["text"] as? String) ?? req.query["text"] ?? ""
        guard !text.isEmpty else {
            return .error("text is required", status: 400, code: "bad_request")
        }
        let r = LCRemoteUIAutomation.typeText(text)
        return .json(["ok": r.ok, "detail": r.detail, "text": text])
    }

    // MARK: - Logs

    private static func logs(_ req: LCRemoteRequest) async -> LCRemoteResponse {
        let since = Int(req.query["since"] ?? "0") ?? 0
        let limit = min(max(Int(req.query["limit"] ?? "500") ?? 500, 1), 5000)
        let wait = min(max(Int(req.query["wait"] ?? "0") ?? 0, 0), 60)
        var (items, latest) = LCRemoteLogStore.shared.snapshot(since: since, limit: limit)
        if items.isEmpty && wait > 0 {
            let deadline = Date().addingTimeInterval(Double(wait))
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 250_000_000)
                (items, latest) = LCRemoteLogStore.shared.snapshot(since: since, limit: limit)
                if !items.isEmpty { break }
            }
        }
        return .json([
            "latest": latest,
            "count": items.count,
            "items": items.map { $0.json }
        ])
    }

    // MARK: - Guest logs (written by LiveProcess)

    private static func guestLogs(_ req: LCRemoteRequest) -> LCRemoteResponse {
        if let name = req.query["name"] {
            let offset = Int(req.query["offset"] ?? "0") ?? 0
            let limit = min(max(Int(req.query["limit"] ?? "65536") ?? 65536, 512), 1024 * 1024)
            guard let payload = LCRemoteGuestLogs.read(name: name, offset: offset, limitBytes: limit) else {
                return .error("no such log file: \(name)", status: 404, code: "not_found")
            }
            return .json(payload)
        }
        let items = LCRemoteGuestLogs.list()
        return .json(["count": items.count, "logs": items])
    }

    // MARK: - Helpers

    private static func equalsConstTime(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        guard ab.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }
}

// MARK: - Upload parsing (raw body or multipart/form-data)

enum LCRemoteUpload {
    struct Upload {
        let filename: String
        let url: URL
    }

    enum UploadError: LocalizedError {
        case emptyBody
        case badMultipart(String)
        var errorDescription: String? {
            switch self {
            case .emptyBody: return "request body is empty"
            case .badMultipart(let m): return "multipart parsing failed: \(m)"
            }
        }
    }

    private static let chunkSize = 4 * 1024 * 1024

    static func extract(_ req: LCRemoteRequest) throws -> Upload {
        let contentType = (req.header("content-type") ?? "").lowercased()
        let fallbackName = (req.query["filename"] ?? req.header("x-filename") ?? "upload.ipa")

        if contentType.hasPrefix("multipart/form-data") {
            guard let boundary = boundaryValue(from: req.header("content-type") ?? "") else {
                throw UploadError.badMultipart("no boundary")
            }
            let data = req.bodyData()
            guard !data.isEmpty else { throw UploadError.emptyBody }
            return try extractMultipart(data: data, boundary: boundary, fallbackName: fallbackName)
        }

        // raw body（curl -T）
        let dest = tempURL(name: fallbackName)
        try FileManager.default.createFile(atPath: dest.path, contents: nil)
        let fh = try FileHandle(forWritingTo: dest)
        defer { try? fh.close() }
        if let _ = req.bodyFile {
            try fh.write(contentsOf: req.bodyData())
        } else {
            guard !req.body.isEmpty else { throw UploadError.emptyBody }
            try fh.write(contentsOf: req.body)
        }
        return Upload(filename: sanitize(fallbackName), url: dest)
    }

    private static func extractMultipart(data: Data, boundary: String, fallbackName: String) throws -> Upload {
        let marker = Data("--\(boundary)".utf8)
        guard let firstMarker = data.range(of: marker) else {
            throw UploadError.badMultipart("start boundary not found")
        }
        // First part (prefer the one named "file")
        var cursor = firstMarker.upperBound
        for _ in 0..<8 {
            guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8),
                                            in: cursor..<data.endIndex) else {
                throw UploadError.badMultipart("part headers are unterminated")
            }
            let partHeaderText = String(data: data[cursor..<headerEnd.lowerBound], encoding: .utf8) ?? ""
            let contentStart = headerEnd.upperBound
            guard let nextMarker = data.range(of: Data("\r\n--\(boundary)".utf8),
                                              in: contentStart..<data.endIndex) else {
                throw UploadError.badMultipart("part has no closing boundary")
            }
            let contentEnd = nextMarker.lowerBound
            let lowerHeader = partHeaderText.lowercased()
            let hasFilename = lowerHeader.contains("filename=")
            if hasFilename || partHeaderText.contains("name=\"file\"") {
                let name = filenameValue(from: partHeaderText) ?? fallbackName
                let dest = tempURL(name: name)
                try FileManager.default.createFile(atPath: dest.path, contents: nil)
                let fh = try FileHandle(forWritingTo: dest)
                defer { try? fh.close() }
                var idx = contentStart
                while idx < contentEnd {
                    let end = min(idx + chunkSize, contentEnd)
                    try fh.write(contentsOf: data[idx..<end])
                    idx = end
                }
                return Upload(filename: sanitize(name), url: dest)
            }
            cursor = nextMarker.upperBound
            guard let again = data.range(of: marker, in: cursor..<data.endIndex) else {
                throw UploadError.badMultipart("no usable file part")
            }
            cursor = again.upperBound
        }
        throw UploadError.badMultipart("no usable file part")
    }

    private static func boundaryValue(from header: String) -> String? {
        for part in header.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("boundary=") else { continue }
            var v = String(trimmed.dropFirst("boundary=".count))
            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return v.isEmpty ? nil : v
        }
        return nil
    }

    private static func filenameValue(from partHeader: String) -> String? {
        guard let r = partHeader.range(of: "filename=\"") else { return nil }
        let rest = partHeader[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[rest.startIndex..<end])
    }

    private static func sanitize(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let cleaned = base.unicodeScalars.map { allowed.contains($0) ? String($0) : "" }.joined()
        return cleaned.isEmpty ? "upload.ipa" : cleaned
    }

    private static func tempURL(name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lc-upload-\(UUID().uuidString)-\(sanitize(name))")
        return url
    }
}
