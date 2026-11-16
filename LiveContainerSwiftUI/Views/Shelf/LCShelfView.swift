//  LCShelfView.swift
//  S2Arm's Cover Flow / grid / column library (ShellUI.LibraryView) fed with LiveContainer's apps.
//  Landscape = Cover Flow, portrait = column or grid; ShellLayout decides from the size it is given, so it follows
//  iPhone Duo opening, closing and rotating. LibraryView also reserves iPhone Duo's side column itself (SideBar.swift).
import SwiftUI
import UIKit

@available(iOS 18.0, *)
@MainActor
private enum LCShelfArt {
    static var cache: [String: Artwork] = [:]
    static func artwork(id: String, app: LCAppModel) -> Artwork? {
        if let hit = cache[id] { return hit }
        guard let cg = app.appInfo.iconIsDarkIcon(false)?.cgImage else { return nil }
        let art = Artwork(id: id, image: cg)
        cache[id] = art
        return art
    }
}

@available(iOS 18.0, *)
struct LCShelfView: View {
    @EnvironmentObject private var sharedModel: SharedModel
    /// Shows LiveContainer's own tabs (Sources, Tweaks, Settings, the classic list) over the shelf.
    let openClassic: () -> Void

    @State private var errorShow = false
    @State private var errorInfo = ""

    var body: some View {
        LibraryView(games: games, actions: ShellActions(onPlay: { play($0) }))
            // S2Arm's "player" chip, reused as the way back to LiveContainer's own screens.
            .environment(\.shellPlayer, ShellPlayer(name: "LC", open: openClassic))
            .alert("lc.common.error".loc, isPresented: $errorShow) {
                Button("lc.common.ok".loc) {}
            } message: {
                Text(errorInfo)
            }
    }

    private static func id(_ app: LCAppModel) -> String {
        app.appInfo.relativeBundlePath ?? app.appInfo.bundleIdentifier() ?? ""
    }

    private var games: [GameDetail] {
        sharedModel.apps.map { app in
            let id = Self.id(app)
            var state = GameState.playable
            if app.isSigningInProgress {
                state = .installing(InstallStage(.installing, fraction: app.signProgress))
            }
            // LiveContainer only has square icons, so no 16:9 banner: ShellUI then shows the icon whole inside the
            // card and tints the card and backdrop from it, as in the S2Arm screenshot.
            let tile = GameTile(id: id, title: app.appInfo.displayName(), subtitle: app.appInfo.version() ?? "",
                                banner: nil, icon: LCShelfArt.artwork(id: id, app: app), state: state)
            return GameDetail(game: tile)
        }
    }

    private func play(_ id: String) {
        guard let app = sharedModel.apps.first(where: { Self.id($0) == id }) else { return }
        Task { @MainActor in
            do {
                if app.appInfo.isLocked && !DataManager.shared.model.isHiddenAppUnlocked {
                    guard try await LCUtils.authenticateUser() else { return }
                }
                try await app.runApp()
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
        }
    }
}
