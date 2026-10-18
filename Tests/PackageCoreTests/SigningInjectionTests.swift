import Foundation
import XCTest
@testable import PackageCore

final class SigningInjectionTests: XCTestCase {
    private func executable(padding: Int = 1024, encrypted: Bool = false) -> Data {
        var data = Data(repeating: 0, count: 2048)
        func word(_ offset: Int, _ value: UInt32) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.replaceSubrange(offset..<offset+4, with: $0) }
        }
        word(0, 0xfeedfacf); word(4, 0x0100000c); word(12, 2)
        word(16, encrypted ? 3 : 2); word(20, encrypted ? 200 : 176)
        word(32, 0x19); word(36, 152); word(96, 1)
        word(32 + 72 + 48, UInt32(padding))
        word(184, 0x32); word(188, 24); word(192, 2)
        if encrypted { word(208, 0x2c); word(212, 24); word(224, 1) }
        for offset in padding..<data.count { data[offset] = UInt8(offset % 251) }
        return data
    }
    func testInjectionPreservesCodeAndCanBeRemovedIdempotently() throws {
        let original = executable()
        let injected = try SigningMachO.inject(original, libraries: ["Probe.dylib"])
        XCTAssertEqual(injected[1024...], original[1024...])
        XCTAssertNotNil(injected.range(of: Data((SigningMachO.libraryPrefix + "Probe.dylib").utf8)))
        XCTAssertEqual(try SigningMachO.inject(injected, libraries: ["Probe.dylib"]), injected)
        XCTAssertEqual(try SigningMachO.inject(injected, libraries: []), original)
    }
    func testRejectsEncryptionInsufficientPaddingAndTraversal() {
        XCTAssertThrowsError(try SigningMachO.inject(executable(encrypted: true), libraries: ["Probe.dylib"]))
        XCTAssertThrowsError(try SigningMachO.inject(executable(padding: 208), libraries: ["Probe.dylib"]))
        XCTAssertThrowsError(try SigningMachO.inject(executable(), libraries: ["../Probe.dylib"]))
    }
    func testCorruptPayloadCannotChangeAppAndDisableRestoresCode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Target.app"), presets = root.appendingPathComponent("Presets")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let original = executable()
        try original.write(to: app.appendingPathComponent("Main"))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Main"], format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
        let identifier = "org.example.target"
        let payload = SigningInjectionPreset.directory(identifier, root: presets)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        let bytes = Data("controlled payload".utf8)
        try bytes.write(to: payload.appendingPathComponent("Probe.dylib"))
        var preset = SigningInjectionPreset(bundleIdentifier: identifier,
            files: [.init(path: "Probe.dylib", sha256: "wrong")], libraries: ["Probe.dylib"], packageNames: ["Probe"])
        try preset.write(to: presets)
        XCTAssertThrowsError(try SigningInjectionApply.prepare(app: app, identifier: identifier, root: presets))
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("Main")), original)
        preset.files[0].sha256 = PackageSHA256.hex(bytes); try preset.write(to: presets)
        try SigningInjectionApply.prepare(app: app, identifier: identifier, root: presets)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Frameworks/LCOSInjected/Probe.dylib").path))
        preset.enabled = false; try preset.write(to: presets)
        try SigningInjectionApply.prepare(app: app, identifier: identifier, root: presets)
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("Main")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Frameworks/LCOSInjected").path))
    }
    func testActualDeviceExecutableInjection() throws {
        guard let path = ProcessInfo.processInfo.environment["LCOS_DEVICE_PROBE_DIR"] else { throw XCTSkip("Requires the Xcode-built device probe") }
        let url = URL(fileURLWithPath: path).appendingPathComponent("Payload/LCOSProbe.app/LCOSProbe")
        let original = try Data(contentsOf: url)
        let changed = try SigningMachO.inject(original, libraries: ["LCOSProbe.dylib"])
        XCTAssertNotEqual(changed, original)
        XCTAssertEqual(try SigningMachO.inject(changed, libraries: []), original)
    }
}
