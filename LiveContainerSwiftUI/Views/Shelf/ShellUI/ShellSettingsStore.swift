import Foundation

/// The shell-level settings, one suite shared by every game: the game-data folder, the cloud-saves folder,
/// the default performance HUD and the touch controls. A game's own settings and bookmarks win over these, and
/// these win over the built-in defaults (ShellSettingsStore priority: game > shell > built-in).
public final class ShellSettingsStore: @unchecked Sendable {
    public static let padMapKey = "padMap"
    public static let suiteName = "shell-settings"
    public static let dataFolderKey = "globalDataBookmark"
    public static let cloudSavesKey = "globalCloudSavesBookmark"
    /// The performance overlay: one switch for every game, the same one as the in-game gear menu (ios/vpad.m, ios/hud.m read
    /// S2APerfHUD from the app's defaults). The shell's own key was never read by anything and is gone.
    public static let performanceHUDKey = "S2APerfHUD"
    static let retiredPerformanceHUDKey = "performanceHUD"
    public static let dataFolderNameKey = "globalDataFolderName"
    public static let cloudSavesNameKey = "globalCloudSavesFolderName"
    public static let touchSizeKey = "touchSize"                 // small, medium or large: DM_TOUCH_SIZE for every game
    /// The touch controls' sizes, as the engine reads DM_TOUCH_SIZE. Medium is the built-in size and is never stored.
    public static let touchSizes = ["small", "medium", "large"]
    public static let touchStickKey = "touchStick"               // corner, higher or inward: DM_TOUCH_STICK for every game
    /// Where the left stick sits, as the engine reads DM_TOUCH_STICK. The corner is the built-in place and is never stored.
    public static let touchStickPlaces = ["corner", "higher", "inward"]
    public static let touchLayoutKey = "touchLayout"             // the player's arrangement: DM_TOUCH_LAYOUT for every game
    /// Game sound in Silent Mode: the same key as the system Settings app's S2Arm page (ios/Settings.bundle), read by ios/app.m
    /// audio_category_apply from the app's defaults (Playback when on, SoloAmbient when off).
    public static let playInSilentModeKey = "S2APlayInSilentMode"
    /// S2Arm: 与其他 App 混音（宿主 ios/app.m audio_choice 读同一个键）；原只在系统设置 App 的 S2Arm 页（11-14 挪进游戏库设置）
    public static let mixWithOthersKey = "S2AMixWithOthers"
    public static let liquidGlassKey = "liquidGlass"             // true/false; Liquid Glass on the floating surfaces, on unless turned off

    /// The store the app reads and writes. Tests and previews swap it.
    nonisolated(unsafe) public static var current = ShellSettingsStore()

    /// The suite itself, so the host keeps the folder bookmarks in it with its `BookmarkStore`.
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = UserDefaults(suiteName: ShellSettingsStore.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    public var dataBookmark: Data? { defaults.data(forKey: Self.dataFolderKey) }
    public var cloudSavesBookmark: Data? { defaults.data(forKey: Self.cloudSavesKey) }
    /// The folders' names for the page, written by the host when the player picks them.
    public var dataFolderName: String? { defaults.string(forKey: Self.dataFolderNameKey) }
    public var cloudSavesFolderName: String? { defaults.string(forKey: Self.cloudSavesNameKey) }
    public var performanceHUD: Bool { UserDefaults.standard.bool(forKey: Self.performanceHUDKey) }
    public var playInSilentMode: Bool { UserDefaults.standard.bool(forKey: Self.playInSilentModeKey) }
    public var mixWithOthers: Bool { UserDefaults.standard.bool(forKey: Self.mixWithOthersKey) }

    public func storeDataFolderName(_ name: String) { defaults.set(name, forKey: Self.dataFolderNameKey) }
    public func storeCloudSavesFolderName(_ name: String) { defaults.set(name, forKey: Self.cloudSavesNameKey) }
    public func clearDataFolderName() { defaults.removeObject(forKey: Self.dataFolderNameKey) }
    public func clearCloudSavesFolderName() { defaults.removeObject(forKey: Self.cloudSavesNameKey) }
    public func storePlayInSilentMode(_ on: Bool) { UserDefaults.standard.set(on, forKey: Self.playInSilentModeKey) }
    public func storeMixWithOthers(_ on: Bool) { UserDefaults.standard.set(on, forKey: Self.mixWithOthersKey) }
    public func storePerformanceHUD(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.performanceHUDKey)
        defaults.removeObject(forKey: Self.retiredPerformanceHUDKey)
    }

    /// The touch controls' size for every game: small, medium (the built-in size) or large.
    public var touchSize: String {
        let value = defaults.string(forKey: Self.touchSizeKey) ?? "medium"
        return Self.touchSizes.contains(value) ? value : "medium"
    }
    public func storeTouchSize(_ size: String) {
        guard Self.touchSizes.contains(size) else { return }
        if size == "medium" { defaults.removeObject(forKey: Self.touchSizeKey) } else { defaults.set(size, forKey: Self.touchSizeKey) }
    }

    /// Where the left stick sits in every game: in the corner (the built-in place), higher, or further in.
    public var touchStick: String {
        let value = defaults.string(forKey: Self.touchStickKey) ?? "corner"
        return Self.touchStickPlaces.contains(value) ? value : "corner"
    }
    public func storeTouchStick(_ place: String) {
        guard Self.touchStickPlaces.contains(place) else { return }
        if place == "corner" { defaults.removeObject(forKey: Self.touchStickKey) } else { defaults.set(place, forKey: Self.touchStickKey) }
    }

    /// The player's arrangement of the touch controls for every game (#414): stored as the value the engine reads, so what the
    /// settings show is what a game gets. A stored value the engine would ignore reads as the built-in layout.
    public var touchLayout: TouchLayout {
        defaults.string(forKey: Self.touchLayoutKey).flatMap { TouchLayout(encoded: $0) } ?? TouchLayout()
    }
    public func storeTouchLayout(_ layout: TouchLayout) {
        if layout.isEmpty { defaults.removeObject(forKey: Self.touchLayoutKey) } else { defaults.set(layout.encoded, forKey: Self.touchLayoutKey) }
    }
    /// Every control of one layout back to its built-in place.
    public func resetTouchLayout(_ kind: TouchLayout.Kind) {
        var layout = touchLayout
        layout.reset(kind)
        storeTouchLayout(layout)
    }

    /// Liquid Glass on the floating chips and the primary pill where the OS offers it (iOS 26 / macOS 26);
    /// on unless the player turns it off, and never stored while on.
    public var liquidGlass: Bool { defaults.object(forKey: Self.liquidGlassKey) as? Bool ?? true }
    public func storeLiquidGlass(_ on: Bool) {
        if on { defaults.removeObject(forKey: Self.liquidGlassKey) } else { defaults.set(false, forKey: Self.liquidGlassKey) }
    }

    public var padMap: PadMap { PadMap(defaults.dictionary(forKey: Self.padMapKey) as? [String: String] ?? [:]) }
    public func setPadButton(_ button: String, to output: String) {
        var map = padMap
        map.set(button, to: output)
        defaults.set(map.entries, forKey: Self.padMapKey)
    }
    public func setPadSwapAB(_ on: Bool) {
        var map = padMap
        map.setSwapAB(on)
        defaults.set(map.entries, forKey: Self.padMapKey)
    }
    public func resetPadMap() { defaults.removeObject(forKey: Self.padMapKey) }

    /// DM_PAD_MAP is deliberately excluded. The host merges it per button at launch.
    /// The shell's value for each `DM_*` switch a game's own settings leave alone.
    public var gameDefaults: [String: String] {
        var values: [String: String] = [:]
        if touchSize != "medium" { values["DM_TOUCH_SIZE"] = touchSize }
        if touchStick != "corner" { values["DM_TOUCH_STICK"] = touchStick }
        let layout = touchLayout.encoded
        if !layout.isEmpty { values["DM_TOUCH_LAYOUT"] = layout }
        return values
    }
}
