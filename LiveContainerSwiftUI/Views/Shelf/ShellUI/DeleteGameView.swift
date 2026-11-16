import SwiftUI

/// The question before a game is deleted (#559), drawn like the How to fix card so a controller can answer it too. It names
/// what goes away, keeps the saves unless the player turns on the switch, and starts on Cancel. The Mac launcher asks the same
/// question with the same words.
struct DeleteGameView: View {
    let game: GameTile
    @Binding var saves: Bool
    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ShellStrings.text("Delete “\(game.title)”?")).shellType(ShellType.pageTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("delete.title")
            Text(ShellStrings.text("The game’s data on this device is deleted and the game leaves the list. A folder you chose yourself is not touched. Send the game data from your Mac again to bring it back."))
                .shellText(15).foregroundStyle(.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $saves) { Text(ShellStrings.text("Also delete saves")).shellText(15, .semibold) }
                    .toggleStyle(CreamToggleStyle())
                    .accessibilityIdentifier("delete.saves")
                    .shellTarget("del.saves") { saves.toggle() }
                Text(saves ? ShellStrings.text("Saves are deleted too and cannot be brought back.")
                           : ShellStrings.text("Saves stay unless you choose to delete them too."))
                    .shellText(12.5).foregroundStyle(saves ? DeleteStyle.red : .white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
            VStack(spacing: 10) {
                Button(action: delete) {
                    Text(saves ? ShellStrings.text("Delete game and saves") : ShellStrings.text("Delete game")).frame(maxWidth: .infinity)
                }
                .buttonStyle(DeletePillStyle())
                .accessibilityIdentifier("delete.confirm")
                .shellTarget("del.confirm", radius: 25, action: delete)
                Button(action: cancel) { Text(ShellStrings.text("Cancel")).frame(maxWidth: .infinity) }
                    .buttonStyle(ShellButtonStyle(fills: true))
                    .accessibilityIdentifier("delete.cancel")
                    .shellTarget("del.cancel", action: cancel)
            }.padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
    }
}

enum DeleteStyle {
    /// The red of a destructive action, the same as the Mac launcher's Manage menu.
    static let red = Color(red: 1, green: 0.42, blue: 0.40)
}

/// The destructive twin of `PrimaryPillStyle`: the same capsule in red with white type.
struct DeletePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.shellType(ShellType.primaryButton)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 26).frame(minHeight: 50)
            .foregroundStyle(.white)
            .background(Color(red: 0.86, green: 0.25, blue: 0.24), in: Capsule())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}

/// Asks before a game is deleted. The library provides it. Without one, game settings show no Delete button.
private struct ShellAskDeleteKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((GameTile) -> Void)? = nil
}
extension EnvironmentValues {
    var shellAskDelete: ((GameTile) -> Void)? {
        get { self[ShellAskDeleteKey.self] }
        set { self[ShellAskDeleteKey.self] = newValue }
    }
}

/// Opens a game's save management. The library provides it when the host has one. Without one, the card's menu has no
/// Manage saves… item.
private struct ShellManageSavesKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((String) -> Void)? = nil
}
extension EnvironmentValues {
    var shellManageSaves: ((String) -> Void)? {
        get { self[ShellManageSavesKey.self] }
        set { self[ShellManageSavesKey.self] = newValue }
    }
}
public extension Notification.Name {
    /// The host asks the library to open its own settings (the Home Screen quick action Settings).
    static let shellOpenSettings = Notification.Name("S2AShellOpenSettings")
}

/// Long press on a library card: a menu with the game's settings and, where the library allows it, Delete game…
/// (the same confirmation as the button at the bottom of the game's settings). Shared by the carousel and the portrait list.
struct GameTileMenu: ViewModifier {
    let detail: GameDetail
    let select: (String) -> Void
    let openSettings: () -> Void
    @Environment(\.shellAskDelete) private var askDelete
    @Environment(\.shellManageSaves) private var manageSaves
    func body(content: Content) -> some View {
        content.contextMenu {
            Button { select(detail.id); openSettings() } label: { Label(ShellStrings.text("Game settings"), systemImage: "slider.horizontal.3") }
            if let manageSaves {
                Button { manageSaves(detail.id) } label: { Label(ShellStrings.text("Manage saves…"), systemImage: "externaldrive") }
            }
            if let askDelete {
                Button(role: .destructive) { askDelete(detail.game) } label: { Label(ShellStrings.text("Delete game…"), systemImage: "trash") }
            }
        }
    }
}
