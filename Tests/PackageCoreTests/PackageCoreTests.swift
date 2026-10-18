import Foundation
import XCTest
@testable import PackageCore

final class PackageCoreTests: XCTestCase {
    let target = "org.example.lcosguest"
    func data(_ name: String) throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "deb", subdirectory: "Fixtures")!)
    }
    func package(_ name: String, limits: PackageLimits = PackageLimits()) throws -> DebianPackage {
        try DebianPackage(data: data(name), limits: limits)
    }
    func plan(_ name: String) throws -> TweakInstallPlan {
        try TweakInstallPlan(package: package(name), targetBundle: target)
    }
    func testCommonCompression() throws {
        for name in ["valid-tar", "valid-gz", "valid-xz", "valid-zst"] {
            // Apple's libarchive may lack zstd. It must fail explicitly, never simulate import.
            do {
                let decoded = try package(name)
                XCTAssertEqual(decoded.files.count, 2)
            }
            catch {
                #if os(Linux)
                throw error
                #else
                guard name == "valid-zst", error.localizedDescription.contains("compression") else { throw error }
                #endif
            }
        }
    }
    func testMetadataContinuationAndUnknownFields() throws {
        let p = try package("valid-gz")
        XCTAssertEqual(p.control["description"], "Fixture\ncontinued")
        XCTAssertEqual(p.control["X-Unknown"], "preserved")
        XCTAssertThrowsError(try DebianControl(Data("Package: aa\nPackage: bb\n".utf8)))
    }
    func testRootlessAndRootfulProduceSameRuntime() throws {
        let a = try plan("valid-gz"), b = try plan("rootless")
        XCTAssertEqual(a.files, b.files)
        XCTAssertEqual(a.package.layout, "rootful")
        XCTAssertEqual(b.package.layout, "rootless")
    }
    func testUnsafeArchivesRejected() {
        for name in ["traversal", "absolute", "symlink", "hardlink", "duplicate", "case-collision", "missing-control", "corrupt"] {
            XCTAssertThrowsError(try package(name), name)
        }
    }
    func testUnsupportedTweakSemanticsRejected() {
        for name in ["mixed", "scripts", "dependency", "system", "wrong-cpu", "wrong-filter", "missing-library", "substrate-no-room"] {
            XCTAssertThrowsError(try plan(name), name)
        }
    }
    func testResourceLimits() {
        var limits = PackageLimits()
        limits.fileCount = 10
        XCTAssertThrowsError(try package("many-files", limits: limits))
        limits = PackageLimits(); limits.fileBytes = 10000
        XCTAssertThrowsError(try package("large-file", limits: limits))
        limits = PackageLimits(); limits.expandedBytes = 15000
        XCTAssertThrowsError(try package("large-file", limits: limits))
        limits = PackageLimits(); limits.archiveBytes = 20
        XCTAssertThrowsError(try package("valid-gz", limits: limits))
    }
    func testProtectedTargetsRejected() throws {
        for target in ["com.SideStore.SideStore", "com.kdt.livecontainer", "com.apple.springboard"] {
            XCTAssertThrowsError(try TweakInstallPlan(package: package("valid-gz"), targetBundle: target))
        }
    }
    func testBoundedSubstrateRewrite() throws {
        let p = try plan("substrate-room")
        XCTAssertEqual(p.binaries["Example.dylib"]?.dependencies, ["@rpath/CydiaSubstrate.framework/CydiaSubstrate"])
        let old = try package("substrate-room").files.values.first { $0.starts(with: [0xcf, 0xfa, 0xed, 0xfe]) }!
        XCTAssertEqual(p.files["Example.dylib"]?.count, old.count)
    }
    func testMalformedMachOHasNoUnsafeReads() throws {
        let binary = try plan("valid-gz").files["Example.dylib"]!
        for size in 0..<binary.count {
            XCTAssertThrowsError(try MachOInspection.inspectAndAdapt(Data(binary.prefix(size))), "length \(size)")
        }
        var corrupt = binary
        corrupt.replaceSubrange(20..<24, with: [0xff, 0xff, 0xff, 0x7f])
        XCTAssertThrowsError(try MachOInspection.inspectAndAdapt(corrupt))
    }
    func testSHA256Vectors() {
        XCTAssertEqual(PackageSHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(PackageSHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(PackageSHA256.hex(Data(repeating: 97, count: 1000000)), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
    func testUnencryptedMachOEncryptionCommand() throws {
        var binary = try plan("valid-gz").files["Example.dylib"]!
        binary.replaceSubrange(16..<20, with: [2, 0, 0, 0])
        binary.replaceSubrange(20..<24, with: [48, 0, 0, 0])
        binary.append(contentsOf: [0x2c,0,0,0, 24,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0])
        _ = try MachOInspection.inspectAndAdapt(binary)
        binary[binary.count - 8] = 1
        XCTAssertThrowsError(try MachOInspection.inspectAndAdapt(binary))
    }
    func testActualDeviceProbe() throws {
        guard let directory = ProcessInfo.processInfo.environment["LCOS_DEVICE_PROBE_DIR"] else {
            throw XCTSkip("Actual iOS probe is validated after SDK compilation in Actions")
        }
        for layout in ["rootful", "rootless"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("LCOSProbe-\(layout).deb")
            let p = try TweakInstallPlan(package: DebianPackage(data: Data(contentsOf: url)), targetBundle: target)
            XCTAssertEqual(p.package.layout, layout)
            XCTAssertNotNil(p.binaries["LCOSProbe.dylib"])
        }
    }
    func testAtomicInstallEnableAndRemove() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackageStore(root: root)
        let p = try plan("valid-gz")
        let receipt = try await store.install(p, targetBundle: target) { _ in /* Parser tests use a test signer, never production signing. */ }
        XCTAssertEqual(receipt.runtimeStatus, "not attempted")
        try await store.verify(receipt.id, enabled: true)
        try await store.setEnabled(receipt.id, enabled: false)
        let inventory = try await store.inventory()
        XCTAssertEqual(inventory.count, 1)
        XCTAssertFalse(inventory[0].1)
        try await store.setEnabled(receipt.id, enabled: true)
        try Data("unrelated guest data".utf8).write(to: root.appendingPathComponent("unrelated"))
        try await store.remove(receipt.id, enabled: true)
        let remaining = try await store.inventory()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("unrelated").path))
    }
    func testSignerFailureRollsBack() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackageStore(root: root)
        do {
            _ = try await store.install(plan("valid-gz"), targetBundle: target) { _ in throw PackageFailure.invalid("Signing failed") }
            XCTFail("Signer failure was swallowed")
        } catch { XCTAssertEqual(error.localizedDescription, "Signing failed") }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testTamperingPreventsEnable() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackageStore(root: root)
        let receipt = try await store.install(plan("valid-gz"), targetBundle: target) { _ in }
        try await store.setEnabled(receipt.id, enabled: false)
        let file = root.appendingPathComponent("lcos-\(receipt.id).disabled/Example.dylib")
        try Data("tampered".utf8).write(to: file)
        do { try await store.setEnabled(receipt.id, enabled: true); XCTFail("Tampering was ignored") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Integrity")) }
    }

    func testStorageSymlinkRejected() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let actual = parent.appendingPathComponent("actual")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: false)
        let link = parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)
        let store = PackageStore(root: link.appendingPathComponent("packages"))
        do { _ = try await store.install(plan("valid-gz"), targetBundle: target) { _ in }; XCTFail("Storage symlink was followed") }
        catch { XCTAssertTrue(error.localizedDescription.contains("symbolic link")) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: actual.path).isEmpty)
    }

    func testResigningRefreshesIntegrityReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackageStore(root: root)
        let receipt = try await store.install(plan("valid-gz"), targetBundle: target) { _ in }
        let binary = root.appendingPathComponent("lcos-\(receipt.id)/Example.dylib")
        var changed = try Data(contentsOf: binary)
        changed.append(contentsOf: [0, 1, 2, 3]) // Simulates bytes changed by the trusted signer.
        try changed.write(to: binary)
        try await store.recordResigned(receipt.id)
        try await store.verify(receipt.id, enabled: true)
    }
}
