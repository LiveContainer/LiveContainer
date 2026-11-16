import Foundation

/// Whether a button press with no shell input behind it is iPadOS's echo of a controller button. iPadOS also takes a
/// controller's A as a press on a button of its own choosing (Play in portrait, the middle cover in landscape, a close
/// button, a switch), about 25 ms after A comes up, past the shell's own input. Such a press counts as the echo when no
/// finger came down since the last controller button, and that button is still held (up to `heldLimit`) or went down or
/// came up less than `span` ago. A button still held counts because the shell hears of a button coming up through a
/// SwiftUI update, and the system's press can come before it: with A held longer than `span`, the window of A going down
/// was over and the press got through.
///
/// Times are seconds of a monotonic clock (`ProcessInfo.systemUptime`), which a time change or a network time sync does
/// not move. A time before the last controller button (a clock that went back) is never the echo.
struct SystemEchoWindow: Equatable {
    static let span: TimeInterval = 1
    /// A button held longer than this is taken for one whose coming up was lost (a controller that went away).
    static let heldLimit: TimeInterval = 30
    /// When a controller button last went down or came up.
    private(set) var controllerAt: TimeInterval?
    /// How many controller buttons are down.
    private(set) var held = 0
    /// When a finger last came down anywhere on the screen.
    private(set) var touchAt: TimeInterval?

    /// A controller button went down.
    mutating func buttonDown(at time: TimeInterval) { controllerAt = time; held += 1 }
    /// A controller button came up. The echo comes after this, so the window starts again here.
    mutating func buttonUp(at time: TimeInterval) { controllerAt = time; held = max(0, held - 1) }
    mutating func touch(at time: TimeInterval) { touchAt = time }

    func isEcho(at now: TimeInterval) -> Bool {
        guard let controllerAt else { return false }
        let elapsed = now - controllerAt
        guard elapsed >= 0 else { return false }
        if let touchAt, touchAt >= controllerAt { return false }
        return elapsed < (held > 0 ? Self.heldLimit : Self.span)
    }
}

/// Marks the actions a controller or key press causes, so they are not taken for touch, and keeps the window for the
/// system's echo of a controller button. Not observed.
@MainActor final class InputGate {
    /// The echo is iPadOS's: a Mac sends none, and a click there has no probe to end the window.
    static let platformEchoes: Bool = {
        #if os(iOS)
        true
        #else
        false
        #endif
    }()
    /// True while `handle` acts on a controller or key press.
    var handling = false
    private var window = SystemEchoWindow()
    private let clock: () -> TimeInterval
    private let echoes: Bool

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, echoes: Bool = InputGate.platformEchoes) {
        self.clock = clock
        self.echoes = echoes
    }

    /// A controller action came in. Only buttons count: the system's press follows a button (A), and a direction
    /// repeats while held, which would end a finger's tap that began before it.
    func controller(_ action: ShellInput.Action) {
        if !Self.isDirection(action) { window.buttonDown(at: clock()) }
    }
    /// A controller button or direction came up.
    func controllerUp(_ action: ShellInput.Action) {
        if !Self.isDirection(action) { window.buttonUp(at: clock()) }
    }
    private static func isDirection(_ action: ShellInput.Action) -> Bool {
        switch action {
        case .up, .down, .left, .right: true
        default: false
        }
    }
    func touch() { window.touch(at: clock()) }
    /// A press acted on now, outside `handle`, is the system's echo of a controller button.
    var isSystemEcho: Bool { echoes && !handling && window.isEcho(at: clock()) }
}

/// What sits on top of the library and owns the D-pad, the topmost first. Each one's focus targets start with its
/// prefix; the library's own targets start with `FocusLayer.libraryPrefix`.
enum FocusLayer: CaseIterable {
    case buttonTest, padMapping, choice, touchLayout, controllers, shellSettings, help, delete, settings

    static let libraryPrefix = "lib."

    var prefix: String {
        switch self {
        case .buttonTest: "test."
        case .padMapping: "map."
        case .choice: "pick."
        case .touchLayout: "lay."
        case .controllers: "ctl."
        case .shellSettings: "shs."
        case .help: "help."
        case .delete: "del."
        case .settings: "set."
        }
    }

    /// Whether the library acts on a press of one of its own buttons: one from the shell's input always, any other only
    /// with nothing over the library. Under a dialog or a panel the library takes no hits, so no finger made that press.
    static func libraryTakesPress(fromShell: Bool, under top: FocusLayer?) -> Bool { fromShell || top == nil }

    /// Whether the D-pad reaches target `id` with `top` open (nil: nothing over the library).
    static func isLive(_ id: String, under top: FocusLayer?) -> Bool {
        if let top { return id.hasPrefix(top.prefix) }
        return !allCases.contains { id.hasPrefix($0.prefix) }
    }
}
