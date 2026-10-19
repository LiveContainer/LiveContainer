import Foundation
import XCTest
@testable import PackageCore

final class GuestJITSupportTests: XCTestCase {
    func testBundledHuskScriptIsBoundedAndDoesNotSelectUnrelatedApps() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let script = app.appendingPathComponent("husk-jit.js")
        try Data("controlled script".utf8).write(to: script)
        XCTAssertEqual(try GuestJITSupport.bundledScript(in: app, bundleIdentifier: "com.husk.app"), Data("controlled script".utf8))
        XCTAssertNil(try GuestJITSupport.bundledScript(in: app, bundleIdentifier: "com.other.app"))
        try Data(repeating: 65, count: 256 * 1024 + 1).write(to: script)
        XCTAssertThrowsError(try GuestJITSupport.bundledScript(in: app, bundleIdentifier: "com.husk.app"))
        try FileManager.default.removeItem(at: script)
        let outside = root.appendingPathComponent("outside.js")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: script, withDestinationURL: outside)
        XCTAssertThrowsError(try GuestJITSupport.bundledScript(in: app, bundleIdentifier: "com.husk.app"))
    }
}
