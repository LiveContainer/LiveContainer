import Foundation
import XCTest
@testable import PackageCore

final class SigningBundleIdentifierTests: XCTestCase {
    func testCustomParentAndSignedSuffixPreserveDistinctExtensionIDs() throws {
        let map = try SigningBundleIdentifiers.extensionMap(originalParent: "ph.telegra.Telegraph",
            targetParent: "org.example.custom", signedParent: "org.example.custom.36J962CSYN",
            extensions: ["ph.telegra.Telegraph.Share", "ph.telegra.Telegraph.NotificationService"])
        XCTAssertEqual(map["org.example.custom.Share"], "org.example.custom.36J962CSYN.Share")
        XCTAssertEqual(map["org.example.custom.NotificationService"], "org.example.custom.36J962CSYN.NotificationService")
        XCTAssertThrowsError(try SigningBundleIdentifiers.extensionMap(originalParent: "org.app", targetParent: "org.app",
            signedParent: "org.app.TEAM", extensions: ["org.app"]))
        XCTAssertThrowsError(try SigningBundleIdentifiers.extensionMap(originalParent: "org.app", targetParent: "org.app",
            signedParent: "org.app.TEAM", extensions: ["org.application.Share"]))
    }

    func testActualPreparedBundleRejectsScreenshotFailureAndDuplicateExtensions() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        defer { try? FileManager.default.removeItem(at: app) }
        func write(_ bundle: URL, _ id: String) throws {
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
                .write(to: bundle.appendingPathComponent("Info.plist"))
        }
        let parent = "ph.telegra.Telegraph.36J962CSYN"
        let share = app.appendingPathComponent("PlugIns/Share.appex")
        try write(app, parent)
        try write(share, parent)
        XCTAssertThrowsError(try SigningBundleIdentifiers.validateBundle(at: app))
        try write(share, parent + ".Share")
        XCTAssertNoThrow(try SigningBundleIdentifiers.validateBundle(at: app))
        try write(app.appendingPathComponent("PlugIns/Other.appex"), parent + ".Share")
        XCTAssertThrowsError(try SigningBundleIdentifiers.validateBundle(at: app))
    }
}
