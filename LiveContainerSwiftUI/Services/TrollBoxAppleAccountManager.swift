#if false
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

            session = result

            let encoded = try JSONEncoder().encode(result)
            try TrollBoxKeychain.save(encoded, for: sessionKey)

            account = result.account

            try await refreshTeams()
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

    func restoreSession() async {
        guard !isBusy else { return }

        do {
            guard let data = try TrollBoxKeychain.load(for: sessionKey) else {
                return
            }

            let restored = try JSONDecoder().decode(
                AuthSession.self,
                from: data
            )

            guard restored.session.isValid else {
                try TrollBoxKeychain.delete(for: sessionKey)
                return
            }

            session = restored
            account = restored.account

            try await refreshTeams()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signingContext() throws -> (session: Session, team: Team) {
        guard let authSession = session, authSession.session.isValid else {
            throw SigningContextError.notSignedIn
        }

        guard let team = selectedTeam else {
            throw SigningContextError.noTeamSelected
        }

        return (authSession.session, team)
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

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to your Apple Account before signing a Full app."
        case .noTeamSelected:
            return "Select an Apple Developer team before signing a Full app."
        }
    }
}

#endif
