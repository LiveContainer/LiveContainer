import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let launchMapKey = "LCGuestURLLaunchMap"
    private static let bundleLaunchMapKey = "LCGuestBundleLaunchMap"
    private static let directLaunchMapKey = "LCGuestDirectLaunchMap"
    private static let launchExtensionBundleIDKey = "LCLaunchExtensionBundleID"
    private static let launchExtensionContainerNameKey = "LCLaunchExtensionContainerName"
    private static let launchExtensionLaunchDateKey = "LCLaunchExtensionLaunchDate"
    private static let launchExtensionOpenURLKey = "LCLaunchExtensionOpenURL"
    private static var launchHelperExtension: AnyObject?
    private static var siteAssociationCache = [String: SiteAssociation]()
    private static var failedSiteAssociationHosts = Set<String>()

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message: Any?
        if #available(iOS 15.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        Task {
            let payload = await handleMessage(message)
            let response = NSExtensionItem()
            if #available(iOS 15.0, *) {
                response.userInfo = [SFExtensionMessageKey: payload]
            } else {
                response.userInfo = ["message": payload]
            }
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    private func handleMessage(_ message: Any?) async -> [String: Any] {
        guard let body = message as? [String: Any],
              let command = body["command"] as? String else {
            return ["ok": true]
        }

        switch command {
        case "launchResolved":
            guard let urlString = body["url"] as? String,
                  let url = URL(string: urlString) else {
                return ["ok": false]
            }
            return ["ok": await launchResolved(url)]
        default:
            return ["ok": true]
        }
    }

    private func sharedMap(forKey key: String) -> [String: String] {
        for defaults in candidateDefaults() {
            guard let launchMap = defaults.dictionary(forKey: key) as? [String: String],
                  !launchMap.isEmpty else {
                continue
            }
            return launchMap
        }
        return [:]
    }

    private func launchResolved(_ url: URL) async -> Bool {
        guard let target = await launchTarget(for: url) else {
            return false
        }
        return launch(target)
    }

    private func launchTarget(for url: URL) async -> LaunchTarget? {
        let scheme = (url.scheme ?? "").lowercased()
        if !scheme.isEmpty && scheme != "http" && scheme != "https" {
            if let bundleName = sharedMap(forKey: Self.launchMapKey)[scheme] {
                return LaunchTarget(bundleName: bundleName, openURL: url)
            }
            return nil
        }

        guard scheme == "https",
              let bundleName = await resolveUniversalLink(url) else {
            return nil
        }

        return LaunchTarget(bundleName: bundleName, openURL: url)
    }

    private func resolveUniversalLink(_ url: URL) async -> String? {
        guard url.scheme == "https",
              let host = url.host,
              let siteAssociation = await loadSiteAssociation(host: host),
              let details = siteAssociation.applinks?.details else {
            return nil
        }

        let bundleLaunchMap = sharedMap(forKey: Self.bundleLaunchMapKey)
        for item in details {
            guard item.matches(url: url) else {
                continue
            }

            for bundleIdentifier in item.getBundleIds() {
                if let bundleName = bundleLaunchMap[bundleIdentifier] {
                    return bundleName
                }
            }
        }
        return nil
    }

    private func launchURL(for target: LaunchTarget) -> URL? {
        let encodedOpenURL = Data(target.openURL.absoluteString.utf8).base64EncodedString()
        var components = URLComponents()
        components.scheme = "livecontainer"
        components.host = "livecontainer-launch"
        components.queryItems = [
            URLQueryItem(name: "bundle-name", value: target.bundleName),
            URLQueryItem(name: "open-url", value: encodedOpenURL)
        ]
        return components.url
    }

    private func prepareDirectLaunch(_ target: LaunchTarget) -> Bool {
        guard let (defaults, containerName) = directLaunchEntry(for: target.bundleName) else {
            return false
        }

        defaults.set(target.bundleName, forKey: Self.launchExtensionBundleIDKey)
        defaults.set(containerName, forKey: Self.launchExtensionContainerNameKey)
        defaults.set(target.openURL.absoluteString, forKey: Self.launchExtensionOpenURLKey)
        defaults.set(Date.now, forKey: Self.launchExtensionLaunchDateKey)
        return defaults.synchronize()
    }

    private func directLaunchEntry(for bundleName: String) -> (defaults: UserDefaults, containerName: String)? {
        for defaults in candidateDefaults() {
            guard let launchMap = defaults.dictionary(forKey: Self.directLaunchMapKey) as? [String: String],
                  let containerName = launchMap[bundleName] else {
                continue
            }
            return (defaults, containerName)
        }
        return nil
    }

    private func launch(_ target: LaunchTarget) -> Bool {
        guard let launchURL = launchURL(for: target) else {
            return false
        }

        _ = prepareDirectLaunch(target)
        return openWithLaunchHelper(launchURL)
    }

    private func openWithLaunchHelper(_ url: URL) -> Bool {
        guard let helper = launchHelper() else {
            return false
        }
        let item = NSExtensionItem()
        item.userInfo = ["url": url]
        let selector = NSSelectorFromString("beginExtensionRequestWithInputItems:completion:")
        guard helper.responds(to: selector) else {
            return false
        }
        _ = helper.perform(selector, with: [item], with: nil)
        return true
    }

    private func launchHelper() -> AnyObject? {
        if let helper = Self.launchHelperExtension {
            return helper
        }

        let parentBundleIdentifier = (Bundle.main.bundleIdentifier! as NSString).deletingPathExtension
        let helperIdentifier = (parentBundleIdentifier as NSString).appendingPathExtension("LaunchAppExtensionHelper")
        let selector = NSSelectorFromString("extensionWithIdentifier:error:")
        guard let extensionClass = NSClassFromString("NSExtension") as? NSObject.Type,
              extensionClass.responds(to: selector),
              let helper = extensionClass.perform(selector, with: helperIdentifier, with: nil)?.takeUnretainedValue() else {
            return nil
        }
        Self.launchHelperExtension = helper
        return helper
    }

    private func loadSiteAssociation(host: String) async -> SiteAssociation? {
        if let cached = Self.siteAssociationCache[host] {
            return cached
        }
        if Self.failedSiteAssociationHosts.contains(host) {
            return nil
        }

        let urls = [
            URL(string: "https://\(host)/apple-app-site-association"),
            URL(string: "https://\(host)/.well-known/apple-app-site-association")
        ].compactMap { $0 }

        for url in urls {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let siteAssociation = try JSONDecoder().decode(SiteAssociation.self, from: data)
                Self.siteAssociationCache[host] = siteAssociation
                return siteAssociation
            } catch {
                continue
            }
        }
        Self.failedSiteAssociationHosts.insert(host)
        return nil
    }

    private func configuredAppGroups() -> [String] {
        (Bundle.main.object(forInfoDictionaryKey: "LiveContainerAppGroups") as? [String] ?? [])
            .filter { !$0.isEmpty }
    }

    private func candidateDefaults() -> [UserDefaults] {
        configuredAppGroups().compactMap { UserDefaults(suiteName: $0) }
    }
}

private struct LaunchTarget {
    let bundleName: String
    let openURL: URL
}

private struct SiteAssociation: Decodable {
    let applinks: AppLinks?
}

private struct AppLinks: Decodable {
    let details: [SiteAssociationDetailItem]?

    private enum CodingKeys: String, CodingKey {
        case details
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let arrayDetails = try? container.decode([SiteAssociationDetailItem].self, forKey: .details) {
            details = arrayDetails
            return
        }

        if let dictionaryDetails = try? container.decode([String: SiteAssociationDetailValue].self, forKey: .details) {
            details = dictionaryDetails.keys.sorted().map { key in
                let value = dictionaryDetails[key]
                return SiteAssociationDetailItem(
                    appID: key,
                    appIDs: value?.appIDs,
                    paths: value?.paths,
                    components: value?.components
                )
            }
            return
        }

        details = nil
    }
}

private struct SiteAssociationDetailValue: Decodable {
    let appIDs: [String]?
    let paths: [String]?
    let components: [SiteAssociationComponent]?
}

private struct SiteAssociationDetailItem: Decodable {
    let appID: String?
    let appIDs: [String]?
    let paths: [String]?
    let components: [SiteAssociationComponent]?

    init(appID: String?, appIDs: [String]?, paths: [String]? = nil, components: [SiteAssociationComponent]? = nil) {
        self.appID = appID
        self.appIDs = appIDs
        self.paths = paths
        self.components = components
    }

    func getBundleIds() -> [String] {
        var identifiers = [String]()
        if let appID {
            identifiers.append(bundleIdentifier(from: appID))
        }
        if let appIDs {
            identifiers.append(contentsOf: appIDs.map { bundleIdentifier(from: $0) })
        }
        return identifiers.filter { !$0.isEmpty }
    }

    private func bundleIdentifier(from appID: String) -> String {
        guard let separator = appID.firstIndex(of: ".") else {
            return ""
        }
        return String(appID[appID.index(after: separator)...])
    }

    func matches(url: URL) -> Bool {
        if let components, !components.isEmpty {
            return components.first(where: { $0.matches(url: url) }).map { !$0.exclude } ?? false
        }

        if let paths, !paths.isEmpty {
            return matches(url: url, paths: paths)
        }

        return true
    }

    private func matches(url: URL, paths: [String]) -> Bool {
        let path = url.path.isEmpty ? "/" : url.path
        var didMatchInclude = false

        for rule in paths {
            let trimmedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            let isExclude = trimmedRule.hasPrefix("NOT ")
            let pattern = isExclude ? String(trimmedRule.dropFirst(4)) : trimmedRule
            guard matchAASAPath(path, pattern: pattern) else {
                continue
            }
            if isExclude {
                return false
            }
            didMatchInclude = true
        }

        return didMatchInclude
    }
}

private struct SiteAssociationComponent: Decodable {
    let path: String?
    let query: [String: StringOrBool]?
    let fragment: String?
    let exclude: Bool

    private enum CodingKeys: String, CodingKey {
        case path = "/"
        case query = "?"
        case fragment = "#"
        case exclude
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        query = try container.decodeIfPresent([String: StringOrBool].self, forKey: .query)
        fragment = try container.decodeIfPresent(String.self, forKey: .fragment)
        exclude = try container.decodeIfPresent(Bool.self, forKey: .exclude) ?? false
    }

    func matches(url: URL) -> Bool {
        if let path, !matchWildcard(value: url.path.isEmpty ? "/" : url.path, pattern: path) {
            return false
        }

        if let fragment, !matchWildcard(value: url.fragment ?? "", pattern: fragment) {
            return false
        }

        if let query {
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            for (key, expectedValue) in query {
                guard let actualValue = queryItems.first(where: { $0.name == key })?.value else {
                    return false
                }
                if !expectedValue.matches(value: actualValue) {
                    return false
                }
            }
        }

        return true
    }
}

private enum StringOrBool: Decodable {
    case string(String)
    case bool(Bool)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        self = .bool(try container.decode(Bool.self))
    }

    func matches(value: String) -> Bool {
        switch self {
        case .string(let expectedValue):
            return matchWildcard(value: value, pattern: expectedValue)
        case .bool(let expectedValue):
            return expectedValue ? !value.isEmpty : value.isEmpty
        }
    }
}

private func matchWildcard(value: String, pattern: String) -> Bool {
    if pattern == "*" {
        return true
    }

    if pattern.hasSuffix("*") {
        return value.hasPrefix(String(pattern.dropLast()))
    }

    return value == pattern
}

private func matchAASAPath(_ path: String, pattern: String) -> Bool {
    if pattern == "*" || pattern == "/*" {
        return true
    }

    if pattern.hasSuffix("*") {
        return path.hasPrefix(String(pattern.dropLast()))
    }

    return path == pattern
}
