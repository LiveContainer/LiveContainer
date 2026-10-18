import Foundation

enum SigningInjectionFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

/// Edits only owned load commands in existing zero-filled header padding. Never shifts signed code.
enum SigningMachO {
    static let libraryPrefix = "@executable_path/Frameworks/LCOSInjected/"
    static let searchPath = "@executable_path/Frameworks/LCOSInjected"
    static func inject(_ input: Data, libraries: [String]) throws -> Data {
        guard libraries.count <= 64, libraries.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("..") && $0.hasSuffix(".dylib") }) else {
            throw SigningInjectionFailure.invalid("Invalid injection library names")
        }
        var result = input
        func read(_ offset: Int, big: Bool = false) throws -> UInt32 {
            guard offset >= 0, offset <= input.count - 4 else { throw SigningInjectionFailure.invalid("Truncated Mach-O") }
            let bytes = Array(input[offset..<offset+4])
            return big ? bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                : bytes.reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        let magic = try read(0)
        var slices: [(Int, Int)] = []
        if magic == 0xbebafeca {
            let count = Int(try read(4, big: true))
            guard (1...16).contains(count), 8 + count * 20 <= input.count else { throw SigningInjectionFailure.invalid("Invalid universal Mach-O") }
            for index in 0..<count {
                let entry = 8 + index * 20
                guard try read(entry, big: true) == 0x0100000c else { throw SigningInjectionFailure.invalid("Only ARM64 application slices are supported") }
                let start = Int(try read(entry + 8, big: true)), size = Int(try read(entry + 12, big: true))
                guard start >= 8 + count * 20, size >= 32, start <= input.count - size,
                      !slices.contains(where: { start < $0.0 + $0.1 && $0.0 < start + size }) else { throw SigningInjectionFailure.invalid("Invalid or overlapping slices") }
                slices.append((start, size))
            }
        } else { slices = [(0, input.count)] }
        for (base, size) in slices {
            guard size >= 32, try read(base) == 0xfeedfacf, try read(base + 4) == 0x0100000c,
                  try read(base + 12) == 2 else { throw SigningInjectionFailure.invalid("Expected an ARM64 executable") }
            let count = Int(try read(base + 16)), bytes = Int(try read(base + 20))
            guard count <= 4096, bytes <= size - 32 else { throw SigningInjectionFailure.invalid("Invalid executable load commands") }
            let end = base + 32 + bytes
            var cursor = base + 32, commands: [Data] = [], firstCode = base + size, platform = false
            for _ in 0..<count {
                let command = try read(cursor), length = Int(try read(cursor + 4))
                guard length >= 8, length % 8 == 0, cursor <= end - length else { throw SigningInjectionFailure.invalid("Malformed load command") }
                if command == 0x19 {
                    guard length >= 72 else { throw SigningInjectionFailure.invalid("Truncated segment") }
                    let sections = Int(try read(cursor + 64))
                    guard sections <= (length - 72) / 80 else { throw SigningInjectionFailure.invalid("Invalid section table") }
                    for section in 0..<sections {
                        let sectionBase = cursor + 72 + section * 80
                        let flags = try read(sectionBase + 64) & 0xff
                        let offset = Int(try read(sectionBase + 48))
                        if offset > 0, ![UInt32(1), 0xc, 0x12].contains(flags) { firstCode = min(firstCode, base + offset) }
                    }
                }
                if command == 0x2c || command == 0x21 {
                    guard length >= 20, try read(cursor + 16) == 0 else { throw SigningInjectionFailure.invalid("Encrypted applications cannot be injected") }
                }
                if command == 0x32 {
                    guard length >= 24, try read(cursor + 8) == 2 else { throw SigningInjectionFailure.invalid("Expected an iOS device executable") }
                    platform = true
                } else if command == 0x25 { platform = true }
                var owned = false
                if [UInt32(0xc), 0x80000018, 0x8000001c].contains(command) {
                    let offset = Int(try read(cursor + 8))
                    guard offset >= 12, offset < length else { throw SigningInjectionFailure.invalid("Invalid load path") }
                    let raw = input[(cursor+offset)..<(cursor+length)].prefix { $0 != 0 }
                    let path = String(decoding: raw, as: UTF8.self)
                    owned = path.hasPrefix(libraryPrefix) || (command == 0x8000001c && path == searchPath)
                }
                if !owned { commands.append(input.subdata(in: cursor..<cursor+length)) }
                cursor += length
            }
            guard cursor == end, platform, firstCode >= end, firstCode < base + size else { throw SigningInjectionFailure.invalid("Missing iOS platform or header padding") }
            func command(_ kind: UInt32, path: String, header: Int) -> Data {
                let pathBytes = Data(path.utf8) + Data([0])
                let length = (header + pathBytes.count + 7) & ~7
                var words = [kind, UInt32(length), UInt32(header)]
                if header == 24 { words += [0, 0, 0] }
                var data = words.reduce(into: Data()) { result, word in var value = word.littleEndian; withUnsafeBytes(of: &value) { result.append(contentsOf: $0) } }
                data.append(pathBytes); data.append(Data(repeating: 0, count: length - data.count)); return data
            }
            if !libraries.isEmpty {
                commands.append(command(0x8000001c, path: searchPath, header: 12))
                for name in Set(libraries).sorted() { commands.append(command(0xc, path: libraryPrefix + name, header: 24)) }
            }
            let replacement = commands.reduce(into: Data()) { $0.append($1) }
            guard replacement.count <= firstCode - base - 32,
                  input[end..<max(end, base + 32 + replacement.count)].allSatisfy({ $0 == 0 }) else {
                throw SigningInjectionFailure.invalid("Application has insufficient header padding for injection")
            }
            let clearEnd = max(end, base + 32 + replacement.count)
            result.replaceSubrange((base+32)..<clearEnd, with: replacement + Data(repeating: 0, count: clearEnd - base - 32 - replacement.count))
            for (offset, value) in [(base + 16, UInt32(commands.count)), (base + 20, UInt32(replacement.count))] {
                var value = value.littleEndian
                withUnsafeBytes(of: &value) { result.replaceSubrange(offset..<offset+4, with: $0) }
            }
        }
        return result
    }
}
