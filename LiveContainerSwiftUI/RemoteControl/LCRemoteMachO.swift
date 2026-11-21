//
//  LCRemoteMachO.swift
//  LiveContainerSwiftUI
//  Summary (EN): Static Mach-O inspection (headers, load commands, code signature) used by the remote API.
//
//  Why: tweak debugging usually starts with "does this dylib even link the right things, and is it
//  actually signed?". Reading that from the device avoids copying binaries back to a PC.
//
//  Everything here is read-only and stdlib-free (Foundation only): filenames, load commands and the
//  embedded code-signature superblob are parsed straight from the file.
//

import Foundation
import CryptoKit

enum LCRemoteMachO {

    /// Same 64-bit little-endian guard the tweak manager uses; big-endian and 32-bit slices are reported as-is.
    private static let maxLoadCommandBytes = 8 * 1024 * 1024

    static func inspect(path: String) -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        var out: [String: Any] = ["path": url.path, "exists": fm.fileExists(atPath: url.path)]
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return out }
        out["size"] = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if let mode = attrs[.posixPermissions] as? NSNumber {
            out["mode"] = String(format: "%04o", mode.intValue & 0o7777)
        }
        if let mtime = attrs[.modificationDate] as? Date {
            out["modified"] = ISO8601DateFormatter().string(from: mtime)
        }
        out["kind"] = (attrs[.type] as? FileAttributeType) == .typeDirectory ? "directory" : "file"
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return out }

        let thin = parseSlice(data, sliceOffset: 0)
        if let slices = fatSlices(data) {
            out["fat"] = true
            out["slices"] = slices.map { slice -> [String: Any] in
                var parsed = parseSlice(data, sliceOffset: slice.offset, sliceLimit: slice.size)
                parsed["offset"] = slice.offset
                parsed["size"] = slice.size
                return parsed
            }
        } else {
            out["fat"] = false
            out["slices"] = [thin]
        }
        return out
    }

    // MARK: - Fat container

    private static func fatSlices(_ data: Data) -> [(offset: Int, size: Int)]? {
        guard data.count >= 8 else { return nil }
        let magicBE = be32(data, 0)
        guard magicBE == 0xCAFEBABE || magicBE == 0xCAFEBABF else { return nil }
        let is64 = magicBE == 0xCAFEBABF
        let count = Int(be32(data, 4))
        guard count > 0, count < 32 else { return nil }
        let entrySize = is64 ? 32 : 20
        var out: [(Int, Int)] = []
        for i in 0..<count {
            let base = 8 + i * entrySize
            guard base + entrySize <= data.count else { break }
            let offset = is64 ? Int(be64(data, base + 8)) : Int(be32(data, base + 8))
            let size = is64 ? Int(be64(data, base + 16)) : Int(be32(data, base + 12))
            guard offset > 0, size > 0, offset + size <= data.count else { continue }
            out.append((offset, size))
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - One thin slice

    private static func parseSlice(_ data: Data, sliceOffset: Int, sliceLimit: Int? = nil) -> [String: Any] {
        let end = min(data.count, sliceOffset + (sliceLimit ?? data.count))
        guard sliceOffset + 32 <= end else { return ["error": "truncated header"] }
        let magic = le32(data, sliceOffset)
        // 0xFEEDFACF = MH_MAGIC_64, 0xFEEDFACE = MH_MAGIC (32-bit)
        let is64 = magic == 0xFEEDFACF
        guard magic == 0xFEEDFACF || magic == 0xFEEDFACE else {
            return ["error": String(format: "not a Mach-O header (magic 0x%08x)", magic)]
        }
        let headerSize = is64 ? 32 : 28
        let cpuType = le32(data, sliceOffset + 4)
        let cpuSubtype = le32(data, sliceOffset + 8)
        let fileType = le32(data, sliceOffset + 12)
        let ncmds = Int(le32(data, sliceOffset + 16))
        let sizeofcmds = Int(le32(data, sliceOffset + 20))
        let flags = le32(data, sliceOffset + (is64 ? 24 : 24))

        var out: [String: Any] = [
            "magic64": is64,
            "cpu": cpuName(cpuType, cpuSubtype),
            "cpuType": String(format: "0x%x", cpuType),
            "fileType": fileTypeName(fileType),
            "flags": String(format: "0x%x", flags),
            "pie": (flags & 0x200000) != 0,          // MH_PIE
            "ncmds": ncmds
        ]

        let cmdsStart = sliceOffset + headerSize
        let cmdsEnd = min(end, cmdsStart + min(sizeofcmds, maxLoadCommandBytes))
        guard cmdsEnd > cmdsStart else { return out }

        var dylibs: [String] = []
        var weakDylibs: [String] = []
        var rpaths: [String] = []
        var idDylib = ""
        var hasPageZero = false
        var cryptid = 0
        var signatureOffset: (Int, Int)?
        var offset = cmdsStart
        var seen = 0

        while offset + 8 <= cmdsEnd && seen < ncmds {
            let cmd = le32(data, offset)
            let cmdsize = Int(le32(data, offset + 4))
            guard cmdsize >= 8, offset + cmdsize <= cmdsEnd else { break }
            switch cmd {
            case 0x19 where !is64, 0x1 where is64:            // LC_SEGMENT / LC_SEGMENT_64
                let segNameOffset = offset + 8
                if let segName = readCString(data, at: segNameOffset, limit: 16), segName == "__PAGEZERO" {
                    hasPageZero = true
                }
            case 0xC:                                          // LC_LOAD_DYLIB
                if let s = readCString(data, at: nameOffset(data, offset, is64: is64), limit: cmdsize) { dylibs.append(s) }
            case 0x8000001F:                                   // LC_LOAD_WEAK_DYLIB
                if let s = readCString(data, at: nameOffset(data, offset, is64: is64), limit: cmdsize) { weakDylibs.append(s) }
            case 0xD:                                          // LC_ID_DYLIB
                if let s = readCString(data, at: nameOffset(data, offset, is64: is64), limit: cmdsize) { idDylib = s }
            case 0x8000001C:                                   // LC_RPATH
                if let s = readCString(data, at: nameOffset(data, offset, is64: is64), limit: cmdsize) { rpaths.append(s) }
            case 0x21:                                         // LC_ENCRYPTION_INFO
                cryptid = Int(le32(data, offset + 16))
            case 0x2C:                                         // LC_ENCRYPTION_INFO_64
                cryptid = Int(le32(data, offset + 16))
            case 0x1D:                                         // LC_CODE_SIGNATURE
                let dataoff = Int(le32(data, offset + 8))
                let datasize = Int(le32(data, offset + 12))
                signatureOffset = (sliceOffset + dataoff, datasize)
            default:
                break
            }
            offset += cmdsize
            seen += 1
        }

        out["pageZero"] = hasPageZero
        out["dylibs"] = dylibs
        out["weakDylibs"] = weakDylibs
        out["rpaths"] = rpaths
        if !idDylib.isEmpty { out["idDylib"] = idDylib }
        out["encrypted"] = cryptid != 0
        out["tweakLoaderLinked"] = dylibs.contains { $0.contains("TweakLoader") }
        out["isDylib"] = fileType == 6                            // MH_DYLIB
        out["codeSignature"] = codeSignature(data, at: signatureOffset)
        return out
    }

    private static func nameOffset(_ data: Data, _ cmdOffset: Int, is64: Bool) -> Int {
        // dylib_command / rpath_command: cmd(4) cmdsize(4) name.offset(4) ...
        let rel = Int(le32(data, cmdOffset + 8))
        return cmdOffset + rel
    }

    // MARK: - Code signature

    private static func codeSignature(_ data: Data, at range: (Int, Int)?) -> [String: Any] {
        guard let (start, size) = range, size > 20, start + size <= data.count else {
            return ["present": false]
        }
        let blob = data.subdata(in: start..<(start + size))
        var out: [String: Any] = ["present": true, "size": size]
        guard be32(blob, 0) == 0xFADE0CC0 else {          // CSMAGIC_EMBEDDED_SIGNATURE
            out["error"] = "unexpected superblob magic"
            return out
        }
        let count = Int(be32(blob, 8))
        var hasCMSSignature = false
        var cdhash = ""
        for i in 0..<max(0, min(count, 32)) {
            let slot = Int(be32(blob, 12 + i * 8))
            let off = Int(be32(blob, 12 + i * 8 + 4))
            guard off + 8 <= blob.count else { continue }
            if slot == 0x10000 { hasCMSSignature = true }   // CSSLOT_SIGNATURESLOT (CMS)
            guard be32(blob, off) == 0xFADE0C02 else { continue }   // CSMAGIC_CODEDIRECTORY
            let cdLen = Int(be32(blob, off + 4))
            guard cdLen > 0, off + cdLen <= blob.count else { continue }
            let cd = blob.subdata(in: off..<(off + cdLen))
            cdhash = SHA256.hash(data: cd).prefix(8).map { String(format: "%02x", $0) }.joined()
            let cdFlags = be32(blob, off + 12)                          // flags
            out["flags"] = String(format: "0x%x", cdFlags)
            out["adhoc"] = (cdFlags & 0x2) != 0
            out["hashType"] = hashTypeName(be32(blob, off + 36)) ?? "unknown"
            if let ident = readCString(blob, at: off + Int(be32(blob, off + 20)), limit: 512) {
                out["identifier"] = ident
            }
            if let team = readCString(blob, at: off + Int(be32(blob, off + 48)), limit: 512) {
                out["teamId"] = team
            }
            break
        }
        out["cdhash"] = cdhash
        out["cmsSigned"] = hasCMSSignature
        out["valid"] = !cdhash.isEmpty
        return out
    }

    private static func hashTypeName(_ type: UInt32) -> String? {
        switch type {
        case 1: return "sha1"
        case 2: return "sha256"
        case 3: return "sha256-truncated"
        case 4: return "sha384"
        default: return nil
        }
    }

    // MARK: - Names

    private static func cpuName(_ type: UInt32, _ subtype: UInt32) -> String {
        switch type {
        case 0x0100000C: return subtype & 0x02 != 0 ? "arm64e" : "arm64"
        case 0x01000007: return "x86_64"
        case 0x7: return "i386"
        case 0xC: return "arm"
        default: return String(format: "cpu 0x%x/0x%x", type, subtype)
        }
    }

    private static func fileTypeName(_ type: UInt32) -> String {
        switch type {
        case 1: return "MH_OBJECT"
        case 2: return "MH_EXECUTE"
        case 3: return "MH_FVMLIB"
        case 4: return "MH_CORE"
        case 5: return "MH_PRELOAD"
        case 6: return "MH_DYLIB"
        case 7: return "MH_DYLINKER"
        case 8: return "MH_BUNDLE"
        case 9: return "MH_DYLIB_STUB"
        case 10: return "MH_DSYM"
        case 11: return "MH_KEXT_BUNDLE"
        default: return String(format: "filetype %u", type)
        }
    }

    // MARK: - Primitive readers

    private static func readCString(_ data: Data, at offset: Int, limit: Int) -> String? {
        guard offset > 0, offset < data.count else { return nil }
        let end = min(data.count, offset + max(1, limit))
        var bytes: [UInt8] = []
        var i = offset
        while i < end {
            let b = data[i]
            if b == 0 { break }
            bytes.append(b)
            i += 1
        }
        return bytes.isEmpty ? nil : String(bytes: bytes, encoding: .utf8)
    }

    private static func le32(_ d: Data, _ o: Int) -> UInt32 {
        guard o + 4 <= d.count else { return 0 }
        return UInt32(d[o]) | UInt32(d[o + 1]) << 8 | UInt32(d[o + 2]) << 16 | UInt32(d[o + 3]) << 24
    }

    private static func be32(_ d: Data, _ o: Int) -> UInt32 {
        guard o + 4 <= d.count else { return 0 }
        return UInt32(d[o]) << 24 | UInt32(d[o + 1]) << 16 | UInt32(d[o + 2]) << 8 | UInt32(d[o + 3])
    }

    private static func be64(_ d: Data, _ o: Int) -> UInt64 {
        guard o + 8 <= d.count else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 { v = v << 8 | UInt64(d[o + i]) }
        return v
    }
}
