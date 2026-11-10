import Foundation
import SwiftUI
import SideSign

@MainActor
final class TrollBoxAppleAccountManager: ObservableObject {
    static let shared = TrollBoxAppleAccountManager()

    @Published private(set) var account: Account?
    @Published private(set) var teams: [Team] = []
    @Published var selectedTeamID: String? {
        didSet {
            UserDefaults.standard.set(
                selectedTeamID,
                forKey: "TrollBox.AppleAccount.SelectedTeam"
            )
        }
    }

    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var pendingTwoFactorRequest: TwoFactorRequest?

    private let sessionKey = "trollbox.appleAccount.session"

    private var session: AuthSession?
    private var verificationContinuation:
        CheckedContinuation<TwoFactorResponse, Error>?

    private init() {
        selectedTeamID = UserDefaults.standard.string(
            forKey: "TrollBox.AppleAccount.SelectedTeam"
        )
    }

    var isSignedIn: Bool {
        session != nil
    }

    var selectedTeam: Team? {
        teams.first { $0.identifier == selectedTeamID }
    }

    func signIn(appleID: String, password: String) async {
        guard !isBusy else { return }

        isBusy = true
        errorMessage = nil

        defer { isBusy = false }

        do {
            let anisette = try await TrollBoxAnisetteManager.shared
                .fetchAnisetteData()

            let result = try await DeveloperPortal.shared.authenticate(
                appleID: appleID,
                password: password,
                anisetteData: anisette,
                xcodeVersion: "26.2",
                verificationHandler: { [weak self] request in
                    guard let self else {
                        return .cancel
                    }

                    return try await self.requestVerification(request)
                }
            )

            let fetchedAccount = try await DeveloperPortal.shared.fetchAccount(
                session: result.session
            )

            let fetchedTeams = try await DeveloperPortal.shared.fetchTeams(
                for: fetchedAccount,
                session: result.session
            )

            let encoded = try JSONEncoder().encode(result)
            try TrollBoxKeychain.save(encoded, for: sessionKey)

            session = result
            account = fetchedAccount
            teams = fetchedTeams

            if !teams.contains(where: {
                $0.identifier == selectedTeamID
            }) {
                selectedTeamID = teams.first?.identifier
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestVerification(
        _ request: TwoFactorRequest
    ) async throws -> TwoFactorResponse {
        pendingTwoFactorRequest = request

        return try await withCheckedThrowingContinuation {
            continuation in

            verificationContinuation = continuation
        }
    }

    func completeTwoFactor(_ response: TwoFactorResponse) {
        guard let continuation = verificationContinuation else {
            return
        }

        verificationContinuation = nil
        pendingTwoFactorRequest = nil
        continuation.resume(returning: response)
    }

    func refreshTeams() async throws {
        guard let session else { return }

        let fetchedAccount = try await DeveloperPortal.shared.fetchAccount(
            session: session.session
        )

        account = fetchedAccount

        let fetchedTeams = try await DeveloperPortal.shared.fetchTeams(
            for: fetchedAccount,
            session: session.session
        )

        teams = fetchedTeams

        if !teams.contains(where: {
            $0.identifier == selectedTeamID
        }) {
            selectedTeamID = teams.first?.identifier
        }
    }

    private func isExpiredSessionError(_ error: Error) -> Bool {
        guard let serverError = error as? ServerError else {
            return false
        }

        if case .underlyingError(let code, _) = serverError {
            return code == 1100
        }

        return false
    }

    private func clearRejectedSession() {
        session = nil
        account = nil
        teams = []

        do {
            try TrollBoxKeychain.delete(for: sessionKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreSavedSession() async throws {
        guard let data = try TrollBoxKeychain.load(for: sessionKey) else {
            throw SigningContextError.notSignedIn
        }

        let restored = try JSONDecoder().decode(
            AuthSession.self,
            from: data
        )

        guard restored.session.isValid else {
            clearRejectedSession()
            throw SigningContextError.notSignedIn
        }

        do {
            let fetchedAccount = try await DeveloperPortal.shared.fetchAccount(
                session: restored.session
            )

            let fetchedTeams = try await DeveloperPortal.shared.fetchTeams(
                for: fetchedAccount,
                session: restored.session
            )

            session = restored
            account = fetchedAccount
            teams = fetchedTeams

            if !teams.contains(where: {
                $0.identifier == selectedTeamID
            }) {
                selectedTeamID = teams.first?.identifier
            }
        } catch {
            if isExpiredSessionError(error) {
                clearRejectedSession()
                throw SigningContextError.sessionExpired
            }

            throw error
        }
    }

    func restoreSession() async {
        guard !isBusy else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            if session == nil {
                try await restoreSavedSession()
            }
        } catch SigningContextError.notSignedIn {
            // No saved session is normal when the user has not signed in.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signingContext() async throws -> (session: Session, team: Team) {
        if session == nil {
            try await restoreSavedSession()
        }

        guard let authSession = session, authSession.session.isValid else {
            throw SigningContextError.notSignedIn
        }

        guard let team = selectedTeam else {
            throw SigningContextError.noTeamSelected
        }

        return (authSession.session, team)
    }

    func handleSigningError(_ error: Error) {
        guard isExpiredSessionError(error) else {
            return
        }

        clearRejectedSession()
        errorMessage = "Your Apple sign-in session expired. Please sign in again."
    }

    func signOut() {
        if let continuation = verificationContinuation {
            verificationContinuation = nil
            continuation.resume(returning: .cancel)
        }

        pendingTwoFactorRequest = nil
        session = nil
        account = nil
        teams = []
        selectedTeamID = nil

        do {
            try TrollBoxKeychain.delete(for: sessionKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


private enum SigningContextError: LocalizedError {
    case notSignedIn
    case noTeamSelected
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to your Apple Account before signing a Full app."
        case .noTeamSelected:
            return "Select an Apple Developer team before signing a Full app."
        case .sessionExpired:
            return "Your Apple sign-in session expired. Please sign in again."
        }
    }
}
