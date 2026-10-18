import Foundation
#if canImport(LCArchiveBridge)
import LCArchiveBridge
#endif

enum PackageFailure: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let reason) = self { return reason }; return nil }
}

struct PackageLimits {
    var archiveBytes = 64 * 1024 * 1024
    var expandedBytes = 128 * 1024 * 1024
    var fileBytes = 32 * 1024 * 1024
    var fileCount = 4096
}

struct DebianControl: Codable {
    let fields: [String: String]
    subscript(_ key: String) -> String { fields[key.lowercased()] ?? "" }
    init(_ data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PackageFailure.invalid("Control metadata is not UTF-8")
        }
        var fields: [String: String] = [:]
        var current: String?
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if line.isEmpty { current = nil; continue }
            if line.first == " " || line.first == "\t" {
                guard let key = current else { throw PackageFailure.invalid("Orphan control continuation") }
                fields[key, default: ""] += "\n" + line.dropFirst()
            } else {
                guard let colon = line.firstIndex(of: ":") else { throw PackageFailure.invalid("Invalid control field") }
                let key = String(line[..<colon]).lowercased()
                guard !key.isEmpty, fields[key] == nil else { throw PackageFailure.invalid("Duplicate control field: \(key)") }
                fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                current = key
            }
        }
        for key in ["package", "version", "architecture"] where fields[key, default: ""].isEmpty {
            throw PackageFailure.invalid("Missing control field: \(key)")
        }
        let identifier = fields["package"]!
        guard identifier.range(of: "^[a-z0-9][a-z0-9+.-]+$", options: .regularExpression) != nil else {
            throw PackageFailure.invalid("Invalid Debian package identifier")
        }
        self.fields = fields
    }
}

struct DebianPackage {
    let control: DebianControl
    let files: [String: Data]
    let scripts: [String]
    let layout: String

    static func safePath(_ raw: String) throws -> String {
        var path = raw
        while path.hasPrefix("./") { path.removeFirst(2) }
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("\0"),
              path.utf8.count < 1024,
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw PackageFailure.invalid("Unsafe archive path: \(raw)")
        }
        return path.split(separator: "/").filter { $0 != "." }.joined(separator: "/")
    }

    init(data: Data, limits: PackageLimits = PackageLimits()) throws {
        guard data.count <= limits.archiveBytes, data.starts(with: Data("!<arch>\n".utf8)) else {
            throw PackageFailure.invalid("Invalid or oversized Debian ar archive")
        }
        var members: [String: Data] = [:]
        var offset = 8
        while offset < data.count {
            guard data.count - offset >= 60,
                  data.subdata(in: offset+58..<offset+60) == Data("`\n".utf8),
                  let rawName = String(data: data.subdata(in: offset..<offset+16), encoding: .ascii),
                  let rawSize = String(data: data.subdata(in: offset+48..<offset+58), encoding: .ascii),
                  let size = Int(rawSize.trimmingCharacters(in: .whitespaces)), size >= 0,
                  size <= data.count - offset - 60 else { throw PackageFailure.invalid("Damaged ar member") }
            let name = rawName.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard members[name] == nil, members.count < 8 else { throw PackageFailure.invalid("Duplicate or excessive ar members") }
            members[name] = data.subdata(in: offset+60..<offset+60+size)
            offset += 60 + size
            if size % 2 != 0 {
                guard offset < data.count, data[offset] == 10 else { throw PackageFailure.invalid("Invalid ar padding") }
                offset += 1
            }
        }
        guard members["debian-binary"] == Data("2.0\n".utf8) else { throw PackageFailure.invalid("Unsupported Debian format version") }
        let suffixes = ["", ".gz", ".xz", ".zst"]
        func member(_ prefix: String) throws -> Data {
            let names = members.keys.filter { $0.hasPrefix(prefix + ".tar") }
            guard names.count == 1, let name = names.first, suffixes.contains(String(name.dropFirst((prefix + ".tar").count))) else {
                throw PackageFailure.invalid("Missing, ambiguous or unsupported \(prefix).tar compression (supported: tar, gzip, xz, zstd if available)")
            }
            return members[name]!
        }
        guard members.count == 3 else { throw PackageFailure.invalid("Unexpected Debian archive members") }
        let controls = try Self.readTar(member("control"), limits: limits)
        guard let controlData = controls["control"] else { throw PackageFailure.invalid("Missing control metadata") }
        control = try DebianControl(controlData)
        scripts = ["preinst", "postinst", "prerm", "postrm", "config", "triggers"].filter { controls[$0] != nil }
        files = try Self.readTar(member("data"), limits: limits)
        let rootless = files.keys.contains { $0.hasPrefix("var/jb/") }
        let rootful = files.keys.contains { $0.hasPrefix("Library/") || $0.hasPrefix("usr/") || $0.hasPrefix("etc/") }
        layout = rootless && rootful ? "mixed" : rootless ? "rootless" : rootful ? "rootful" : "unknown"
    }

    private static func readTar(_ data: Data, limits: PackageLimits) throws -> [String: Data] {
        try data.withUnsafeBytes { buffer in
            guard let reader = lc_archive_open(buffer.baseAddress, buffer.count) else { throw PackageFailure.invalid("Unable to allocate archive reader") }
            defer { lc_archive_close(reader) }
            var files: [String: Data] = [:]
            var seen = Set<String>()
            var total = 0
            while true {
                var pathPointer: UnsafePointer<CChar>?
                var size: Int64 = 0
                var directory: Int32 = 0
                let status = lc_archive_next(reader, &pathPointer, &size, &directory)
                if status == 0 { break }
                guard status == 1, let pathPointer else { throw PackageFailure.invalid(String(cString: lc_archive_error(reader))) }
                let path = try safePath(String(cString: pathPointer))
                if path.isEmpty && directory == 1 { continue }
                guard !path.isEmpty, seen.insert(path.lowercased()).inserted, seen.count <= limits.fileCount,
                      size >= 0, size <= limits.fileBytes, size <= limits.expandedBytes - total else {
                    throw PackageFailure.invalid("Duplicate path or archive extraction limit exceeded")
                }
                total += Int(size)
                if directory == 1 { continue }
                var contents = Data(count: Int(size))
                try contents.withUnsafeMutableBytes { bytes in
                    var read = 0
                    while read < bytes.count {
                        let n = lc_archive_read(reader, bytes.baseAddress!.advanced(by: read), bytes.count - read)
                        guard n > 0 else { throw PackageFailure.invalid("Truncated tar entry: \(path)") }
                        read += Int(n)
                    }
                }
                var extra: UInt8 = 0
                guard lc_archive_read(reader, &extra, 1) == 0 else { throw PackageFailure.invalid("Tar entry exceeds declared size") }
                files[path] = contents
            }
            return files
        }
    }
}
