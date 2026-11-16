import SwiftUI
import CoreText

public enum ShellPalette {
    public static let background = Color(red: 0.055, green: 0.055, blue: 0.06)
    public static let surface = Color(red: 0.10, green: 0.10, blue: 0.11)
    public static let cream = Color(red: 1, green: 0.94, blue: 0.84)
    public static let ready = Color(red: 0.25, green: 0.84, blue: 0.47)
    public static let attention = Color(red: 1, green: 0.78, blue: 0.24)
    public static let muted = Color(red: 0.57, green: 0.58, blue: 0.61)
    /// Hairlines between rows and around cards.
    static let hairline = Color.white.opacity(0.08)
}

/// 宿主层（S2ArmShellHost 调整位置编辑页）取同一份 Localizable.xcstrings 的文字（S2Arm 改动，见 UPSTREAM.md）
public func shellText(_ key: String.LocalizationValue) -> String { ShellStrings.text(key) }

enum ShellStrings {
    /// Visual QA renders one language's `.lproj` whatever the Mac's language is. Nil in the app.
    nonisolated(unsafe) static var captureBundle: Bundle?
    static var bundle: Bundle { captureBundle ?? .module }
    static func text(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: bundle) }

    /// A text of a game's `launcher.json` (section, label, note, option label) in the player's language. The file is English and
    /// not ours to change, so the catalog is keyed by that English text. The key is used as it is (a `%` in a note is not a format).
    /// A text with no entry, and an empty one, stays as it is: the player reads English, never a key. `bundle` is a language's
    /// `.lproj` in tests.
    static func setting(_ text: String, bundle: Bundle = ShellStrings.bundle) -> String {
        text.isEmpty ? text : bundle.localizedString(forKey: text, value: text, table: nil)
    }
}

@MainActor public enum ShellFonts {
    /// Register just the bundled font. No game or user files are accessed.
    private static let registered: Bool = {
        guard let url = Bundle.module.url(forResource: "Manrope", withExtension: "ttf") else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        return (CTFontManagerCopyAvailablePostScriptNames() as? [String])?.contains("Manrope") == true
    }()
    /// Manrope that follows Dynamic Type.
    public static func font(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo: Font.TextStyle = .body) -> Font {
        if registered { return .custom("Manrope", size: size, relativeTo: relativeTo).weight(weight) }
        return .system(relativeTo).weight(weight)
    }
    /// Manrope at a fixed size, for lettering that belongs to a picture rather than to the interface.
    static func fixed(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if registered { return .custom("Manrope", fixedSize: size).weight(weight) }
        return .system(size: size, weight: weight)
    }
}

extension View {
    func shellText(_ size: CGFloat = 15, _ weight: Font.Weight = .regular, relativeTo: Font.TextStyle = .body) -> some View {
        font(ShellFonts.font(size, weight: weight, relativeTo: relativeTo))
    }
    /// A settings group: the surface colour with a 1 pt hairline, as on the Mac.
    func shellCard(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ShellPalette.hairline, lineWidth: 1))
    }
}

/// A text role: Manrope at a size and weight, scaled with Dynamic Type through its text style, and its tracking.
struct TypeRole {
    let size: CGFloat
    let weight: Font.Weight
    let style: Font.TextStyle
    var tracking: CGFloat = 0
}

/// The type scale, derived from the Mac launcher's (frontend/Sources): the same face from the same file,
/// the same weight for the same role, the same tracking for capitals, sizes adapted to iOS. Every role scales with
/// Dynamic Type through its text style.
///
/// | Role | Mac | iOS |
/// | --- | --- | --- |
/// | Hero title | heavy, up to 68, tracking -1.6 | heavy 32 (24 folded, 34 iPad), -0.024 per pt |
/// | Cover Flow title | console title, bold 36, -1.6 | bold 28 (20 on a phone on its side) |
/// | Page title (settings, controllers) | heavy 26, -0.6 | heavy 26, -0.6 |
/// | Section capitals | console label, semibold 14, tracking 2 | semibold 11.5, tracking 1.6 |
/// | Status eyebrow | bold 12, tracking 1.3 | bold 11.5, tracking 1.3 |
/// | Status | medium 13 | medium 12.5 |
/// | Card title | semibold 16 | semibold 14.5 |
/// | Setting label | medium 14 | medium 15 |
/// | Note | regular 12 | regular 12.5 |
/// | Meta line | regular 13 | regular 13 |
/// | Button | semibold 13 | semibold 14 |
/// | Primary button | bold 18 | bold 17 |
enum ShellType {
    static func heroTitle(_ size: CGFloat) -> TypeRole { TypeRole(size: size, weight: .heavy, style: .largeTitle, tracking: -size * 0.024) }
    static func flowTitle(_ size: CGFloat) -> TypeRole { TypeRole(size: size, weight: .bold, style: .title, tracking: -size * 0.04) }
    static let pageTitle = TypeRole(size: 26, weight: .heavy, style: .title, tracking: -0.6)
    static let sectionCaps = TypeRole(size: 11.5, weight: .semibold, style: .caption, tracking: 1.6)
    static let eyebrow = TypeRole(size: 11.5, weight: .bold, style: .caption, tracking: 1.3)
    static let status = TypeRole(size: 12.5, weight: .medium, style: .caption)
    static let cardTitle = TypeRole(size: 14.5, weight: .semibold, style: .subheadline)
    static let settingLabel = TypeRole(size: 15, weight: .medium, style: .body)
    static let note = TypeRole(size: 12.5, weight: .regular, style: .footnote)
    static let meta = TypeRole(size: 13, weight: .regular, style: .footnote)
    static let body = TypeRole(size: 14.5, weight: .regular, style: .body)
    static let button = TypeRole(size: 14, weight: .semibold, style: .body)
    static let primaryButton = TypeRole(size: 17, weight: .bold, style: .headline)
}

extension View {
    func shellType(_ role: TypeRole) -> some View {
        font(ShellFonts.font(role.size, weight: role.weight, relativeTo: role.style)).tracking(role.tracking)
    }
}

/// The small cream capitals that open a section, such as YOUR GAMES.
struct SectionHeading: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).shellType(ShellType.sectionCaps)
                .foregroundStyle(ShellPalette.cream.opacity(0.72)).accessibilityAddTraits(.isHeader)
            if let trailing {
                Spacer(minLength: 8)
                Text(trailing).shellText(12, .medium, relativeTo: .caption).monospacedDigit().foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

/// The Mac's secondary button: white 0.055, a 0.10 hairline, radius 9.
struct ShellButtonStyle: ButtonStyle {
    /// Take all the width offered, as the buttons inside a settings card do.
    var fills = false
    /// Red type for an action that removes something.
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.shellType(ShellType.button).lineLimit(1)
            .padding(.horizontal, 14).frame(maxWidth: fills ? .infinity : nil, minHeight: 44)
            .foregroundStyle(destructive ? DeleteStyle.red : .white.opacity(0.92))
            .background(.white.opacity(configuration.isPressed ? 0.13 : 0.055), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.10)))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

/// The one primary action of a screen: a cream capsule with black type, as the Mac hero's Play.
struct PrimaryPillStyle: ButtonStyle {
    var expands = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.shellType(ShellType.primaryButton)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 26).frame(minHeight: 50)
            .frame(maxWidth: expands ? .infinity : nil)
            .foregroundStyle(.black)
            .modifier(PrimarySurface())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}

/// The primary action's surface: on iOS 26 / macOS 26 with Liquid Glass on, the system's regular glass
/// tinted with the cream — the only tinted glass in the shell (GameCase #61's rule: tint for the one
/// primary action); everywhere else the plain cream capsule it has always been.
private struct PrimarySurface: ViewModifier {
    // S2Arm：开关值用 @AppStorage 绑同一个键，设置里一切换就重画（原先在 body 里直接读 store，切了要等别的原因重画才变）
    @AppStorage(ShellSettingsStore.liquidGlassKey, store: ShellSettingsStore.current.defaults) private var glass = true
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), glass {
            content.glassEffect(.regular.tint(ShellPalette.cream).interactive(), in: Capsule())
        } else {
            content.background(ShellPalette.cream, in: Capsule())
        }
    }
}

/// A round icon button beside the primary action, such as game settings.
struct RoundIconButtonStyle: ButtonStyle {
    var size: CGFloat = 50
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 17, weight: .medium))
            .frame(width: size, height: size)
            .foregroundStyle(active ? .black : .white)
            .background(active ? ShellPalette.cream : .white.opacity(configuration.isPressed ? 0.2 : 0.10), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(active ? 0 : 0.14)))
            .contentShape(Circle())
    }
}

/// A small capsule that sits on top of art, such as the controller count.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.shellText(13, .semibold, relativeTo: .footnote)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .foregroundStyle(.white)
            .modifier(ChipSurface(isPressed: configuration.isPressed))
            .environment(\.colorScheme, .dark)
            .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
            .contentShape(Capsule())
    }
}

/// The chip's own quiet backdrop: on iOS 26 / macOS 26 with Liquid Glass on, the system's regular glass
/// (GameCase #61's shape; no tint — a chip is never the primary action), interactive because the chip is
/// tappable — a plain `.regular` glass can latch its press state when the press restructures the view;
/// everywhere else the blur and dark tint it has always worn, so it stays legible on any art.
private struct ChipSurface: ViewModifier {
    let isPressed: Bool
    @AppStorage(ShellSettingsStore.liquidGlassKey, store: ShellSettingsStore.current.defaults) private var glass = true   // 同 PrimarySurface
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), glass {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(.black.opacity(isPressed ? 0.62 : 0.5)))
            }
        }
    }
}

struct CreamToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { CreamSwitch(configuration: configuration, isOn: configuration.isOn) }
}

/// The cream switch. The knob moves the moment it is tapped, with a short spring, from its own state. The new value
/// goes out without an animation, so the host's update does not animate the whole screen, and the knob follows the
/// value that comes back.
private struct CreamSwitch: View {
    let configuration: ToggleStyleConfiguration
    /// The value as a plain input: a change from elsewhere (a controller, the host) redraws the switch even though the
    /// configuration's binding looks the same.
    let isOn: Bool
    @State private var shown: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellIgnoresPress) private var ignoresPress
    var body: some View {
        let on = shown ?? isOn
        Button {
            // The system's echo of a controller button: no value goes out, so the knob must not move either.
            if ignoresPress() { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { shown = !on }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { configuration.isOn = !on }
        } label: {
            HStack(spacing: 16) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? ShellPalette.cream : .white.opacity(0.14))
                    Circle().fill(on ? ShellPalette.background : .white.opacity(0.85)).padding(3)
                }.frame(width: 46, height: 28)
                // A value from elsewhere (a controller's A) moves the knob as a tap does. A tap has moved it already.
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: on)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .onChange(of: isOn) { _, _ in shown = nil }
            .accessibilityValue(ShellStrings.text(on ? "On" : "Off"))
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A game's picture filling whatever frame it gets: the banner, else the icon whole on a blurred copy of itself,
/// else the placeholder.
struct ArtView: View {
    let game: GameTile
    /// Draw from the small copy, for a backdrop that is blurred anyway.
    var backdrop = false
    /// The placeholder's lettering. Off where the title is set beside the art already, as in the hero.
    var lettering = true
    var body: some View {
        Color.clear.overlay {
            if let banner = game.banner {
                Image(decorative: backdrop ? banner.thumbnail : banner.image, scale: 1)
                    .resizable().interpolation(backdrop ? .medium : .high).scaledToFill()
            } else if let icon = game.icon {
                if backdrop {
                    Image(decorative: icon.thumbnail, scale: 1).resizable().scaledToFill()
                } else {
                    IconCard(icon: icon)
                }
            } else {
                PlaceholderArt(title: game.title, seed: game.id, lettering: lettering && !backdrop)
            }
        }.clipped()
    }
}

/// A square icon in a wide frame: whole and sharp in the middle, on a blurred and darkened copy of itself.
private struct IconCard: View {
    let icon: Artwork
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.height * 0.74, geometry.size.width * 0.74)
            ZStack {
                Image(decorative: icon.thumbnail, scale: 1).resizable().interpolation(.medium).scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blur(radius: max(8, geometry.size.height * 0.14), opaque: true)
                    .saturation(1.15)
                    .overlay(Color.black.opacity(0.3))
                Image(decorative: icon.image, scale: 1).resizable().interpolation(.high).scaledToFit()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.1))
                    .shadow(color: .black.opacity(0.35), radius: side * 0.06, y: side * 0.03)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// For a game without a picture: a deep tone from its name, a soft disc and the title set like a book cover.
/// It has to read as a deliberate cover, not as missing data.
struct PlaceholderArt: View {
    let title: String
    let seed: String
    var lettering = true
    var body: some View {
        let hash = stableHash(seed)
        let hue = Double(hash % 360) / 360
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(hue: hue, saturation: 0.42, brightness: 0.36),
                                        Color(hue: hue, saturation: 0.55, brightness: 0.13)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                Circle().fill(Color(hue: hue, saturation: 0.30, brightness: 0.62).opacity(0.30))
                    .frame(width: side * 1.1, height: side * 1.1)
                    .position(x: geometry.size.width * 0.8, y: geometry.size.height * 0.22)
                if lettering {
                    Text(title).font(ShellFonts.fixed(max(9, side * 0.16), weight: .heavy)).tracking(-side * 0.004)
                        .foregroundStyle(ShellPalette.cream.opacity(0.92))
                        .lineLimit(2).minimumScaleFactor(0.5).multilineTextAlignment(.leading)
                        .padding(side * 0.11)
                }
            }
        }
    }
}

/// A 16:9 card with the hairline every picture gets, so dark art keeps its edge on the dark page. In the library it
/// carries the game's state as a small dot in its top-left corner.
struct CoverView: View {
    let game: GameTile
    var radius: CGFloat = 10
    var showsState = false
    var body: some View {
        ArtView(game: game)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { if case .installing(let stage) = game.state { InstallMask(stage: stage) } }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.10)))
            .overlay(alignment: .topLeading) {
                if showsState || game.sgrade {
                    GeometryReader { geometry in
                        let size = max(8, min(14, geometry.size.width * 0.034))
                        // 金色 S（v0.4.0）：这款打进了 S 级优化，放左上角；状态点跟在它右边
                        HStack(alignment: .center, spacing: size * 0.6) {
                            if game.sgrade { SGradeBadge(size: max(16, geometry.size.width * 0.085)) }
                            if showsState { StateDot(state: game.state, size: size) }
                        }
                        .padding(size * 0.9)
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

/// The blue dot iOS puts before a new app's name until it is first opened.
struct NewDot: View {
    var size: CGFloat = 9
    var body: some View { Circle().fill(Color(red: 0.04, green: 0.52, blue: 1)).frame(width: size, height: size).accessibilityHidden(true) }
}

extension GameTile {
    /// Ready and not opened since it was installed: says so once, under the name.
    var showsNewNote: Bool { isNew && state == .playable }
}

/// An arriving game's grey veil, as iOS draws an app being installed: the grey clears clockwise from twelve o'clock as
/// this phase gets on, and a stopped or failed install stays fully grey with a sign of what happened.
struct InstallMask: View {
    let stage: InstallStage
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                RemainingPie(done: stage.phase == .interrupted || stage.phase == .failed ? 0 : stage.fraction ?? 0)
                    .fill(Color.black.opacity(0.58))
                    .animation(.linear(duration: 0.9), value: stage.fraction)
                Circle().strokeBorder(.white.opacity(0.85), lineWidth: max(1.5, side * 0.02))
                    .frame(width: side * 0.34, height: side * 0.34)
                    .overlay {
                        switch stage.phase {
                        case .interrupted: Image(systemName: "pause.fill").font(.system(size: side * 0.12, weight: .bold))
                        case .failed: Image(systemName: "exclamationmark").font(.system(size: side * 0.13, weight: .heavy))
                        default: DonePie(fraction: stage.fraction ?? 0).fill(.white.opacity(0.85)).clipShape(Circle()).padding(side * 0.04)
                                     .animation(.linear(duration: 0.9), value: stage.fraction)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// The part of a full turn not yet done: a pie from `done` of the way round, clockwise from twelve o'clock, back to twelve.
/// Its radius reaches the corners, so whatever it covers is covered edge to edge.
struct RemainingPie: Shape {
    var done: Double
    var animatableData: Double { get { done } set { done = newValue } }
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = hypot(rect.width, rect.height) / 2
        let d = min(1, max(0, done))
        var p = Path()
        if d >= 1 { return p }
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: .degrees(-90 + 360 * d), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The part of a full turn done: clockwise from twelve o'clock.
struct DonePie: Shape {
    var fraction: Double
    var animatableData: Double { get { fraction } set { fraction = newValue } }
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = hypot(rect.width, rect.height) / 2
        let f = min(1, max(0, fraction))
        var p = Path()
        if f <= 0 { return p }
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * f), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The game's state as a dot: green ready, amber when it needs data or an update, grey when it is damaged. A dark
/// ring behind it keeps it readable on light art.
struct StateDot: View {
    let state: GameState
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(state.color).frame(width: size, height: size)
            .padding(size * 0.32)
            .background(Circle().fill(.black.opacity(0.55)))
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

extension GameState {
    var title: String {
        switch self {
        case .playable: ShellStrings.text("Ready to play")
        case .needsGameData: ShellStrings.text("Needs game data")
        case .needsAppUpdate: ShellStrings.text("App update needed")
        case .broken(let reason, _, _): reason.isEmpty ? ShellStrings.text("Unavailable") : reason
        case .installing(let stage):
            switch stage.phase {
            case .transferring: ShellStrings.text("Transferring – keep connected…") + Self.percent(stage.fraction)
            case .installing: Self.stepTitle(stage.step) + Self.percent(stage.fraction)
            case .interrupted: ShellStrings.text("Transfer stopped")
            case .failed: ShellStrings.text("Install didn't finish")
            }
        }
    }
    private static func stepTitle(_ step: Int) -> String {
        switch step {
        case 1: ShellStrings.text("Importing…")
        case 2: ShellStrings.text("Unpacking small files…")
        case 3: ShellStrings.text("Checking files…")
        case 4: ShellStrings.text("Waiting for another game…")
        case 5: ShellStrings.text("Organizing game folders…")
        default: ShellStrings.text("Installing…")
        }
    }
    private static func percent(_ fraction: Double?) -> String { fraction.map { " \(Int(($0 * 100).rounded(.down)))%" } ?? "" }
    /// The phase of an arriving game; nil for any other state.
    public var installPhase: InstallStage.Phase? { if case .installing(let stage) = self { return stage.phase }; return nil }
    /// Being copied or unpacked: nothing to do but wait, so its primary action is shown but cannot be pressed.
    var isArriving: Bool {
        if case .installing(let stage) = self { return stage.phase == .transferring || stage.phase == .installing }
        return false
    }
    var color: Color {
        switch self {
        case .playable: ShellPalette.ready
        case .needsGameData, .needsAppUpdate: ShellPalette.attention
        case .broken: ShellPalette.muted
        case .installing(let stage): stage.phase == .interrupted || stage.phase == .failed ? ShellPalette.attention : ShellPalette.muted
        }
    }
    var explanation: String {
        switch self {
        case .playable: ""
        case .needsGameData: ShellStrings.text("Choose this game's data to get ready to play.")
        case .needsAppUpdate: ShellStrings.text("Install a newer version of this app to play this game.")
        case .broken(_, let detail, _): detail
        case .installing(let stage):
            switch stage.phase {
            case .transferring: ShellStrings.text("This game is being copied from your computer. Keep the cable connected.")
            case .installing: ShellStrings.text("Getting this game ready. Keep this app open.")
            case .interrupted: ShellStrings.text("Connect this iPhone to the computer again to continue.")
            case .failed:
                (stage.reason.map { $0 + "\n" } ?? "") + ShellStrings.text("Tap Try again. If it still does not finish, install it again from the computer.")
            }
        }
    }
    var actionTitle: String {
        switch self {
        case .playable: ShellStrings.text("Play")
        case .needsGameData: ShellStrings.text("Choose game data…")
        case .needsAppUpdate: ShellStrings.text("How to update")
        case .broken: ShellStrings.text("How to fix")
        case .installing(let stage):
            switch stage.phase {
            case .transferring, .installing: ShellStrings.text("Play")
            case .interrupted: ShellStrings.text("How to continue")
            case .failed: ShellStrings.text("Try again")
            }
        }
    }
    var actionSymbol: String {
        switch self {
        case .playable: "play.fill"
        case .needsGameData: "folder"
        case .needsAppUpdate: "arrow.up.circle"
        case .broken: "wrench.and.screwdriver"
        case .installing(let stage):
            switch stage.phase {
            case .transferring, .installing: "play.fill"
            case .interrupted: "cable.connector"
            case .failed: "arrow.clockwise"
            }
        }
    }
}

/// The Mac's status: a small coloured dot and the words. Prominent is the hero's capitals.
struct StatusLabel: View {
    let state: GameState
    var prominent = false
    var body: some View {
        HStack(spacing: prominent ? 8 : 6) {
            Circle().fill(state.color).frame(width: prominent ? 7 : 6, height: prominent ? 7 : 6)
            Text(prominent ? state.title.uppercased() : state.title)
                .shellType(prominent ? ShellType.eyebrow : ShellType.status)
                .foregroundStyle(state.color)
                .lineLimit(prominent ? 2 : 1)
        }.accessibilityElement(children: .combine)
    }
}

/// What a button does, for its glyph.
enum GlyphRole { case activate, back, settings, controllers }

/// A button as the Mac console draws it for the device used last: the letter in a rounded square for Xbox, Nintendo
/// and unknown controllers, the shape for PlayStation (cross, circle, square, triangle), a key cap for a keyboard.
struct ButtonGlyph: View {
    let role: GlyphRole
    @Environment(\.shellInputDevice) private var device
    var body: some View {
        Group {
            switch device {
            case .controller(.playStation):
                Image(systemName: playStationSymbol).font(.system(size: 9, weight: .heavy)).frame(width: 20, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.45), lineWidth: 1.2))
            case .keyboard:
                Text(keyCap).font(ShellFonts.fixed(10, weight: .bold)).padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.45), lineWidth: 1.2))
            case .controller:
                Text(letter).font(ShellFonts.fixed(11, weight: .bold)).frame(width: 20, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.45), lineWidth: 1.2))
            }
        }.accessibilityHidden(true)
    }
    private var letter: String {
        switch role { case .activate: "A"; case .back: "B"; case .settings: "X"; case .controllers: "Y" }
    }
    private var playStationSymbol: String {
        switch role { case .activate: "xmark"; case .back: "circle"; case .settings: "square"; case .controllers: "triangle" }
    }
    private var keyCap: String {
        switch role { case .activate: "return"; case .back: "esc"; case .settings: "O"; case .controllers: "Y" }
    }
}

struct GlyphHint: View {
    let role: GlyphRole
    let label: String
    var body: some View {
        HStack(spacing: 8) {
            ButtonGlyph(role: role)
            Text(label).shellText(13, .medium, relativeTo: .footnote)
        }.foregroundStyle(.white.opacity(0.6))
    }
}

private struct ShellInputDeviceKey: EnvironmentKey {
    static let defaultValue = InputDevice.controller(.neutral)
}
extension EnvironmentValues {
    /// The device that sent the last input. The hints and the controller help draw its glyphs.
    var shellInputDevice: InputDevice {
        get { self[ShellInputDeviceKey.self] }
        set { self[ShellInputDeviceKey.self] = newValue }
    }
}
extension GameState {
    /// The short verb of the state chip under a Cover Flow card.
    var chipAction: String {
        switch self {
        case .playable: ShellStrings.text("Play")
        case .needsGameData: ShellStrings.text("Choose")
        case .needsAppUpdate: ShellStrings.text("How to update")
        case .broken: ShellStrings.text("How to fix")
        case .installing: actionTitle
        }
    }
    /// Broken, needs-an-update and a stopped transfer are fixed on the computer. Their primary action explains how, instead of acting.
    var needsHelp: Bool {
        switch self {
        case .broken, .needsAppUpdate: true
        case .installing(let stage): stage.phase == .interrupted
        default: false
        }
    }
}

/// Shows the How to fix or How to update explanation for a game. The library provides it. Without one, the state
/// view presents the explanation itself.
private struct ShellHelpKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((GameTile) -> Void)? = nil
}
extension EnvironmentValues {
    var shellShowHelp: ((GameTile) -> Void)? {
        get { self[ShellHelpKey.self] }
        set { self[ShellHelpKey.self] = newValue }
    }
}
