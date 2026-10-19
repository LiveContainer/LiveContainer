import Foundation

@_silgen_name("LCOSTestGuestJITRouting")
func testGuestJITRouting()

@main
enum SigningBridgeTest {
    static func main() async throws {
        testGuestJITRouting()
        try await LCOSSigningInjectionUI.configure(identifier: "org.example.probe", appName: "Controlled probe", presenter: NSObject())
        do {
            try await LCOSSigningInjectionUI.configure(identifier: "org.example.cancel", appName: "Controlled probe", presenter: NSObject())
            throw SigningInjectionFailure.invalid("Install cancellation was ignored")
        } catch is CancellationError { }
        let manager = FileManager.default
        let probe = URL(fileURLWithPath: CommandLine.arguments[1])
        let group = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LCOS_TEST_GROUP"]!)
        let app = group.appendingPathComponent("Target.app")
        try manager.createDirectory(at: group, withIntermediateDirectories: true)
        try manager.copyItem(at: probe.appendingPathComponent("Payload/LCOSProbe.app"), to: app)
        let executable = app.appendingPathComponent("LCOSProbe")
        let original = try Data(contentsOf: executable)
        let root = group.appendingPathComponent("LiveContainer/SigningInjection")
        let identifier = "org.example.lcosguest"
        let payload = SigningInjectionPreset.directory(identifier, root: root)
        try manager.createDirectory(at: payload, withIntermediateDirectories: true)
        let library = try Data(contentsOf: probe.appendingPathComponent("LCOSProbe.dylib"))
        try library.write(to: payload.appendingPathComponent("LCOSProbe.dylib"))
        var preset = SigningInjectionPreset(bundleIdentifier: identifier,
            files: [.init(path: "LCOSProbe.dylib", sha256: PackageSHA256.hex(library))],
            libraries: ["LCOSProbe.dylib"], packageNames: ["Controlled probe"])
        try preset.write(to: root)
        try LCOSSigningInjection.prepare(at: app, bundleIdentifier: identifier)
        let injected = try Data(contentsOf: executable)
        guard injected != original,
              injected.range(of: Data((SigningMachO.libraryPrefix + "LCOSProbe.dylib").utf8)) != nil else {
            throw SigningInjectionFailure.invalid("Bridge did not apply the shared preset")
        }
        preset.enabled = false
        try preset.write(to: root)
        try LCOSSigningInjection.prepare(at: app, bundleIdentifier: identifier)
        guard try Data(contentsOf: executable) == original else {
            throw SigningInjectionFailure.invalid("Bridge did not remove disabled injection")
        }
        preset.enabled = true
        try preset.write(to: root)
        try LCOSSigningInjection.prepare(at: app, bundleIdentifier: identifier)
        let embedded = app.appendingPathComponent("Frameworks/LCOSInjected/LCOSProbe.dylib")
        for arguments in [["--force", "--sign", "-", "--timestamp=none", embedded.path],
                          ["--force", "--sign", "-", "--timestamp=none", app.path],
                          ["--verify", "--deep", "--strict", app.path]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw SigningInjectionFailure.invalid("Signing bridge signature verification failed")
            }
        }
        let evidence = ["shared_group_bridge": true, "install_ui_bridge": true, "install_cancel": true, "guest_jit_routing": true, "injection": true, "disable_restores_binary": true,
                        "adhoc_signature_verified": true, "physical_device_tested": false]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: group.deletingLastPathComponent().appendingPathComponent("signing-bridge-evidence.json"))
        print("Signing bridge: shared preset, injection, removal and code signature verified")
    }
}
