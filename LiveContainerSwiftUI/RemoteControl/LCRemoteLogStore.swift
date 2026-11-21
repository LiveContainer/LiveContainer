//
//  LCRemoteLogStore.swift
//  LiveContainerSwiftUI
//  Summary (EN): In-process log ring buffer with sequence numbers so clients can poll incrementally.
//
//  Log capture and ring buffer:
//   - process stdout / stderr are redirected onto one pipe via dup2 (NSLog, Swift print and
//     same-process guest output all land here)
//   - lines are split and appended to a ring buffer that the HTTP API polls incrementally
//   - seq increases monotonically; clients use ?since=<seq> to fetch deltas
//

import Foundation
import os

struct LCRemoteLogEntry {
    let seq: Int
    let ts: TimeInterval
    let src: String
    let msg: String

    var json: [String: Any] {
        ["seq": seq, "ts": ts, "src": src, "msg": msg]
    }
}

final class LCRemoteLogStore {
    static let shared = LCRemoteLogStore()

    private let queue = DispatchQueue(label: "lc.remote.log")
    private let capacity = 5000
    private var entries: [LCRemoteLogEntry] = []
    private var nextSeq = 1
    private var installed = false
    private var readFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var pending = Data()
    private let maxPendingBytes = 32 * 1024

    private init() {}

    // MARK: - Capture

    /// Idempotent; repeated calls install the capture only once.
    func installCapture() {
        queue.sync {
            guard !installed else { return }
            installed = true

            var fds: [Int32] = [0, 0]
            guard pipe(&fds) == 0 else {
                installed = false
                return
            }
            // Unbuffered, otherwise NSLog / print lines only show up once the buffer fills.
            setvbuf(stdout, nil, _IONBF, 0)
            setvbuf(stderr, nil, _IONBF, 0)
            dup2(fds[1], STDOUT_FILENO)
            dup2(fds[1], STDERR_FILENO)
            close(fds[1])

            readFD = fds[0]
            let src = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: queue)
            src.setEventHandler { [weak self] in
                self?.drain()
            }
            src.setCancelHandler { [weak self] in
                guard let self, self.readFD >= 0 else { return }
                close(self.readFD)
                self.readFD = -1
            }
            source = src
            src.resume()

            appendLocked("remote control log capture installed", src: "api")
        }
    }

    private func drain() {
        var buf = [UInt8](repeating: 0, count: 8192)
        let n = read(readFD, &buf, buf.count)
        guard n > 0 else { return }
        pending.append(contentsOf: buf[0..<n])

        while let range = pending.range(of: Data([0x0A])) {
            let lineData = pending.subdata(in: pending.startIndex..<range.lowerBound)
            pending.removeSubrange(pending.startIndex..<range.upperBound)
            var text = String(data: lineData, encoding: .utf8) ?? ""
            if text.hasSuffix("\r") { text.removeLast() }
            appendLocked(text, src: "log")
        }
        if pending.count > maxPendingBytes {
            let text = String(data: pending, encoding: .utf8) ?? ""
            pending.removeAll()
            appendLocked(text, src: "log")
        }
    }

    // MARK: - Write / read

    func append(_ msg: String, src: String = "api") {
        queue.sync { appendLocked(msg, src: src) }
    }

    private func appendLocked(_ msg: String, src: String) {
        for line in msg.split(separator: "\n", omittingEmptySubsequences: true) {
            let entry = LCRemoteLogEntry(seq: nextSeq, ts: Date().timeIntervalSince1970,
                                         src: src, msg: String(line))
            nextSeq += 1
            entries.append(entry)
        }
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// Returns records with seq > since, at most `limit`; `latest` is the current maximum seq.
    func snapshot(since: Int, limit: Int) -> (items: [LCRemoteLogEntry], latest: Int) {
        queue.sync {
            let filtered = entries.filter { $0.seq > since }
            let slice = filtered.suffix(max(0, limit))
            return (Array(slice), nextSeq - 1)
        }
    }

    var latestSeq: Int {
        queue.sync { nextSeq - 1 }
    }
}
