import Foundation
import Combine
import SideSign

@MainActor
final class TrollBoxAnisetteManager: ObservableObject {
    static let shared = TrollBoxAnisetteManager()

    private let serverListURL = URL(
        string: "https://servers.sidestore.io/servers.json"
    )!

    private let identifierKey = "TrollBox.Anisette.Identifier"
    private let lastServerKey = "TrollBox.Anisette.LastServer"
    private let selectedServerKey = "TrollBox.Anisette.SelectedServer"
    private let rotationKey = "TrollBox.Anisette.Rotation"
    private let adiBlobKey = "trollbox.anisette.adiBlob"

    private let manager = AnisetteDataManager.shared

    @Published private(set) var servers: [AnisetteServerItem] = []
    @Published var selectedServerAddress: String {
        didSet {
            UserDefaults.standard.set(
                selectedServerAddress,
                forKey: selectedServerKey
            )
        }
    }

    @Published var automaticRotation: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticRotation,
                forKey: rotationKey
            )
        }
    }

    @Published private(set) var lastSuccessfulServer: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isLoadingServers = false

    private init() {
        selectedServerAddress = UserDefaults.standard.string(
            forKey: selectedServerKey
        ) ?? ""

        automaticRotation = UserDefaults.standard.object(
            forKey: rotationKey
        ) as? Bool ?? true

        lastSuccessfulServer = UserDefaults.standard.string(
            forKey: lastServerKey
        )
    }

    func loadServers() async {
        guard !isLoadingServers else { return }

        isLoadingServers = true
        defer { isLoadingServers = false }

        do {
            let serverList = try await manager.fetchServerList(
                from: serverListURL
            )

            servers = serverList.servers.filter {
                !$0.isHidden &&
                URL(string: $0.address)?.scheme?.hasPrefix("http") == true
            }

            if !servers.contains(where: {
                $0.address == selectedServerAddress
            }) {
                selectedServerAddress = servers.first?.address ?? ""
            }

            statusMessage = "\(servers.count) Anisette servers available."
        } catch {
            statusMessage = "Could not load servers: \(error.localizedDescription)"
        }
    }
    private func recordSuccessfulServer(_ url: URL) {
    UserDefaults.standard.set(
        url.absoluteString,
        forKey: lastServerKey
    )
    lastSuccessfulServer = url.absoluteString
    statusMessage = "Connected using \(url.host ?? url.absoluteString)"
}
    func fetchAnisetteData() async throws -> AnisetteData {
        if servers.isEmpty {
            await loadServers()
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

        let selectedIndex = servers.firstIndex {
            $0.address == selectedServerAddress
        } ?? 0

        let lastSuccessfulIndex = servers.firstIndex {
            $0.address == lastSuccessfulServer
        }

        let preferredIndex = lastSuccessfulIndex ?? selectedIndex

        let orderedServers = Array(servers.dropFirst(preferredIndex))
            + Array(servers.prefix(preferredIndex))

        let candidates = automaticRotation
            ? orderedServers
            : [servers[selectedIndex]]

        let urls = candidates.compactMap {
            URL(string: $0.address)
        }

        guard !urls.isEmpty else {
            throw AnisetteError.noServersConfigured
        }

        let existingBlob = try TrollBoxKeychain.load(for: adiBlobKey)
        var lastError: Error?

        for url in urls {
            do {
                let result = try await manager.fetchAnisetteData(
                    mode: .remote(server: url),
                    identifier: identifier,
                    existingAdiBlob: existingBlob
                )

                if let newBlob = result.newAdiBlob {
                    try TrollBoxKeychain.save(newBlob, for: adiBlobKey)
                }

                recordSuccessfulServer(url)
                return result.data
            } catch {
                lastError = error

                let needsReprovision: Bool

                if let anisetteError = error as? AnisetteError,
                   case let .badServerResponse(statusCode, payload) = anisetteError {
                    needsReprovision =
                        statusCode == -1 &&
                        payload.localizedCaseInsensitiveContains(
                            "not provisioned for this server"
                        ) &&
                        payload.localizedCaseInsensitiveContains(
                            "reprovision required"
                        )
                } else {
                    needsReprovision = false
                }

                guard needsReprovision, existingBlob != nil else {
                    continue
                }

                statusMessage = "Reprovisioning with \(url.host ?? url.absoluteString)..."

                do {
                    let result = try await manager.fetchAnisetteData(
                        mode: .remote(server: url),
                        identifier: identifier,
                        existingAdiBlob: nil
                    )

                    if let newBlob = result.newAdiBlob {
                        try TrollBoxKeychain.save(newBlob, for: adiBlobKey)
                    }

                    recordSuccessfulServer(url)
                    return result.data
                } catch {
                    lastError = error
                }
            }
        }

        let finalError = lastError ?? AnisetteError.allServersFailed
        statusMessage = "Anisette connection failed: \(finalError.localizedDescription)"
        throw finalError
    }
}