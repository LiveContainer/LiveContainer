import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let installedApps = [
    SourceAppInstalledApp(
        bundleIdentifier: "com.example.demo",
        version: "1.2.3",
        relativeBundlePath: "com.example.demo.app"
    )
]

let matchingState = SourceAppInstallStateResolver.state(
    forSourceBundleIdentifier: "com.example.demo",
    latestVersion: "1.2.3",
    installedApps: installedApps
)
expect(
    matchingState == .run(relativeBundlePath: "com.example.demo.app"),
    "matching installed source app should run the installed app"
)

let newerSourceState = SourceAppInstallStateResolver.state(
    forSourceBundleIdentifier: "com.example.demo",
    latestVersion: "1.2.4",
    installedApps: installedApps
)
expect(
    newerSourceState == .install,
    "different source version should keep the install action available"
)

let missingState = SourceAppInstallStateResolver.state(
    forSourceBundleIdentifier: "com.example.missing",
    latestVersion: "1.0",
    installedApps: installedApps
)
expect(
    missingState == .install,
    "missing installed app should offer install"
)

print("SourceAppInstallationStateTests passed")
