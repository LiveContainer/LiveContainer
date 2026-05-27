import Foundation

struct SourceAppInstalledApp: Equatable {
    let bundleIdentifier: String
    let version: String
    let relativeBundlePath: String
}

enum SourceAppInstallState: Equatable {
    case install
    case run(relativeBundlePath: String)
}

enum SourceAppInstallStateResolver {
    static func state(
        forSourceBundleIdentifier bundleIdentifier: String,
        latestVersion: String?,
        installedApps: [SourceAppInstalledApp]
    ) -> SourceAppInstallState {
        guard let latestVersion = latestVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !latestVersion.isEmpty else {
            return .install
        }

        // LiveContainer supports installing multiple copies with the same bundle ID.
        // Only switch to Run when one of those copies is already at the source's latest version.
        for installedApp in installedApps where installedApp.bundleIdentifier == bundleIdentifier {
            let installedVersion = installedApp.version.trimmingCharacters(in: .whitespacesAndNewlines)
            if installedVersion == latestVersion {
                return .run(relativeBundlePath: installedApp.relativeBundlePath)
            }
        }

        // Keep Install available for different versions so users can add another copy
        // or choose the existing replace flow themselves.
        return .install
    }
}
