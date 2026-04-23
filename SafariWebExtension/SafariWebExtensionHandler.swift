import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let launchMapKey = "LCGuestURLLaunchMap"

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message: Any?
        if #available(iOS 15.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        let payload = handleMessage(message)
        let response = NSExtensionItem()
        if #available(iOS 15.0, *) {
            response.userInfo = [SFExtensionMessageKey: payload]
        } else {
            response.userInfo = ["message": payload]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func handleMessage(_ message: Any?) -> [String: Any] {
        guard let body = message as? [String: Any],
              let command = body["command"] as? String else {
            return ["ok": true]
        }

        switch command {
        case "getLaunchMap":
            return [
                "ok": true,
                "launchMap": sharedLaunchMap()
            ]
        default:
            return ["ok": true]
        }
    }

    private func sharedLaunchMap() -> [String: String] {
        for defaults in candidateDefaults() {
            guard let launchMap = defaults.dictionary(forKey: Self.launchMapKey) as? [String: String],
                  !launchMap.isEmpty else {
                continue
            }
            return launchMap
        }
        return [:]
    }

    private func configuredAppGroups() -> [String] {
        (Bundle.main.object(forInfoDictionaryKey: "LiveContainerAppGroups") as? [String] ?? [])
            .filter { !$0.isEmpty }
    }

    private func candidateDefaults() -> [UserDefaults] {
        configuredAppGroups().compactMap { UserDefaults(suiteName: $0) }
    }
}
