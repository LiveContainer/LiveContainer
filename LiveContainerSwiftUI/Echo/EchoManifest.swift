//
//  EchoManifest.swift
//  Echo Launcher
//
//  The update manifest served by the Echo backend. See ECHO.md for the format.
//

import Foundation

struct EchoManifest: Codable {
    struct Game: Codable {
        var build: String
        var url: String
        var sha256: String
        var size: Int64?
    }
    struct RemoteFile: Codable {
        var url: String
        var sha256: String
    }
    struct ClientFile: Codable {
        var name: String
        var build: Int?
        var url: String
        var sha256: String
        /// nil = always used; otherwise only with that renderer ("echo" or "stock")
        var renderer: String?
    }
    struct Pak: Codable {
        var name: String
        var renderer: String?
        var pak: RemoteFile
        var sig: RemoteFile?
    }
    struct CommandLine: Codable {
        var all: [String]?
        var echo: [String]?
        var stock: [String]?
    }

    var version: Int
    var game: Game
    var client: [ClientFile]?
    var paks: [Pak]?
    var commandLine: CommandLine?
}

enum EchoRenderer: String, CaseIterable, Identifiable {
    case echo
    case stock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .echo: return "Echo (PC shaders)"
        case .stock: return "Stock"
        }
    }
}

enum EchoError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
