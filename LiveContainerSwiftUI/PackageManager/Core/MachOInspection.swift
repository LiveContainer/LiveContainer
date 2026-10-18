import Foundation

struct MachOInspection: Codable {
    let dependencies: [String]
    let rpaths: [String]
    let minimumOS: UInt32
    let hasSignature: Bool

    static func inspectAndAdapt(_ input: Data) throws -> (Data, MachOInspection) {
        var bytes = input
        func word(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset <= bytes.count - 4 else { throw PackageFailure.invalid("Truncated Mach-O") }
            return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
        }
        guard bytes.count >= 32, try word(0) == 0xfeedfacf, try word(4) == 0x0100000c,
              try word(8) & 0x00ffffff == 0, try word(12) == 6 else {
            throw PackageFailure.invalid("Requires a thin arm64 (not arm64e) MH_DYLIB; fat/other binaries require rebuilding")
        }
        let count = Int(try word(16)), size = Int(try word(20))
        guard size <= bytes.count - 32, count <= size / 8 else { throw PackageFailure.invalid("Invalid Mach-O command bounds") }
        var cursor = 32
        var dependencies: [String] = [], rpaths: [String] = []
        var minimumOS: UInt32 = 0
        var platformFound = false, signed = false
        let end = 32 + size
        for _ in 0..<count {
            guard cursor <= end - 8 else { throw PackageFailure.invalid("Truncated Mach-O command") }
            let command = try word(cursor), length = Int(try word(cursor + 4))
            guard length >= 8, length % 8 == 0, length <= end - cursor else { throw PackageFailure.invalid("Invalid Mach-O command length") }
            if [UInt32(0xc), 0x80000018, 0x8000001f, 0x80000023, 0x20, 0xd, 0x8000001c].contains(command) {
                let isRpath = command == 0x8000001c
                let minimum = isRpath ? 12 : 24
                guard length >= minimum else { throw PackageFailure.invalid("Short Mach-O string command") }
                let relative = Int(try word(cursor + 8))
                guard relative >= minimum, relative < length else { throw PackageFailure.invalid("Invalid Mach-O string offset") }
                let start = cursor + relative
                guard let zero = bytes[start..<cursor+length].firstIndex(of: 0),
                      let path = String(data: bytes[start..<zero], encoding: .utf8), !path.isEmpty else { throw PackageFailure.invalid("Unterminated Mach-O path") }
                if isRpath { rpaths.append(path) }
                else if command != 0xd {
                    let substrate = ["/usr/lib/libsubstrate.dylib", "/var/jb/usr/lib/libsubstrate.dylib",
                                     "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
                                     "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate"]
                    var replacement = path
                    if substrate.contains(path) {
                        replacement = "@rpath/CydiaSubstrate.framework/CydiaSubstrate"
                        guard replacement.utf8.count + 1 <= length - relative else {
                            throw PackageFailure.invalid("Insufficient load-command space to adapt substrate; rebuild from source")
                        }
                        bytes.replaceSubrange(start..<cursor+length, with: Array(replacement.utf8) + Array(repeating: 0, count: length-relative-replacement.utf8.count))
                    }
                    let system = (replacement.hasPrefix("/System/Library/Frameworks/") || replacement.hasPrefix("/System/Library/PrivateFrameworks/") || replacement.hasPrefix("/usr/lib/")) && !replacement.contains("..")
                    let allowedLibraries = ["libSystem.B.dylib", "libobjc.A.dylib", "libc++.1.dylib", "libc++abi.dylib", "libz.1.dylib", "libsqlite3.dylib", "libiconv.2.dylib"]
                    let knownSystem = system && (!replacement.hasPrefix("/usr/lib/") || allowedLibraries.contains(String(replacement.dropFirst(9))))
                    guard knownSystem || replacement == "@rpath/CydiaSubstrate.framework/CydiaSubstrate" else {
                        throw PackageFailure.invalid("Unresolved or unsupported library: \(path)")
                    }
                    dependencies.append(replacement)
                }
            } else if command == 0x32 {
                guard length >= 24, try word(cursor + 8) == 2 else { throw PackageFailure.invalid("Binary is not built for iOS devices") }
                minimumOS = try word(cursor + 12)
                platformFound = true
            } else if command == 0x25 {
                guard length >= 16 else { throw PackageFailure.invalid("Invalid minimum iOS command") }
                minimumOS = try word(cursor + 8)
                platformFound = true
            } else if [UInt32(0x24), 0x2f, 0x30].contains(command) {
                throw PackageFailure.invalid("Binary targets another Apple platform")
            } else if command == 0x1d {
                guard length >= 16 else { throw PackageFailure.invalid("Invalid code signature command") }
                let offset = Int(try word(cursor + 8)), count = Int(try word(cursor + 12))
                guard offset <= bytes.count, count <= bytes.count - offset else { throw PackageFailure.invalid("Code signature outside binary") }
                signed = true
            } else if command == 0x2c || command == 0x21 {
                guard length >= (command == 0x2c ? 24 : 20) else { throw PackageFailure.invalid("Truncated encryption command") }
                // The linker emits this command for unencrypted binaries too.
                guard try word(cursor + 16) == 0 else { throw PackageFailure.invalid("Encrypted dylibs are unsupported") }
                let offset = Int(try word(cursor + 8)), count = Int(try word(cursor + 12))
                guard offset <= bytes.count, count <= bytes.count - offset else { throw PackageFailure.invalid("Encryption range outside binary") }
            }
            cursor += length
        }
        guard cursor == end, platformFound else { throw PackageFailure.invalid("Missing device platform or inconsistent Mach-O commands") }
        // Runtime strings cannot be repaired by moving files. Reject known jailbreak resource accesses.
        for prefix in ["/var/jb/Library/", "/Library/Application Support/", "/Library/Preference", "/usr/libexec/"] {
            if bytes.range(of: Data(prefix.utf8)) != nil { throw PackageFailure.invalid("Runtime path requires source adaptation: \(prefix)") }
        }
        return (bytes, MachOInspection(dependencies: dependencies, rpaths: rpaths, minimumOS: minimumOS, hasSignature: signed))
    }
}
