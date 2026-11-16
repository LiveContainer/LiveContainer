import SwiftUI

/// How a choice row presents its options. Segmented cells work for a few short labels. Everything else is a compact
/// row that opens a list, so a long list never turns the settings into a wall of buttons.
enum ChoicePresentation: Equatable {
    case segmented
    case list

    /// More options than this never share a row of segments.
    static let maxSegments = 4
    /// Estimates for Manrope at the segment's 13.5 pt (bold, the widest case) and the cell's side padding.
    static let characterWidth: CGFloat = 7.6
    static let cellPadding: CGFloat = 28
    /// The track around the cells (3 pt each side) and the gap between cells.
    static let trackPadding: CGFloat = 6
    static let cellGap: CGFloat = 2

    /// The rule: segmented when there are 2 to `maxSegments` options and every label fits its equal segment on one
    /// line at `width` (the row's width, nil while unknown) and `textScale` (Dynamic Type, 1 at the default size).
    /// With no width yet only the count decides, and the view still falls back when the real layout does not fit.
    static func resolve(labels: [String], width: CGFloat?, textScale: CGFloat = 1) -> ChoicePresentation {
        guard labels.count >= 2, labels.count <= maxSegments else { return .list }
        guard let width else { return .segmented }
        let count = CGFloat(labels.count)
        let segment = (width - trackPadding - cellGap * (count - 1)) / count
        let widest = labels.map { CGFloat($0.count) * characterWidth * textScale + cellPadding }.max() ?? 0
        return widest <= segment ? .segmented : .list
    }

    /// Dynamic Type's growth of text, close to the system's body scale.
    static func textScale(_ size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.23
        case .xxxLarge: 1.35
        case .accessibility1: 1.6
        case .accessibility2: 1.9
        case .accessibility3: 2.2
        case .accessibility4: 2.6
        case .accessibility5: 3.0
        @unknown default: 1
        }
    }
}

/// A choice the player is picking from a list: which row of which game, and its options.
struct ChoiceRequest: Equatable {
    let gameID: String
    let row: SettingRow
    var options: [SettingOption] {
        if case .choice(let options) = row.kind { options } else { [] }
    }
}

private struct ShellPickChoiceKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((ChoiceRequest) -> Void)? = nil
}
extension EnvironmentValues {
    /// Opens the list for a choice row. The library provides it.
    var shellPickChoice: ((ChoiceRequest) -> Void)? {
        get { self[ShellPickChoiceKey.self] }
        set { self[ShellPickChoiceKey.self] = newValue }
    }
}

/// The list of a choice's options with a checkmark on the current one. A card in the shell's style over the dimmed
/// settings. D-pad and keys move through `pick.<option>` targets, A or Return picks, B or Escape closes.
struct ChoicePickerView: View {
    let request: ChoiceRequest
    let pick: (String) -> Void
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellFocus) private var focus

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(scrolls: false)
            content(scrolls: true)
        }
        .frame(maxWidth: 460)
        .background(Color(red: 0.075, green: 0.075, blue: 0.082), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.5), radius: 40)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("choice.picker")
    }

    private func content(scrolls: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.row.label).shellType(ShellType.flowTitle(20)).lineLimit(2)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("choice.title")
                    if !request.row.note.isEmpty {
                        Text(request.row.note).shellType(ShellType.note).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle()).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ShellStrings.text("Close"))
                .accessibilityIdentifier("choice.close")
                .shellTarget("pick.close", radius: 22, action: close)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
            Rectangle().fill(ShellPalette.hairline).frame(height: 1)
            if scrolls {
                ScrollViewReader { proxy in
                    ScrollView { list }
                        .scrollIndicators(.hidden)
                        .onAppear { proxy.scrollTo("pick.\(request.row.value)", anchor: .center) }
                        .onChange(of: focus.id) { _, id in
                            guard let id, id.hasPrefix("pick.") else { return }
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                                proxy.scrollTo(id, anchor: id == "pick.close" ? .top : .center)
                            }
                        }
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        VStack(spacing: 4) {
            ForEach(request.options) { option in
                let chosen = request.row.value == option.id
                Button { pick(option.id) } label: {
                    HStack(spacing: 12) {
                        Text(option.label).shellText(15, chosen ? .bold : .medium).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if chosen { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).accessibilityHidden(true) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 44)
                    .foregroundStyle(chosen ? ShellPalette.cream : .white.opacity(0.8))
                    .background(.white.opacity(chosen ? 0.09 : 0.0), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("choice.option.\(option.id)")
                .shellTarget("pick.\(option.id)", radius: 10) { pick(option.id) }
            }
        }
        .padding(10)
    }
}

/// The compact choice row: the label on the left, the current value and a chevron on the right.
struct ChoiceValueRow: View {
    let row: SettingRow
    let valueLabel: String
    var hint = ShellStrings.text("Opens the list of choices")
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.label).shellType(ShellType.settingLabel).fixedSize(horizontal: false, vertical: true)
                    if !row.note.isEmpty {
                        Text(row.note).shellType(ShellType.note).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                    }
                    if row.fromShell { FromSettingsMark() }
                }
                Spacer(minLength: 8)
                Text(valueLabel).shellText(14.5, .semibold).foregroundStyle(ShellPalette.cream)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 48)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.label)
        .accessibilityValue(valueLabel)
        .accessibilityHint(hint)
    }
}
