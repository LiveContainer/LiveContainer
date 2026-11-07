import Foundation
import SideSign

@MainActor
final class TrollBoxAnisetteManager {
    static let shared = TrollBoxAnisetteManager()

    private let serverListURL = URL(
        string: "https://servers.sidestore.io/servers.json"
    )!

    private let identifierKey = "TrollBox.Anisette.Identifier"
    private let lastServerKey = "TrollBox.Anisette.LastServer"
    private let adiBlobKey = "trollbox.anisette.adiBlob"

    private let manager = AnisetteDataManager.shared

    private init() {}

    func fetchAnisetteData() async throws -> AnisetteData {
        let serverList = try await manager.fetchServerList(
            from: serverListURL
        )

        let servers = serverList.servers.compactMap {
            URL(string: $0.address)
        }

        guard !servers.isEmpty else {
            throw AnisetteError.noServersConfigured
        }

        let defaults = UserDefaults.standard

        let identifier: UUID
        if let saved = defaults.string(forKey: identifierKey),
           let uuid = UUID(uuidString: saved) {
            identifier = uuid
        } else {
            identifier = UUID()
            defaults.set(identifier.uuidString, forKey: identifierKey)
        }

        let lastServer = defaults.string(forKey: lastServerKey)
        let startIndex = servers.firstIndex {
            $0.absoluteString == lastServer
        } ?? 0

        let existingBlob = try TrollBoxKeychain.load(for: adiBlobKey)

        let result = try await manager.fetchAnisetteDataWithFailover(
            servers: servers,
            startIndex: startIndex,
            identifier: identifier,
            existingAdiBlob: existingBlob,
            onSuccess: { url in
                Task { @MainActor in
                    defaults.set(
                        url.absoluteString,
                        forKey: self.lastServerKey
                    )
                }
            }
        )

        if let newBlob = result.newAdiBlob {
            try TrollBoxKeychain.save(newBlob, for: adiBlobKey)
        }

        return result.data
    }
}
