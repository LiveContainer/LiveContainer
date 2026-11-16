import SwiftUI

/// The open button-mapping card: whose map it is (`ControllersView.mappingID` for the shell's, else a game's ID) and the
/// row whose options are showing, nil for the list of rows.
struct PadMappingState: Equatable {
    let gameID: String
    var row: String?
}

private struct ShellOpenPadMappingKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((String) -> Void)? = nil
}
private struct ShellOpenButtonTestKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    /// Opens the button-mapping card for the shell (`ControllersView.mappingID`) or a game. The library provides it.
    var shellOpenPadMapping: ((String) -> Void)? {
        get { self[ShellOpenPadMappingKey.self] }
        set { self[ShellOpenPadMappingKey.self] = newValue }
    }
    /// Opens the button test. The library provides it.
    var shellOpenButtonTest: (() -> Void)? {
        get { self[ShellOpenButtonTestKey.self] }
        set { self[ShellOpenButtonTestKey.self] = newValue }
    }
}

/// The rows of a mapping, shared by the card and the compact row that opens it. A row's `fromShell` means it does what it
/// would do anyway: the default for the shell's map, the shell's choice for a game's.
public enum PadMappingRows {
    /// The shell's map as rows: Swap A and B, then the 16 buttons.
    static func global(_ map: PadMap) -> [SettingRow] {
        let swap = SettingRow(id: "swapAB", label: ShellStrings.text("Swap A and B"),
                              kind: .choice([SettingOption("0", ShellStrings.text("Off")), SettingOption("1", ShellStrings.text("On"))]),
                              value: map.swapAB ? "1" : "0", fromShell: !map.swapAB)
        return [swap] + PadMap.buttons.map { button in
            SettingRow(id: button, label: PadMap.label(button), kind: .choice(PadMap.options), value: map.output(for: button),
                       fromShell: map.output(for: button) == button)
        }
    }
    /// A game's rows, as the host puts them in its "pad" section.
    static func game(_ detail: GameDetail) -> [SettingRow] {
        detail.sections.first { $0.id == sectionID }?.rows ?? []
    }
    static let sectionID = "pad"
    /// The setting a game's card sends to forget the game's own mapping.
    public static let resetID = "pad.reset"
    /// What a game's button row holds while it follows the shell's map.
    static let follow = "follow"
    /// The button a row is for: the shell's rows go by the button, a game's by `pad.<button>`.
    static func button(of row: SettingRow) -> String { row.id.hasPrefix("pad.") ? String(row.id.dropFirst(4)) : row.id }
    /// What a row's button sends: its own value, or the shell's for a game's row that follows it.
    static func output(of row: SettingRow, inherited: PadMap?) -> String {
        row.value == follow ? (inherited ?? PadMap()).output(for: button(of: row)) : row.value
    }
    /// The compact row's value: nothing changed, only A and B swapped (or kept for one game), or a custom map.
    static func summary(_ rows: [SettingRow], game: Bool) -> String {
        let changed = Set(rows.filter { !$0.fromShell }.map(\.id))
        guard let swap = rows.first, !changed.isEmpty else { return ShellStrings.text(game ? "Same as all games" : "Default") }
        // Swapping A and B changes the rows of A and B too: only those three changed reads as the swap itself.
        if changed.contains(swap.id) && changed.isSubset(of: Set(rows.prefix(3).map(\.id))) {
            if swap.value == "1" || swap.value == "on" { return ShellStrings.text("A and B swapped") }
            if swap.value == "off" { return ShellStrings.text("A and B not swapped") }
        }
        return ShellStrings.text("Custom")
    }
}

/// The compact row that opens the mapping card, in the Controllers page and in a game's settings.
struct PadMappingEntryRow: View {
    let gameID: String
    let rows: [SettingRow]
    var targetID: String
    @Environment(\.shellOpenPadMapping) private var openMapping
    var body: some View {
        let isGame = gameID != ControllersView.mappingID
        let row = SettingRow(id: "padMapping", label: ShellStrings.text("Button mapping"),
                             note: ShellStrings.text(isGame ? "Change buttons for this game only." : "What each button sends in games."),
                             kind: .choice([]), value: "")
        ChoiceValueRow(row: row, valueLabel: PadMappingRows.summary(rows, game: isGame), hint: ShellStrings.text("Opens the button mapping")) {
            openMapping?(gameID)
        }
        .shellTarget(targetID, radius: 11) { openMapping?(gameID) }
        .accessibilityIdentifier("padMapping.open")
    }
}

/// The button mapping in a card of its own. The list: the controller drawing for touch and VoiceOver (no live input, no
/// focus target), Swap A and B as a segmented choice, then the 16 buttons in four
/// grouped cards (face buttons, shoulders and triggers, D-pad, more), each row the button's glyph, where it sits and what it
/// sends, a cream dot on a row that differs. Reset stays in a footer under the scrolling list. A row picked shows the
/// buttons it can send as a grid of glyphs, in the same groups. D-pad and keys move through `map.` targets, A picks, B goes
/// back to the rows and then closes.
struct PadMappingCard: View {
    /// The game's title, or All games for the shell's map.
    let title: String
    let rows: [SettingRow]
    /// The shell's map, which a game's rows follow until they are changed. Nil on the shell's own card.
    var inherited: PadMap?
    let openRow: String?
    let open: (String) -> Void
    let pick: (String, String) -> Void
    let backToList: () -> Void
    let reset: () -> Void
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellFocus) private var focus

    private var shown: SettingRow? { openRow.flatMap { id in rows.first { $0.id == id } } }
    private var isGame: Bool { inherited != nil }
    private var swapRow: SettingRow? { rows.first { PadMappingRows.button(of: $0) == "swapAB" } }
    private var changedAny: Bool { !rows.allSatisfy(\.fromShell) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(ShellPalette.hairline).frame(height: 1)
            ViewThatFits(in: .vertical) {
                content.fixedSize(horizontal: false, vertical: true)
                ScrollViewReader { proxy in
                    ScrollView { content }
                        .scrollIndicators(.hidden)
                        .onAppear { if let id = focus.id { proxy.scrollTo(id, anchor: .center) } }
                        .onChange(of: focus.id) { _, id in
                            guard let id, id.hasPrefix("map."), id != "map.close", id != "map.back", id != "map.reset" else { return }
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                        }
                }
            }
            if shown == nil {
                Rectangle().fill(ShellPalette.hairline).frame(height: 1)
                footer
            }
        }
        .frame(maxWidth: 480)
        .background(Color(red: 0.075, green: 0.075, blue: 0.082), in: RoundedRectangle(cornerRadius: 26))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.5), radius: 40)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("padMapping.card")
    }

    @ViewBuilder private var content: some View {
        if let shown { options(shown) } else { list }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if shown != nil {
                roundButton("chevron.left", label: ShellStrings.text("Button mapping"), id: "padMapping.back", target: "map.back", action: backToList)
            }
            if let shown {
                let button = PadMappingRows.button(of: shown)
                PadGlyph(button: button)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PadMap.place(button)).shellType(ShellType.flowTitle(20)).lineLimit(2)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("padMapping.title")
                        .accessibilityLabel(PadMap.label(button) + ", " + PadMap.place(button))
                    Text(ShellStrings.text("Sends in games")).shellType(ShellType.note).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ShellStrings.text("Button mapping")).shellType(ShellType.flowTitle(20)).lineLimit(2)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("padMapping.title")
                    Text(title).shellType(ShellType.note).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            roundButton("xmark", label: ShellStrings.text("Close"), id: "padMapping.close", target: "map.close", action: close)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
    }

    private func roundButton(_ symbol: String, label: String, id: String, target: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44)
                .background(.white.opacity(0.08), in: Circle()).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .shellTarget(target, radius: 22, action: action)
    }

    /// The key to the cream dot, and Reset, which is there whatever the list scrolls to.
    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ChangedDot()
                Text(ShellStrings.text("Changed")).shellType(ShellType.note).foregroundStyle(.white.opacity(0.55))
            }
            .opacity(changedAny ? 1 : 0)
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            Button(action: reset) { Text(ShellStrings.text("Reset")) }
                .buttonStyle(ShellButtonStyle())
                .accessibilityHint(ShellStrings.text(isGame ? "Every button does what it does in all games." : "Every button does what it does by default."))
                .disabled(!changedAny)
                .accessibilityIdentifier("padMapping.reset")
                .shellTarget("map.reset", enabled: changedAny, radius: 9, action: reset)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: The list

    private var list: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(ShellStrings.text(isGame ? "For this game only. A button left alone does what it does in all games."
                                          : "For controllers in games only. This app’s menus keep A to confirm and B to go back."))
                .shellType(ShellType.note).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            drawing
            if let swapRow { swap(swapRow) }
            ForEach(PadMap.groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: group.title)
                    VStack(spacing: 0) {
                        ForEach(Array(group.buttons.enumerated()), id: \.element) { index, button in
                            if index > 0 { Rectangle().fill(.white.opacity(0.06)).frame(height: 1).padding(.leading, 62) }
                            if let row = rows.first(where: { PadMappingRows.button(of: $0) == button }) { buttonRow(row) }
                        }
                    }
                    .background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ShellPalette.hairline))
                    if group.buttons.first == "A" {
                        Text(ShellStrings.text("Named as on a Switch controller, by where they sit."))
                            .shellType(ShellType.note).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }

    /// The controller as the button test draws it, with the Switch names of its places, for touch and VoiceOver: a tap on a
    /// button opens its choices, as its row does, and a cream ring marks a changed button. It never shows what a controller
    /// presses and is no focus target. The card is a menu, so a controller moves through the rows below, A picks and B
    /// closes. Trying buttons is the button test's job, which takes the controller's input for itself (#495).
    private var drawing: some View {
        func row(_ e: PadElement) -> SettingRow? {
            PadMap.button(at: e).flatMap { button in rows.first { PadMappingRows.button(of: $0) == button } }
        }
        let marked = Set(rows.filter { !$0.fromShell }.compactMap { PadMap.element(of: PadMappingRows.button(of: $0)) })
        return VStack(spacing: 10) {
            XboxControllerDiagram(snapshot: PadSnapshot(), switchNames: true, marked: marked,
                                  tap: { e in if let row = row(e) { open(row.id) } },
                                  value: { e in
                                      guard let row = row(e) else { return "" }
                                      let sends = PadMap.label(PadMappingRows.output(of: row, inherited: inherited))
                                      return row.fromShell ? sends : sends + ", " + ShellStrings.text("Changed")
                                  })
                .aspectRatio(XboxControllerDiagram.design.width / XboxControllerDiagram.design.height, contentMode: .fit)
                .frame(maxWidth: 420)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(ShellStrings.text("Controller"))
                .accessibilityIdentifier("padMapping.drawing")
            Text(ShellStrings.text("Tap a button to change what it sends."))
                .shellType(ShellType.note).foregroundStyle(.white.opacity(0.45)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Swap A and B: Off and On, and for a game first the shell's choice. Equal segments, stacked when they do not fit.
    private func swap(_ row: SettingRow) -> some View {
        // The shell's choice reads All games in a segment, short enough for three segments on a phone.
        let options: [SettingOption] = if case .choice(let o) = row.kind {
            o.filter { $0.id != "custom" }.map { $0.id == PadMappingRows.follow ? SettingOption($0.id, ShellStrings.text("All games")) : $0 }
        } else { [] }
        let control = { (lines: [[SettingOption]]) in
            SegmentedChoice(label: row.label, rows: lines, value: row.value, targetPrefix: "map.swap.") { pick(row.id, $0) }
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(row.label).shellType(ShellType.settingLabel)
                if !row.fromShell { ChangedDot() }
            }
            Text(ShellStrings.text("Puts A on the bottom button, where Xbox and PlayStation controllers confirm."))
                .shellType(ShellType.note).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                control([options])
                control(options.map { [$0] })
            }
        }
        .padding(16)
        .background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ShellPalette.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("padMapping.row.\(row.id)")
    }

    private func buttonRow(_ row: SettingRow) -> some View {
        let button = PadMappingRows.button(of: row)
        let output = PadMappingRows.output(of: row, inherited: inherited)
        let changed = !row.fromShell
        return Button { open(row.id) } label: {
            HStack(spacing: 12) {
                PadGlyph(button: button).frame(width: 36)
                Text(PadMap.place(button)).shellType(ShellType.settingLabel)
                    .foregroundStyle(.white.opacity(changed ? 1 : 0.85)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if changed { ChangedDot() }
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(changed ? 0.5 : 0.25))
                PadGlyph(button: output, lit: changed, dim: !changed).frame(minWidth: 36)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PadMap.label(button) + ", " + PadMap.place(button))
        .accessibilityValue(PadMap.label(output) + (changed ? ", " + ShellStrings.text("Changed") : ""))
        .accessibilityHint(ShellStrings.text("Opens the list of choices"))
        .accessibilityIdentifier("padMapping.row.\(row.id)")
        .shellTarget("map.row.\(row.id)", radius: 12) { open(row.id) }
        .id("map.row.\(row.id)")
    }

    // MARK: A row's options

    /// The buttons a row can send, as glyphs in the list's groups, None last, and on a game's card the shell's choice first.
    private func options(_ row: SettingRow) -> some View {
        let button = PadMappingRows.button(of: row)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return VStack(alignment: .leading, spacing: 18) {
            if let inherited {
                wideOption(row, id: PadMappingRows.follow, label: ShellStrings.text("Same as all games"),
                           glyph: inherited.output(for: button))
            }
            ForEach(PadMap.groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: group.title)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(group.buttons, id: \.self) { option in chip(row, option: option, isDefault: option == button) }
                    }
                }
            }
            wideOption(row, id: "none", label: ShellStrings.text("None"), glyph: "none")
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }

    private func chip(_ row: SettingRow, option: String, isDefault: Bool) -> some View {
        let chosen = row.value == option
        return Button { pick(row.id, option) } label: {
            PadGlyph(button: option, inverted: chosen)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(chosen ? ShellPalette.cream : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(chosen ? 0 : 0.08)))
                .overlay(alignment: .topTrailing) {
                    // The button's own place: what it sends when nothing is changed.
                    if isDefault { Circle().fill(chosen ? .black.opacity(0.5) : .white.opacity(0.35)).frame(width: 5, height: 5).padding(7) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PadMap.label(option) + ", " + PadMap.place(option))
        .accessibilityValue(isDefault ? ShellStrings.text("Default") : "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("padMapping.option.\(option)")
        .shellTarget("map.opt.\(option)", radius: 12) { pick(row.id, option) }
        .id("map.opt.\(option)")
    }

    private func wideOption(_ row: SettingRow, id: String, label: String, glyph: String) -> some View {
        let chosen = row.value == id
        return Button { pick(row.id, id) } label: {
            HStack(spacing: 12) {
                Text(label).shellText(15, chosen ? .bold : .medium).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                PadGlyph(button: glyph, inverted: chosen)
                if chosen { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).accessibilityHidden(true) }
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .foregroundStyle(chosen ? .black : .white.opacity(0.85))
            .background(chosen ? ShellPalette.cream : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(chosen ? 0 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(id == PadMappingRows.follow ? PadMap.label(glyph) : "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("padMapping.option.\(id)")
        .shellTarget("map.opt.\(id)", radius: 12) { pick(row.id, id) }
        .id("map.opt.\(id)")
    }
}

/// The cream dot on what differs from the default (the shell's map) or from all games (a game's).
private struct ChangedDot: View {
    var body: some View { Circle().fill(ShellPalette.cream).frame(width: 7, height: 7).accessibilityHidden(true) }
}

/// A controller button drawn as it looks on a Switch controller: the face buttons and + and − round, the shoulders and
/// triggers as a rounded bar, the D-pad as its arrow, the stick presses as a stick. `lit` draws it in cream (a changed value),
/// `inverted` in black for a cream background (the chosen chip), `dim` quieter (an unchanged value).
struct PadGlyph: View {
    let button: String
    var lit = false
    var inverted = false
    var dim = false
    var body: some View {
        let ink: Color = inverted ? .black : lit ? ShellPalette.cream : .white.opacity(dim ? 0.45 : 0.9)
        let line: Color = inverted ? .black.opacity(0.55) : lit ? ShellPalette.cream.opacity(0.9) : .white.opacity(dim ? 0.2 : 0.4)
        Group {
            switch button {
            case "A", "B", "X", "Y":
                Text(verbatim: button).font(ShellFonts.fixed(12, weight: .heavy)).frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(line, lineWidth: 1.4))
            case "Plus", "Minus":
                Image(systemName: button == "Plus" ? "plus" : "minus").font(.system(size: 10, weight: .heavy)).frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(line, lineWidth: 1.4))
            case "Up", "Down", "Left", "Right":
                // The arm's direction alone: the whole cross with one arm filled reads alike at this size.
                Image(systemName: "arrowtriangle.\(button.lowercased()).fill").font(.system(size: 10, weight: .bold)).frame(width: 24, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(line, lineWidth: 1.4))
            case "LS", "RS":
                Image(systemName: button == "LS" ? "l.joystick.press.down" : "r.joystick.press.down").font(.system(size: 19, weight: .regular))
                    .frame(width: 26, height: 26)
            case "none":
                Image(systemName: "nosign").font(.system(size: 15, weight: .semibold)).frame(width: 26, height: 26)
            default:
                Text(verbatim: button).font(ShellFonts.fixed(11, weight: .heavy)).padding(.horizontal, 8).frame(minWidth: 32, minHeight: 22)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(line, lineWidth: 1.4))
            }
        }
        .foregroundStyle(ink)
        .accessibilityHidden(true)
    }
}
