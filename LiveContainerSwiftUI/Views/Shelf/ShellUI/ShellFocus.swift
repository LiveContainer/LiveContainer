import SwiftUI

/// Focus geometry and activation are transient UI state. Hardware belongs to the caller.
struct FocusTarget: Equatable {
    let id: String
    let frame: CGRect
    let activate: () -> Void
    // A new render can change an activation closure without changing its frame or ID.
    private let generation = UUID()
    init(id: String, frame: CGRect, activate: @escaping () -> Void) {
        self.id = id
        self.frame = frame
        self.activate = activate
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame && lhs.generation == rhs.generation
    }
}

/// A non-observed UI registry avoids feeding preference updates back into view rendering.
/// It holds only the latest focus geometry and actions, never game or settings state.
@MainActor final class FocusTargetBuffer {
    var values: [FocusTarget] = []
}
struct FocusTargets: PreferenceKey {
    static var defaultValue: [FocusTarget] { [] }
    static func reduce(value: inout [FocusTarget], nextValue: () -> [FocusTarget]) { value += nextValue() }
}
struct FocusAppearance: Equatable {
    var id: String?
    var visible = false
}
private struct FocusAppearanceKey: EnvironmentKey {
    static var defaultValue: FocusAppearance { FocusAppearance() }
}
private struct IgnoresPressKey: EnvironmentKey {
    static var defaultValue: () -> Bool { { false } }
}
extension EnvironmentValues {
    /// True while a press is the system's echo of a controller button, not a finger (see `LibraryView.noteTouch`). A
    /// control that moves at once on a press, before its value comes back, asks it first.
    var shellIgnoresPress: () -> Bool {
        get { self[IgnoresPressKey.self] }
        set { self[IgnoresPressKey.self] = newValue }
    }
    var shellFocus: FocusAppearance {
        get { self[FocusAppearanceKey.self] }
        set { self[FocusAppearanceKey.self] = newValue }
    }
}
struct ShellFocusTarget: ViewModifier {
    let id: String
    let enabled: Bool
    /// The ring follows the control's shape: 12 for covers and cards, a large value for capsules and circles.
    let radius: CGFloat
    let action: () -> Void
    @Environment(\.shellFocus) private var focus
    func body(content: Content) -> some View {
        content
            .overlay {
                if focus.visible && focus.id == id {
                    RoundedRectangle(cornerRadius: radius + 5).strokeBorder(ShellPalette.cream, lineWidth: 3)
                        .padding(-5).allowsHitTesting(false).accessibilityHidden(true)
                        // On and off at once: a ring fading in or out stays where it was while a panel slides, apart
                        // from its control.
                        .transition(.identity)
                }
            }
            .background {
                if enabled {
                    GeometryReader { geometry in
                        Color.clear.preference(key: FocusTargets.self, value: [
                            FocusTarget(id: id, frame: geometry.frame(in: .named("shell")), activate: action)
                        ])
                    }
                }
            }
            .id(id)
    }
}
extension View {
    func shellTarget(_ id: String, enabled: Bool = true, radius: CGFloat = 12, action: @escaping () -> Void) -> some View {
        modifier(ShellFocusTarget(id: id, enabled: enabled, radius: radius, action: action))
    }
}

/// Pure spatial focus selection shared by the UI and its navigation tests.
enum FocusNavigation {
    static func next(from id: String?, action: ShellInput.Action, targets: [FocusTarget]) -> String? {
        guard let origin = targets.first(where: { $0.id == id }) else { return targets.first?.id }
        let candidates = targets.filter { target in
            guard target.id != origin.id else { return false }
            let dx = target.frame.midX - origin.frame.midX
            let dy = target.frame.midY - origin.frame.midY
            switch action {
            case .left: return dx < -8
            case .right: return dx > 8
            case .up: return dy < -8
            case .down: return dy > 8
            default: return false
            }
        }
        func score(_ target: FocusTarget) -> CGFloat {
            let dx = abs(target.frame.midX - origin.frame.midX)
            let dy = abs(target.frame.midY - origin.frame.midY)
            switch action {
            case .left, .right: return dx + dy * 3
            default: return dy + dx * 3
            }
        }
        return candidates.min(by: { score($0) < score($1) })?.id ?? id
    }
}
