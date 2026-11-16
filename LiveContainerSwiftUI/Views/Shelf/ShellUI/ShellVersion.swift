// S2Arm addition (not in upstream): the version a player's screenshot shows, so a report says which build it came from.
import SwiftUI

/// "v0.3.0" for a release, "v0.2.6-dev+ba0ef07" for anything else: the `S2ADisplayVersion` the computer writes into
/// Info.plist when it assembles the app (pack/jobs/core.py display_version, the same text the computer's S2Arm shows).
/// An app assembled before that key existed falls back to "v" + CFBundleShortVersionString; nothing known is empty.
public enum ShellVersion {
    public static let display = text(Bundle.main.infoDictionary ?? [:])

    static func text(_ info: [String: Any]) -> String {
        if let shown = info["S2ADisplayVersion"] as? String, !shown.isEmpty { return shown }
        if let short = info["CFBundleShortVersionString"] as? String, !short.isEmpty { return "v" + short }
        return ""
    }
}

/// The version at the top of the library: small and quiet like the line under the settings, legible on any banner,
/// never in the way of a tap.
struct LibraryVersionBadge: View {
    var body: some View {
        if !ShellVersion.display.isEmpty {
            Text(verbatim: ShellVersion.display).shellText(12.5).monospacedDigit().lineLimit(1)
                .foregroundStyle(.white.opacity(0.45)).shadow(color: .black.opacity(0.6), radius: 2)
                .allowsHitTesting(false)
                .accessibilityIdentifier("library.version")
        }
    }
}
