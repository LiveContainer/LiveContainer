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

        guard let installedApp = installedApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return .install
        }

        if installedApp.version.trimmingCharacters(in: .whitespacesAndNewlines) == latestVersion {
            return .run(relativeBundlePath: installedApp.relativeBundlePath)
        }

        return .install
    }
}
