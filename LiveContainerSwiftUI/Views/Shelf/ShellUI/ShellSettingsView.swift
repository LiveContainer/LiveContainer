import SwiftUI

/// The rows of the shell settings, in the game settings' own model so the same controls draw them. The game ID tells
/// the library that a change belongs to the shell and not to a game.
enum ShellSettingsRows {
    static let gameID = "shell"
    static let hud = "shell.hud"
    static let glass = "shell.glass"
    static let silent = "shell.silent"
    static let mix = "shell.mix"
    static let touchSize = "shell.touchSize"
    static let touchStick = "shell.touchStick"
    static let targetPrefix = "shs.row."

    /// Liquid Glass on the floating chips and the primary action, where the system offers it.
    static func glassRow(_ store: ShellSettingsStore) -> SettingRow {
        SettingRow(id: glass, label: ShellStrings.text("Liquid Glass"), note: ShellStrings.text("Glass on the floating buttons and the main action, on systems that offer it."),
                   kind: .toggle(on: "1", off: "0"), value: store.liquidGlass ? "1" : "0")
    }

    static func hudRow(_ store: ShellSettingsStore) -> SettingRow {
        SettingRow(id: hud, label: ShellStrings.text("Performance overlay"), note: ShellStrings.text("Shared by all games; you can also switch it in a game any time."),
                   kind: .toggle(on: "1", off: "0"), value: store.performanceHUD ? "1" : "0")
    }

    /// Game sound while the device is in Silent Mode, for every game (the same switch as the system Settings app's S2Arm page).
    static func silentRow(_ store: ShellSettingsStore) -> SettingRow {
        SettingRow(id: silent, label: ShellStrings.text("Play Sound in Silent Mode"),
                   note: ShellStrings.text("When on, game sound keeps playing while the device is in Silent Mode. When off, S2Arm follows Silent Mode like other games."),
                   kind: .toggle(on: "1", off: "0"), value: store.playInSilentMode ? "1" : "0")
    }

    /// S2Arm: other apps' audio keeps playing alongside the game (the system Settings app's S2Arm page had it; moved here 11-14).
    static func mixRow(_ store: ShellSettingsStore) -> SettingRow {
        SettingRow(id: mix, label: ShellStrings.text("Mix with Other Apps"),
                   note: ShellStrings.text("When on, music or podcasts from other apps keep playing with the game, and the Silent switch only mutes the game."),
                   kind: .toggle(on: "1", off: "0"), value: store.mixWithOthers ? "1" : "0")
    }

    /// The touch controls' size for every game. The preview above the row shows it.
    static func touchSizeRow(_ store: ShellSettingsStore) -> SettingRow {
        SettingRow(id: touchSize, label: ShellStrings.text("Size"),
                   kind: .choice([SettingOption("small", ShellStrings.text("Small")), SettingOption("medium", ShellStrings.text("Medium")),
                                  SettingOption("large", ShellStrings.text("Large"))]),
                   value: store.touchSize)
    }

    /// Where the left stick sits in every game. The buttons on the right keep their place.
    static func touchStickRow(_ store: ShellSettingsStore) -> SettingRow {
        SettingRow(id: touchStick, label: ShellStrings.text("Left stick"),
                   kind: .choice([SettingOption("corner", ShellStrings.text("Corner")), SettingOption("higher", ShellStrings.text("Higher")),
                                  SettingOption("inward", ShellStrings.text("Inward"))]),
                   value: store.touchStick)
    }

    /// Under the preview: the rows are for every game, and the engine keeps the controls apart on a screen too small for a
    /// choice. A note of its own, not the rows', so the segments keep the card's width.
    static var touchNote: String { ShellStrings.text("For every game. On a screen too small for a choice, the controls stay closer to where they were.") }

    /// A change of one of the rows, from the row itself or from the list of choices.
    static func apply(_ id: String, value: String, to store: ShellSettingsStore) {
        switch id {
        case hud: store.storePerformanceHUD(value == "1")
        case silent: store.storePlayInSilentMode(value == "1")
        case mix: store.storeMixWithOthers(value == "1")
        case glass: store.storeLiquidGlass(value == "1")
        case touchSize: store.storeTouchSize(value)
        case touchStick: store.storeTouchStick(value)
        default: break
        }
    }
}

/// The shell's own settings: the game-data folder, the cloud-saves folder, the touch controls and the default performance
/// overlay. A game's own choices win over these, and these win over the built-in defaults. It looks like a game's
/// settings and takes a controller the same way, as a panel over the library.
struct ShellSettingsView: View {
    var store: ShellSettingsStore = .current
    var actions: ShellActions
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellFocus) private var focus
    /// Counts the changes in the defaults, so the rows read the store again.
    @State private var revision = 0

    var body: some View {
        let _ = revision
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        HStack(alignment: .center) {
                            Text(ShellStrings.text("Settings")).shellType(ShellType.pageTitle)
                                .lineLimit(1).minimumScaleFactor(0.7).accessibilityAddTraits(.isHeader)
                            Spacer(minLength: 8)
                            Button(action: onClose) { Text(ShellStrings.text("Done")) }
                                .buttonStyle(ChipButtonStyle())
                                .accessibilityIdentifier("shellSettings.close")
                                .shellTarget("shs.close", radius: 22, action: onClose)
                        }.id("shs.top")
                        if let pickData = actions.onPickShellData {
                            SettingsGroup(title: ShellStrings.text("Game data")) {
                                SourceRow(symbol: "folder", title: store.dataFolderName ?? ShellStrings.text("No folder chosen"),
                                          note: ShellStrings.text("Games look for their data here. Keep one romfs.img per game in any folder inside. Each game is found by the image itself, so the folder names do not matter. Each game can also have a folder of its own.")) {
                                    Button(ShellStrings.text("Choose folder…")) { pickData() }
                                        .buttonStyle(ShellButtonStyle(fills: true)).accessibilityIdentifier("shellSettings.data")
                                        .shellTarget("shs.data") { pickData() }
                                    if let clearData = actions.onClearShellData, store.dataFolderName != nil {
                                        Button(ShellStrings.text("Remove")) { clearData() }
                                            .buttonStyle(ShellButtonStyle(fills: true)).accessibilityIdentifier("shellSettings.data.remove")
                                            .shellTarget("shs.data.remove") { clearData() }
                                    }
                                }
                            }
                        }
                        if let pickCloud = actions.onPickShellCloud {
                            SettingsGroup(title: ShellStrings.text("Cloud saves")) {
                                SourceRow(symbol: store.cloudSavesFolderName == nil ? "icloud.slash" : "icloud",
                                          title: store.cloudSavesFolderName ?? ShellStrings.text("Off"),
                                          note: ShellStrings.text("Games without a folder of their own save here. Choose the same iCloud Drive folder you use on your Mac.")) {
                                    Button(ShellStrings.text("Choose folder…")) { pickCloud() }
                                        .buttonStyle(ShellButtonStyle(fills: true)).accessibilityIdentifier("shellSettings.cloud")
                                        .shellTarget("shs.cloud") { pickCloud() }
                                    if let clearCloud = actions.onClearShellCloud, store.cloudSavesFolderName != nil {
                                        Button(ShellStrings.text("Turn off")) { clearCloud() }
                                            .buttonStyle(ShellButtonStyle(fills: true)).accessibilityIdentifier("shellSettings.cloud.off")
                                            .accessibilityLabel(ShellStrings.text("Turn off cloud saves"))
                                            .shellTarget("shs.cloud.off") { clearCloud() }
                                    }
                                }
                            }
                        }
                        // S2Arm: the upstream Touch controls group (size, stick, arrangement) is left out. The game reads its own
                        // per-game layout (each game's settings → button positions), never these shell settings (#372).
                        SettingsGroup(title: ShellStrings.text("Interface")) {
                            ForEach([ShellSettingsRows.glassRow(store), ShellSettingsRows.hudRow(store)]) { row in
                                SettingControl(gameID: ShellSettingsRows.gameID, row: row, targetPrefix: ShellSettingsRows.targetPrefix) {
                                    ShellSettingsRows.apply(row.id, value: $0, to: store)
                                }.equatable()
                            }
                        }
                        SettingsGroup(title: ShellStrings.text("Sound")) {
                            ForEach([ShellSettingsRows.silentRow(store), ShellSettingsRows.mixRow(store)]) { row in
                                SettingControl(gameID: ShellSettingsRows.gameID, row: row, targetPrefix: ShellSettingsRows.targetPrefix) {
                                    ShellSettingsRows.apply(row.id, value: $0, to: store)
                                }.equatable()
                            }
                        }
                        // S2Arm: at the bottom, "Report a problem" (the host asks for an optional sentence, then uploads the logs and shows a short code)
                        if let report = actions.onReportProblem {
                            SettingsGroup(title: ShellStrings.text("Report a problem")) {
                                SourceRow(symbol: "exclamationmark.bubble", title: ShellStrings.text("Report a problem"),
                                          note: ShellStrings.text("Sends this device's logs to the developers and gives you a short code. You can add a sentence about what happened.")) {
                                    Button(ShellStrings.text("Report…")) { report() }
                                        .buttonStyle(ShellButtonStyle(fills: true)).accessibilityIdentifier("shellSettings.report")
                                        .shellTarget("shs.report") { report() }
                                }
                            }
                        }
                        // S2Arm: the version, the same text the computer's S2Arm shows (written when the computer installs the app; ShellVersion).
                        if !ShellVersion.display.isEmpty {
                            Text(verbatim: "S2Arm " + ShellVersion.display).shellText(12.5).foregroundStyle(.white.opacity(0.45))
                                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
                                .accessibilityIdentifier("shellSettings.version")
                        }
                    }
                    .padding(24).padding(.bottom, geometry.safeAreaInsets.bottom).frame(maxWidth: 640)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                // The horizontal safe insets are positional for a trailing-edge overlay and must not be
                // spent a second time inside the page — see the note in ControllersView. Only the
                // horizontal pair is added; the top inset and the bottom handling stay as they are.
                .modifier(TrailingOverlaySafeArea())   // 横向不扣安全区；灵动岛转到右边时右侧照扣（SensorEdge.swift）
                .onChange(of: focus.id) { _, id in
                    guard let id, id.hasPrefix("shs.") else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        proxy.scrollTo(id == "shs.close" ? "shs.top" : id, anchor: id == "shs.close" ? .top : .center)
                    }
                }
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in revision += 1 }
    }
}
