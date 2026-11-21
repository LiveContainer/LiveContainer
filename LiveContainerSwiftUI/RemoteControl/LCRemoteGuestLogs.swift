//
//  LCRemoteGuestLogs.swift
//  LiveContainerSwiftUI
//  Summary (EN): Captures guest app / injected tweak stdout-stderr into per-pid log files and serves them incrementally.
//
//  Log access for the guest app and any injected tweak.
//  LiveProcess redirects stdout/stderr at startup into
//  <appGroup>/LiveContainer/RemoteControl/guest-logs/<app>_<pid>.log (see LiveProcess/main.m);
//  this file only lists them, reads incrementally by byte offset, and clears them.
//
//  Note: only stderr/stdout (NSLog, printf, Swift print) is covered. Logs written via os_log()
//  go to the unified logging system and are not visible here.
//

import Foundation

enum LCRemoteGuestLogs {

    static var logsDirectory: URL {
        LCPath.lcGroupDocPath
            .appendingPathComponent("RemoteControl")
            .appendingPathComponent("guest-logs")
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    private static func sanitize(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return String(base.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined())
    }

    private static func fileURL(_ name: String) -> URL {
        logsDirectory.appendingPathComponent(sanitize(name))
    }

    // MARK: - Listing

    static func list() -> [[String: Any]] {
        ensureDirectory()
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: logsDirectory.path)) ?? []
        var out: [[String: Any]] = []
        for name in names.sorted() {
            let url = logsDirectory.appendingPathComponent(name)
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let base = name.replacingOccurrences(of: ".log", with: "")
            let parts = base.split(separator: "_")
            let pidPart = parts.last.map(String.init) ?? ""
            out.append([
                "name": name,
                "app": parts.dropLast().joined(separator: "_"),
                "pid": Int(pidPart) ?? 0,
                "size": size,
                "mtime": mtime,
                "running": isPidAlive(Int(pidPart) ?? 0)
            ])
        }
        return out
    }

    private static func isPidAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    // MARK: - Incremental read

    /// - offset: start at this byte position (0 = beginning); the reply carries `next` for the following call
    static func read(name: String, offset: Int = 0, limitBytes: Int = 64 * 1024) -> [String: Any]? {
        let url = fileURL(name)
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let start = UInt64(max(0, min(offset, Int(size))))
        try? fh.seek(toOffset: start)
        let data = (try? fh.read(upToCount: limitBytes)) ?? Data()
        let next = Int(start) + data.count
        return [
            "name": sanitize(name),
            "offset": Int(start),
            "next": next,
            "size": Int(size),
            "eof": next >= Int(size),
            "text": String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        ]
    }

    // MARK: - Cleanup

    @discardableResult
    static func clear(name: String?) -> Int {
        ensureDirectory()
        let fm = FileManager.default
        if let name {
            try? fm.removeItem(at: fileURL(name))
            return 1
        }
        let names = (try? fm.contentsOfDirectory(atPath: logsDirectory.path)) ?? []
        var removed = 0
        for n in names {
            try? fm.removeItem(at: logsDirectory.appendingPathComponent(n))
            removed += 1
        }
        return removed
    }
}
