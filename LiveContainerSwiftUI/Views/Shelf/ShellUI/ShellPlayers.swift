// S2Arm addition (not in upstream): who is playing (#623), at the top of the library next to Controllers and Settings.
import SwiftUI

/// The player the next game starts as, and what opens the player list. The host sets it on the library; with none set
/// (upstream, the captures) no player chip is drawn.
public struct ShellPlayer: Equatable {
    public var name: String
    public var open: () -> Void
    public init(name: String, open: @escaping () -> Void) {
        self.name = name
        self.open = open
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
}

extension EnvironmentValues {
    @Entry public var shellPlayer: ShellPlayer? = nil
}

/// The current player's name on a chip: a tap opens the player list. Before Play the name says whose saves the game opens.
struct PlayerChip: View {
    /// In the side column (SideBar): the symbol over the name's first letters, as narrow as the gear.
    var vertical = false
    /// A tight top bar: a shorter name.
    var compact = false
    @Environment(\.shellPlayer) private var player
    var body: some View {
        if let player {
            Button(action: player.open) {
                if vertical {
                    VStack(spacing: 2) {
                        Image(systemName: "person.crop.circle")
                        Text(String(player.name.prefix(2))).shellText(11, .semibold).lineLimit(1)
                    }
                    .frame(width: SideBar.chipWidth - 28, height: SideBar.playerHeight)
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "person.crop.circle")
                        Text(player.name).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: compact ? 96 : 120)
                }
            }
            .buttonStyle(ChipButtonStyle())
            .accessibilityLabel(ShellStrings.text("Player") + ", " + player.name)
            .accessibilityHint(ShellStrings.text("Switch player"))
            .accessibilityIdentifier("player.open")
            .shellTarget("lib.player", radius: 22, action: player.open)
        }
    }
}
