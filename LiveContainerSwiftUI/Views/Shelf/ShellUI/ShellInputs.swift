// S2Arm modification: expose the host callback for persistent game reordering.
import Foundation
import CoreGraphics

/// The caller supplies display data. These types never load, validate, or store game data.
public enum GameState: Equatable, Sendable {
    case playable
    case needsGameData
    case needsAppUpdate
    /// `reason` is one short line for under the title, such as "Game files damaged". `detail` is a plain sentence
    /// for the player (what happened, what to do), shown under the title and in the How to fix sheet. `technical`
    /// is the underlying message, shown only as small secondary Details in the sheet.
    case broken(reason: String, detail: String = "", technical: String = "")
    /// On its way from the computer: copied over the cable, then unpacked here. Its cover is greyed until it can be played.
    case installing(InstallStage)
}

/// Where an arriving game is. `fraction` (0...1) is how far this phase has got; nil when it is not known yet.
public struct InstallStage: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Being copied from the computer: the cable must stay connected.
        case transferring
        /// Copied; being unpacked on this device.
        case installing
        /// The copying stopped part way, such as when the cable came out. Connecting the computer again continues it.
        case interrupted
        /// The unpacking did not finish. Play tries it again.
        case failed
    }
    public var phase: Phase
    public var fraction: Double?
    /// While installing, which part is under way (single-file game data): 1 unpacking what was sent, 2 taking the small files
    /// out of the game data file, 3 checking the files on this device; 4 waiting for another game to finish installing, 5 the host is
    /// organizing the game folders (S2Arm). 0: not told, shown as plain Installing.
    public var step: Int
    /// Why the install did not finish, in one plain sentence from the host; nil: the general explanation.
    public var reason: String?
    public init(_ phase: Phase, fraction: Double? = nil, step: Int = 0, reason: String? = nil) {
        self.phase = phase; self.fraction = fraction.map { min(1, max(0, $0)) }; self.step = step; self.reason = reason
    }
}

public struct GameTile: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// One short line under the title, such as the version.
    public var subtitle: String
    /// The game's 16:9 key art, such as its eShop banner. Covers, Cover Flow cards and the hero all use it.
    public var banner: Artwork?
    /// The square NACP icon. Only a fallback without a banner: shown whole inside a 16:9 card, never stretched.
    public var icon: Artwork?
    public var state: GameState
    /// Already localized, such as "Played today". Nil leaves the game out of Recently played.
    public var recentlyPlayed: String?
    /// Installed (or updated) and not opened since: a blue dot before its name, as iOS marks a new app.
    public var isNew: Bool
    /// S-grade enhancements are built into this game (community patches / cheats in its cpatch.tsv): the cover lights a gold S (v0.4.0).
    public var sgrade: Bool
    public init(id: String, title: String, subtitle: String = "", banner: Artwork? = nil, icon: Artwork? = nil,
                state: GameState = .playable, recentlyPlayed: String? = nil, isNew: Bool = false, sgrade: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.banner = banner
        self.icon = icon
        self.state = state
        self.recentlyPlayed = recentlyPlayed
        self.isNew = isNew
        self.sgrade = sgrade
    }
}

public struct SettingOption: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    /// The label is a text of the game's launcher.json: it is shown in the player's language when the catalog has it.
    public init(_ value: String, _ label: String) { self.init(value, label, in: ShellStrings.bundle) }
    init(_ value: String, _ label: String, in bundle: Bundle) { id = value; self.label = ShellStrings.setting(label, bundle: bundle) }
}

public enum SettingKind: Equatable, Sendable {
    case toggle(on: String, off: String)
    case choice([SettingOption])
    case range(min: Double, max: Double, step: Double, unit: String)
}

public struct SettingRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var note: String
    public var kind: SettingKind
    public var value: String
    /// The caller resolves dependencies and locks before supplying rows.
    public var enabled: Bool
    /// The value is the shell settings' choice, because the game has none of its own.
    public var fromShell: Bool
    /// Label and note are texts of the game's launcher.json: shown in the player's language when the catalog has them.
    public init(id: String, label: String, note: String = "", kind: SettingKind, value: String, enabled: Bool = true, fromShell: Bool = false) {
        self.init(id: id, label: label, note: note, kind: kind, value: value, enabled: enabled, fromShell: fromShell, in: ShellStrings.bundle)
    }
    init(id: String, label: String, note: String = "", kind: SettingKind, value: String, enabled: Bool = true, fromShell: Bool = false, in bundle: Bundle) {
        self.id = id
        self.label = ShellStrings.setting(label, bundle: bundle)
        self.note = ShellStrings.setting(note, bundle: bundle)
        self.kind = kind
        self.value = value
        self.enabled = enabled
        self.fromShell = fromShell
    }
}

public struct SettingSection: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var rows: [SettingRow]
    /// The id stays the section's name in launcher.json, the title is that name in the player's language when the catalog has it.
    public init(id: String, title: String, rows: [SettingRow]) { self.init(id: id, title: title, rows: rows, in: ShellStrings.bundle) }
    init(id: String, title: String, rows: [SettingRow], in bundle: Bundle) {
        self.id = id
        self.title = ShellStrings.setting(title, bundle: bundle)
        self.rows = rows
    }
}

public struct GameDetail: Identifiable, Equatable, Sendable {
    public var id: String { game.id }
    public var game: GameTile
    public var sections: [SettingSection]
    public var dataSource: String
    public var dataNote: String
    public var cloudSaves: String?
    public var cloudNote: String
    public var dlc: String
    public var hasModifiedSettings: Bool
    /// The data or cloud-saves folder is the shell settings' one, not one the player picked for this game.
    public var dataFromShell: Bool
    public var cloudFromShell: Bool
    /// The shell settings have a cloud-saves folder this game does not use now, so the game can follow it.
    public var cloudCanUseShell: Bool
    public init(game: GameTile, sections: [SettingSection] = [], dataSource: String = "", dataNote: String = "",
                cloudSaves: String? = nil, cloudNote: String = "", dlc: String = "", hasModifiedSettings: Bool = false,
                dataFromShell: Bool = false, cloudFromShell: Bool = false, cloudCanUseShell: Bool = false) {
        self.game = game
        self.sections = sections
        self.dataSource = dataSource
        self.dataNote = dataNote
        self.cloudSaves = cloudSaves
        self.cloudNote = cloudNote
        self.dlc = dlc
        self.hasModifiedSettings = hasModifiedSettings
        self.dataFromShell = dataFromShell
        self.cloudFromShell = cloudFromShell
        self.cloudCanUseShell = cloudCanUseShell
    }
}

public struct ControllerInfo: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var player: String
    /// Nil means the controller does not report battery level.
    public var batteryPercent: Int?
    public var charging: Bool
    public init(id: String, name: String, player: String, batteryPercent: Int? = nil, charging: Bool = false) {
        self.id = id
        self.name = name
        self.player = player
        self.batteryPercent = batteryPercent
        self.charging = charging
    }
}

/// Which kind of controller a family of glyphs belongs to, from GameController's `productCategory`.
/// The buttons are read by label, as on the Mac: GameController's buttonA is the cross on a PlayStation controller,
/// A at the bottom on an Xbox controller and A on the right on a Nintendo controller, so each confirms with its own.
public enum ControllerFamily: Equatable, Sendable {
    case xbox, playStation, nintendo, neutral
    public init(productCategory: String?) {
        let c = (productCategory ?? "").lowercased().replacingOccurrences(of: "-", with: "")
        if c.contains("dual") || c.contains("playstation") { self = .playStation }
        else if c.contains("xbox") { self = .xbox }
        else if c.contains("nintendo") || c.contains("switch") || c.contains("joycon") { self = .nintendo }
        else { self = .neutral }
    }
}

/// What sent the last input, so the hints show that device's own glyphs.
public enum InputDevice: Equatable, Sendable {
    case controller(ControllerFamily)
    case keyboard
}

/// One event from the host's input adapter: a press, or a button or direction let go. `sequence` orders them.
public struct ShellInput: Equatable, Sendable {
    public enum Action: Sendable { case up, down, left, right, activate, back, settings, controllers }
    public var sequence: Int
    public var action: Action
    public var device: InputDevice
    /// The button or direction of `action` came up. Nothing acts on it; it only restarts the window for the system's
    /// echo of a controller button (`SystemEchoWindow`).
    public var released: Bool
    public init(sequence: Int, action: Action, device: InputDevice = .controller(.neutral), released: Bool = false) {
        self.sequence = sequence
        self.action = action
        self.device = device
        self.released = released
    }
}

/// The host's input events in order, the last `kept` of them. The host appends each press and release; the library acts
/// on every event it has not seen yet. One value would keep only the last event written between two view updates, so a
/// press could be lost, or a release, which left a button counted as held (`SystemEchoWindow`).
public struct ShellInputLog: Equatable, Sendable {
    public static let kept = 64
    public private(set) var events: [ShellInput] = []
    public init() {}
    /// The sequence of the last event, 0 with none yet.
    public var last: Int { events.last?.sequence ?? 0 }
    public mutating func append(_ action: ShellInput.Action, device: InputDevice = .controller(.neutral), released: Bool = false) {
        events.append(ShellInput(sequence: last + 1, action: action, device: device, released: released))
        if events.count > Self.kept { events.removeFirst(events.count - Self.kept) }
    }
    /// The events after `sequence`, oldest first.
    public func since(_ sequence: Int) -> [ShellInput] { events.filter { $0.sequence > sequence } }
}

/// A controller element the button test lights up, named by its place on an Xbox controller (GameController's names).
public enum PadElement: String, CaseIterable, Sendable {
    case a, b, x, y, leftBumper, rightBumper, leftTrigger, rightTrigger, leftStick, rightStick, view, menu, home, up, down, left, right
}

/// A controller's whole state for the button test: what is held, the sticks from -1 to 1 (up is positive) and the
/// triggers from 0 to 1. The host sends it only while the test is open.
public struct PadSnapshot: Equatable, Sendable {
    public var name: String
    public var pressed: Set<PadElement>
    public var leftStick: CGPoint
    public var rightStick: CGPoint
    public var leftTrigger: Double
    public var rightTrigger: Double
    public init(name: String = "", pressed: Set<PadElement> = [], leftStick: CGPoint = .zero, rightStick: CGPoint = .zero,
                leftTrigger: Double = 0, rightTrigger: Double = 0) {
        self.name = name
        self.pressed = pressed
        self.leftStick = leftStick
        self.rightStick = rightStick
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
    }
}

/// All effects leave the package through these closures. The game ID is always explicit.
/// An optional closure the host leaves nil has no handler: the button for it is not shown, so nothing on screen does nothing.
public struct ShellActions {
    /// Inserts the dragged games before an ID, or at the end when the destination is nil.
    public var onReorderGames: (([String], String?) -> Bool)? = nil
    public var onSelect: (String) -> Void
    public var onPlay: (String) -> Void
    public var onChange: (_ gameID: String, _ settingID: String, _ value: String) -> Void
    public var onPickGameData: (String) -> Void
    public var onUseAppData: ((String) -> Void)?
    public var onPickCloudSaves: ((String) -> Void)?
    public var onDisableCloudSaves: ((String) -> Void)?
    public var onResetDefaults: ((String) -> Void)?
    public var onShowLog: ((String) -> Void)?
    public var onAppUpdate: (() -> Void)?
    public var onBack: () -> Void
    public var onPickShellData: (() -> Void)?
    public var onPickShellCloud: (() -> Void)?
    public var onUseShellCloud: ((String) -> Void)?
    public var onClearShellData: (() -> Void)?
    public var onClearShellCloud: (() -> Void)?
    /// S2Arm: settings → "Report a problem" (the host packs the logs, uploads them and shows a short code). Nil hides the row.
    public var onReportProblem: (() -> Void)?
    public var onGlobalPadMapChange: ((String, String) -> Void)?
    public var onGlobalPadMapReset: (() -> Void)?
    /// The button test opened (true) or closed: the host sends `PadSnapshot`s only in between.
    public var onButtonTest: (Bool) -> Void
    /// Deletes the game's data on this device and takes it off the list. `saves`: its saves go too.
    public var onDeleteGame: ((_ gameID: String, _ saves: Bool) -> Void)?
    /// Opens the game's save management (export / import saves) before it starts. nil: no item in the card's menu.
    public var onManageSaves: ((_ gameID: String) -> Void)?
    public init(onSelect: @escaping (String) -> Void = { _ in }, onPlay: @escaping (String) -> Void = { _ in },
                onChange: @escaping (String, String, String) -> Void = { _, _, _ in },
                onPickGameData: @escaping (String) -> Void = { _ in }, onUseAppData: ((String) -> Void)? = nil,
                onPickCloudSaves: ((String) -> Void)? = nil, onDisableCloudSaves: ((String) -> Void)? = nil,
                onResetDefaults: ((String) -> Void)? = nil, onShowLog: ((String) -> Void)? = nil,
                onAppUpdate: (() -> Void)? = nil, onBack: @escaping () -> Void = {},
                onPickShellData: (() -> Void)? = nil, onPickShellCloud: (() -> Void)? = nil,
                onUseShellCloud: ((String) -> Void)? = nil, onClearShellData: (() -> Void)? = nil,
                onClearShellCloud: (() -> Void)? = nil,
                onGlobalPadMapChange: ((String, String) -> Void)? = nil,
                onGlobalPadMapReset: (() -> Void)? = nil, onButtonTest: @escaping (Bool) -> Void = { _ in },
                onDeleteGame: ((String, Bool) -> Void)? = nil, onManageSaves: ((String) -> Void)? = nil) {
        self.onSelect = onSelect
        self.onPlay = onPlay
        self.onChange = onChange
        self.onPickGameData = onPickGameData
        self.onUseAppData = onUseAppData
        self.onPickCloudSaves = onPickCloudSaves
        self.onDisableCloudSaves = onDisableCloudSaves
        self.onResetDefaults = onResetDefaults
        self.onShowLog = onShowLog
        self.onAppUpdate = onAppUpdate
        self.onBack = onBack
        self.onPickShellData = onPickShellData
        self.onPickShellCloud = onPickShellCloud
        self.onUseShellCloud = onUseShellCloud
        self.onClearShellData = onClearShellData
        self.onClearShellCloud = onClearShellCloud
        self.onGlobalPadMapChange = onGlobalPadMapChange
        self.onGlobalPadMapReset = onGlobalPadMapReset
        self.onButtonTest = onButtonTest
        self.onDeleteGame = onDeleteGame
        self.onManageSaves = onManageSaves
    }
}
