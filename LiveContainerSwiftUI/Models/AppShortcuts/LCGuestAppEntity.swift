//
//  LCGuestAppEntity.swift
//  LiveContainerSwiftUI
//
//  Exposes each guest app as an AppEntity so the system can enumerate them,
//  match them against typed or spoken text, and offer one Spotlight and Siri
//  row per app without the user hand-building a shortcut for each one.
//

import AppIntents
import Foundation

extension String {
    var lcFolded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

@available(iOS 17.0, *)
struct LCGuestApp: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "App")
    }

    static var defaultQuery = LCGuestAppQuery()

    var displayName: String
    var containerName: String?
    var bundleFolderName: String
    var containerFolderName: String?
    var searchTerms: [String]
    var iconURL: URL?

    /// Derived rather than stored, so it cannot drift from the fields it names.
    var id: String {
        containerFolderName.map { "\(bundleFolderName)|\($0)" } ?? bundleFolderName
    }

    var displayRepresentation: DisplayRepresentation {
        // Only apps with more than one container carry a container name, so the
        // subtitle stays empty in the common case instead of repeating itself.
        let subtitle: LocalizedStringResource? = containerName
            .flatMap { $0.isEmpty ? nil : "\($0)" }
        return DisplayRepresentation(title: "\(displayName)",
                                     subtitle: subtitle,
                                     image: iconURL.map { .init(url: $0) })
    }

    /// The `livecontainer-launch` URL for this app, minus the scheme, which
    /// depends on which container ends up hosting it.
    var launchURLComponents: URLComponents {
        var components = URLComponents()
        components.host = "livecontainer-launch"
        var items = [URLQueryItem(name: "bundle-name", value: bundleFolderName)]
        if let containerFolderName {
            items.append(URLQueryItem(name: "container-folder-name", value: containerFolderName))
        }
        components.queryItems = items
        return components
    }
}

// EnumerableEntityQuery matters here, not just EntityStringQuery: a
// parameterised App Shortcut needs the system to be able to enumerate every
// possible value of the parameter up front, otherwise it indexes the shortcut
// with an empty value set and nothing matches in Spotlight.
@available(iOS 17.0, *)
struct LCGuestAppQuery: EnumerableEntityQuery, EntityStringQuery {
    func allEntities() async throws -> [LCGuestApp] {
        await MainActor.run { LCGuestAppCatalog.entities() }
    }

    func entities(for identifiers: [String]) async throws -> [LCGuestApp] {
        let ids = Set(identifiers)
        return await MainActor.run { LCGuestAppCatalog.entities(withIDs: ids) }
    }

    func entities(matching string: String) async throws -> [LCGuestApp] {
        let needle = string.lcFolded
        guard !needle.isEmpty else { return try await allEntities() }

        // Rank prefix matches above substring matches so typing "tik" puts
        // TikTok first rather than something that merely contains "tik".
        // searchTerms always contains the folded display name, so the name does
        // not need checking separately except for the exact case.
        var exact: [LCGuestApp] = []
        var prefix: [LCGuestApp] = []
        var contains: [LCGuestApp] = []

        for app in try await allEntities() {
            if app.displayName.lcFolded == needle {
                exact.append(app)
            } else if app.searchTerms.contains(where: { $0.hasPrefix(needle) }) {
                prefix.append(app)
            } else if app.searchTerms.contains(where: { $0.contains(needle) }) {
                contains.append(app)
            }
        }
        return exact + prefix + contains
    }
}
