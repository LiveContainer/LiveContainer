#if false
import Foundation
import SwiftUI
import SideSign

@MainActor
final class TrollBoxSigningManager: ObservableObject {
    static let shared = TrollBoxSigningManager()

    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private init() {}

    private func keyStoreKey(for team: Team) -> String {
        "trollbox.signing.keystore.\(team.identifier)"
    }

    private func loadKeyStore(for team: Team) throws -> KeyStore? {
        guard let data = try TrollBoxKeychain.load(
            for: keyStoreKey(for: team)
        ) else {
            return nil
        }

        return try KeyStore(p12Data: data)
    }

    private func saveKeyStore(
        _ keyStore: KeyStore,
        for team: Team
    ) throws {
        let data = try keyStore.exportP12()

        try TrollBoxKeychain.save(
            data,
            for: keyStoreKey(for: team)
        )
    }

    private func getOrCreateKeyStore(
        team: Team,
        session: Session
    ) async throws -> KeyStore {
        if let existing = try loadKeyStore(for: team) {
            return existing
        }

        let created = try await DeveloperPortal.shared.addCertificate(
            machineName: "TrollBox",
            type: .iosDevelopment,
            to: team,
            session: session
        )

        guard created.certificate.identifier != nil else {
            throw SigningError.missingCertificateIdentifier
        }

        try saveKeyStore(created, for: team)

        return created
    }

    private func getOrCreateAppID(
        bundleIdentifier: String,
        team: Team,
        session: Session
    ) async throws -> AppID {
        let existing = try await DeveloperPortal.shared.fetchAppIDs(
            for: team,
            session: session
        )

        if let match = existing.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            return match
        }

        return try await DeveloperPortal.shared.addAppID(
            withName: "TrollBox \(bundleIdentifier)",
            bundleIdentifier: bundleIdentifier,
            team: team,
            session: session
        )
    }

    func signApp(at appURL: URL) async throws {
        guard !isBusy else {
            throw SigningError.alreadyBusy
        }

        isBusy = true
        errorMessage = nil

        defer {
            isBusy = false
        }

        do {
            let context = try TrollBoxAppleAccountManager.shared
                .signingContext()

            guard context.team.type != .unknown else {
                throw SigningError.unknownTeamType
            }

            guard let app = AppBundle(fileURL: appURL) else {
                throw SigningError.invalidApp
            }

            let keyStore = try await getOrCreateKeyStore(
                team: context.team,
                session: context.session
            )

            var profiles: [ProvisioningProfile] = []
            var processedBundleIDs = Set<String>()

            for bundle in app.allAppBundles {
                let bundleID = bundle.bundleIdentifier

                try validateTeamEntitlements(
                    bundle: bundle,
                    team: context.team
                )

                guard processedBundleIDs.insert(bundleID).inserted else {
                    throw SigningError.duplicateBundleIdentifier(bundleID)
                }

                let appID = try await getOrCreateAppID(
                    bundleIdentifier: bundleID,
                    team: context.team,
                    session: context.session
                )

                let profile = try await DeveloperPortal.shared
                    .downloadProvisioningProfile(
                        for: appID,
                        isTeamProfile: true,
                        type: .iOS,
                        team: context.team,
                        session: context.session
                    )

                try validate(
                    bundle: bundle,
                    profile: profile,
                    keyStore: keyStore,
                    team: context.team
                )

                profiles.append(profile)
            }

            guard profiles.count == app.allAppBundles.count else {
                throw SigningError.incompleteProfiles
            }

            let signer = AppBundleSigner(
                team: context.team,
                keyStore: keyStore
            )

            try await signer.signApp(
                at: appURL,
                provisioningProfiles: profiles
            )

        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func validateTeamEntitlements(
        bundle: AppBundle,
        team: Team
    ) throws {
        guard let allowedEntitlements = team.type.allowedEntitlements else {
            throw SigningError.unknownTeamType
        }

        let systemManagedEntitlements: Set<String> = [
            "application-identifier",
            "com.apple.developer.team-identifier",
            "get-task-allow"
        ]

        for entitlement in bundle.entitlements.keys {
            if systemManagedEntitlements.contains(entitlement) {
                continue
            }

            guard let known = Entitlement.allKnown.first(where: {
                $0.rawValue == entitlement
            }) else {
                continue
            }

            guard allowedEntitlements.contains(known) else {
                throw SigningError.unsupportedEntitlement(
                    bundle.bundleIdentifier,
                    entitlement
                )
            }
        }
    }

    private func validate(
        bundle: AppBundle,
        profile: ProvisioningProfile,
        keyStore: KeyStore,
        team: Team
    ) throws {
        let bundleID = bundle.bundleIdentifier

        guard profile.bundleIdentifier == bundleID else {
            throw SigningError.bundleIdentifierMismatch(
                bundleID,
                profile.bundleIdentifier
            )
        }

        guard profile.teamIdentifier == team.identifier else {
            throw SigningError.teamMismatch(bundleID)
        }

        guard profile.expirationDate > Date() else {
            throw SigningError.expiredProfile(bundleID)
        }

        let certificateSerial = keyStore.certificate.serialNumberHex

        guard profile.certificates.contains(where: {
            $0.serialNumberHex.caseInsensitiveCompare(
                certificateSerial
            ) == .orderedSame
        }) else {
            throw SigningError.certificateMismatch(bundleID)
        }

        let profileEntitlements = profile.entitlements
        let appEntitlements = bundle.entitlements

        let systemManagedEntitlements: Set<String> = [
            "application-identifier",
            "com.apple.developer.team-identifier",
            "get-task-allow"
        ]

        for entitlement in appEntitlements.keys {
            if systemManagedEntitlements.contains(entitlement) {
                continue
            }

            guard profileEntitlements[entitlement] != nil else {
                throw SigningError.missingEntitlement(
                    bundleID,
                    entitlement
                )
            }
        }
    }
}

private enum SigningError: LocalizedError {
    case alreadyBusy
    case invalidApp
    case unknownTeamType
    case unsupportedEntitlement(String, String)
    case missingCertificateIdentifier
    case bundleIdentifierMismatch(String, String)
    case teamMismatch(String)
    case expiredProfile(String)
    case certificateMismatch(String)
    case missingEntitlement(String, String)
    case duplicateBundleIdentifier(String)
    case incompleteProfiles

    var errorDescription: String? {
        switch self {
        case .alreadyBusy:
            return "TrollBox signing is already running."

        case .invalidApp:
            return "The selected IPA does not contain a valid app bundle."

        case .unknownTeamType:
            return "Apple did not provide a recognized Developer Team type."

        case .unsupportedEntitlement(let bundleID, let entitlement):
            return """
            This app requires an entitlement unavailable to your Apple Developer team.
            App: \(bundleID)
            Entitlement: \(entitlement)
            Free accounts support limited capabilities. Try Guest installation if this app requires paid capabilities.
            """

        case .missingCertificateIdentifier:
            return "Apple did not return a certificate identifier."

        case .bundleIdentifierMismatch(let bundleID, let profileID):
            return """
            Provisioning profile mismatch.
            App: \(bundleID)
            Profile: \(profileID)
            """

        case .teamMismatch(let bundleID):
            return "The provisioning profile for \(bundleID) belongs to a different team."

        case .expiredProfile(let bundleID):
            return "The provisioning profile for \(bundleID) has expired."

        case .certificateMismatch(let bundleID):
            return "The provisioning profile for \(bundleID) does not contain TrollBox's signing certificate."

        case .missingEntitlement(let bundleID, let entitlement):
            return """
            Missing required entitlement.
            App: \(bundleID)
            Entitlement: \(entitlement)
            """

        case .duplicateBundleIdentifier(let bundleID):
            return "Duplicate bundle identifier: \(bundleID)."

        case .incompleteProfiles:
            return "TrollBox could not obtain a provisioning profile for every app bundle."
        }
    }
}

#endif
