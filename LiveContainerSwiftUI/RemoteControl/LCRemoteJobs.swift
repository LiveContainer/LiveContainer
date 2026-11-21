//
//  LCRemoteJobs.swift
//  LiveContainerSwiftUI
//
//  Async jobs, used for "let the device download an IPA and install it itself".
//  Streaming an 18 MB upload over one long request dies when the app is suspended; device-side download plus a pollable job is far more reliable.
//

import Foundation

final class LCRemoteJob {
    enum Status: String {
        case running, done, failed
    }

    let id: String
    let kind: String
    var status: Status = .running
    var message: String = ""
    var result: [String: Any]?
    var createdAt = Date()
    var updatedAt = Date()

    init(kind: String) {
        self.id = UUID().uuidString
        self.kind = kind
    }

    var json: [String: Any] {
        var d: [String: Any] = [
            "id": id,
            "kind": kind,
            "status": status.rawValue,
            "message": message,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        if let result { d["result"] = result }
        return d
    }
}

@MainActor
final class LCRemoteJobs {
    static let shared = LCRemoteJobs()

    private var jobs: [String: LCRemoteJob] = [:]
    private let capacity = 50

    private init() {}

    /// The default URLSession request timeout is 60 s, and an 18 MB IPA on a mobile network
    /// often times out ("request timed out" on device). Downloads get their own long-timeout session that can wait for connectivity.
    static let downloadSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 600
        cfg.timeoutIntervalForResource = 3600
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    func create(kind: String) -> LCRemoteJob {
        let job = LCRemoteJob(kind: kind)
        jobs[job.id] = job
        // Trim to the most recent 50 entries.
        if jobs.count > capacity {
            for key in jobs.keys.sorted(by: { (jobs[$0]?.createdAt ?? .distantPast) < (jobs[$1]?.createdAt ?? .distantPast) })
                .prefix(jobs.count - capacity) {
                jobs.removeValue(forKey: key)
            }
        }
        return job
    }

    func get(_ id: String) -> LCRemoteJob? { jobs[id] }

    func all() -> [LCRemoteJob] { jobs.values.sorted { $0.createdAt > $1.createdAt } }

    func finish(_ job: LCRemoteJob, result: [String: Any]? = nil, error: String? = nil) {
        job.updatedAt = Date()
        if let error {
            job.status = .failed
            job.message = error
        } else {
            job.status = .done
            job.result = result
            job.message = "ok"
        }
    }

    /// Device-side download + install; progress is written to job.message.
    func runInstall(_ job: LCRemoteJob, urlString: String, replaceExisting: Bool) async {
        job.message = "downloading \(urlString)"
        guard let url = URL(string: urlString) else {
            finish(job, error: "invalid URL")
            return
        }
        do {
            let (tmpURL, response) = try await LCRemoteJobs.downloadSession.download(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                finish(job, error: "download failed: HTTP \(http.statusCode)")
                return
            }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("lc-dl-\(UUID().uuidString).ipa")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmpURL, to: dest)
            job.message = "downloaded \(dest.lastPathComponent), installing"
            let info = try await LCAppInstaller.install(ipa: dest, replaceExisting: replaceExisting)
            try? FileManager.default.removeItem(at: dest)
            finish(job, result: ["bundleId": info.bundleIdentifier() ?? "",
                                 "name": info.displayName() ?? "",
                                 "version": info.version() ?? "",
                                 "relativePath": info.relativeBundlePath ?? ""])
        } catch {
            finish(job, error: error.localizedDescription)
        }
    }
}
