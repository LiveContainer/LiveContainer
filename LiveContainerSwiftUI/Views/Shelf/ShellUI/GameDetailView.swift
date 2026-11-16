import SwiftUI

/// One game's settings: what it is and its state, then the setting groups, game data, cloud saves and the reset.
/// The library supplies the scrolling container. Values come in through `detail` and leave through `actions`.
public struct GameDetailView: View {
    public let detail: GameDetail
    public var actions: ShellActions
    /// Off where the screen shows the primary action already, as beside the library's hero.
    public var showsPrimaryAction: Bool
    /// Off where the game's cover and title are already in view, as beside the library's hero.
    public var showsHeader: Bool
    @Environment(\.shellAskDelete) private var askDelete
    public init(detail: GameDetail, actions: ShellActions = ShellActions(), showsPrimaryAction: Bool = true, showsHeader: Bool = true) {
        self.detail = detail
        self.actions = actions
        self.showsPrimaryAction = showsPrimaryAction
        self.showsHeader = showsHeader
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if showsHeader || showsPrimaryAction { header }
            ForEach(detail.sections) { section in
              // 社区补丁与金手指合成一块 S 级优化专区（SGradeGroup.swift），出现在两组里第一组的位置
              if SGradeGroup.ids.contains(section.id) {
                if section.id == detail.sections.first(where: { SGradeGroup.ids.contains($0.id) })?.id {
                    SGradeGroup(gameID: detail.id, sections: detail.sections.filter { SGradeGroup.ids.contains($0.id) }) { actions.onChange(detail.id, $0, $1) }
                }
              } else {
                group(section.title) {
                    // The button mapping is one row here and opens a card of its own, as a long choice list does.
                    if section.id == PadMappingRows.sectionID {
                        PadMappingEntryRow(gameID: detail.id, rows: section.rows, targetID: "set.row.padMapping")
                    } else {
                        ForEach(section.rows) { row in
                            // Equatable on its row: a change re-renders the changed row only, not every row of the game.
                            SettingControl(gameID: detail.id, row: row) { actions.onChange(detail.id, row.id, $0) }.equatable()
                            if row.id != section.rows.last?.id { divider }
                        }
                    }
                }
              }
            }
            group(ShellStrings.text("Game data")) {
                SourceRow(symbol: "folder",
                          title: detail.dataSource.isEmpty ? ShellStrings.text("No data selected") : detail.dataSource,
                          note: detail.dataNote) {
                    // Only while the game has no data: the button then leads to how to bring it in. Once the host reports the
                    // data as ready (the iOS host fills dataSource with its state and size), the row only reads.
                    if detail.dataSource.isEmpty {
                        Button(ShellStrings.text("Choose…")) { actions.onPickGameData(detail.id) }
                            .buttonStyle(ShellButtonStyle(fills: true)).accessibilityLabel(ShellStrings.text("Choose game data…"))
                            .shellTarget("set.data") { actions.onPickGameData(detail.id) }
                    }
                    if let useAppData = actions.onUseAppData, !detail.dataSource.isEmpty && !detail.dataFromShell {
                        Button(ShellStrings.text("Use app data")) { useAppData(detail.id) }
                            .buttonStyle(ShellButtonStyle(fills: true)).shellTarget("set.appdata") { useAppData(detail.id) }
                    }
                }
                if !detail.dlc.isEmpty {   // nothing to say when the host reports no additional content
                    divider
                    Label(detail.dlc, systemImage: "square.stack.3d.up")
                        .shellText(14).foregroundStyle(.white.opacity(0.72)).frame(minHeight: 32)
                }
            }
            if let pickCloud = actions.onPickCloudSaves {
                group(ShellStrings.text("Cloud saves")) {
                    SourceRow(symbol: detail.cloudSaves == nil ? "icloud.slash" : "icloud",
                              title: detail.cloudSaves ?? ShellStrings.text("Off"),
                              note: detail.cloudNote.isEmpty ? ShellStrings.text("Choose the same iCloud Drive folder you use on your Mac.") : detail.cloudNote) {
                        Button(ShellStrings.text("Choose folder…")) { pickCloud(detail.id) }
                            .buttonStyle(ShellButtonStyle(fills: true)).shellTarget("set.cloud") { pickCloud(detail.id) }
                        if let useShellCloud = actions.onUseShellCloud, detail.cloudCanUseShell {
                            Button(ShellStrings.text("Use Settings folder")) { useShellCloud(detail.id) }
                                .buttonStyle(ShellButtonStyle(fills: true)).shellTarget("set.cloud.shell") { useShellCloud(detail.id) }
                        }
                        if let disableCloud = actions.onDisableCloudSaves, detail.cloudSaves != nil {
                            Button(ShellStrings.text("Turn off")) { disableCloud(detail.id) }
                                .buttonStyle(ShellButtonStyle(fills: true)).accessibilityLabel(ShellStrings.text("Turn off cloud saves"))
                                .shellTarget("set.cloud.off") { disableCloud(detail.id) }
                        }
                    }
                }
            }
            if let resetDefaults = actions.onResetDefaults {
                VStack(alignment: .leading, spacing: 10) {
                    Button(ShellStrings.text("Reset to tested defaults")) { resetDefaults(detail.id) }
                        .buttonStyle(ShellButtonStyle(fills: true))
                        .disabled(!detail.hasModifiedSettings)
                        .shellTarget("set.reset", enabled: detail.hasModifiedSettings) { resetDefaults(detail.id) }
                    Text(ShellStrings.text("Brings back the settings this game was tested with."))
                        .shellText(12.5).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let askDelete {
                // Last and apart from the rest: the one action here that removes something. It only asks, the question names what goes.
                VStack(alignment: .leading, spacing: 10) {
                    Button(ShellStrings.text("Delete game…")) { askDelete(detail.game) }
                        .buttonStyle(ShellButtonStyle(fills: true, destructive: true))
                        .accessibilityIdentifier("set.delete")
                        .shellTarget("set.delete") { askDelete(detail.game) }
                    Text(ShellStrings.text("Deletes the game’s data on this device. You choose whether its saves go too."))
                        .shellText(12.5).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.foregroundStyle(.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeader {
            HStack(alignment: .center, spacing: 16) {
                CoverView(game: detail.game, radius: 8).frame(width: 112, height: 63)
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.game.title).shellText(24, .heavy, relativeTo: .title).tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("detail.title")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { status }
                        VStack(alignment: .leading, spacing: 4) { status }
                    }
                }
            }
            }
            if showsPrimaryAction {
                if !detail.game.state.explanation.isEmpty {
                    Text(detail.game.state.explanation).shellText(14).foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                GameStateView(game: detail.game, actions: actions, showsExplanation: false)
            }
        }
    }

    @ViewBuilder private var status: some View {
        StatusLabel(state: detail.game.state).fixedSize()
        if !detail.game.subtitle.isEmpty {
            Text(detail.game.subtitle).shellText(12.5).foregroundStyle(.white.opacity(0.45)).fixedSize()
        }
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        SettingsGroup(title: title, content: content)
    }
}

/// A titled card of rows, for the game settings and the shell settings alike.
struct SettingsGroup<Content: View>: View {
    let title: String
    private let content: Content
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: title)
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .shellCard()
        }
    }
}

/// Where something comes from (game data, a cloud folder) and the buttons that change it.
struct SourceRow<Buttons: View>: View {
    let symbol: String
    let title: String
    let note: String
    @ViewBuilder let buttons: () -> Buttons
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol).foregroundStyle(ShellPalette.cream.opacity(0.8)).frame(width: 20).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).shellText(15, .semibold).fixedSize(horizontal: false, vertical: true)
                    if !note.isEmpty {
                        Text(note).shellType(ShellType.note).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // The buttons share the card's width in equal parts, or stack full width when their labels do not fit.
            ViewThatFits(in: .horizontal) {
                EqualRow(spacing: 10) { buttons() }
                VStack(spacing: 10) { buttons() }
            }
        }
    }
}

struct SettingControl: View, Equatable {
    /// Part of the comparison: two games can have identical rows, and the row must report to its own game.
    let gameID: String
    let row: SettingRow
    /// The focus ids of the row's controls start with this, so a panel can tell its own from the library's.
    var targetPrefix = "set.row."
    let change: (String) -> Void
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.gameID == rhs.gameID && lhs.row == rhs.row }
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.shellPickChoice) private var pickChoice
    @Environment(\.shellIgnoresPress) private var ignoresPress
    /// The row's width, once measured, for the segmented-or-list rule.
    @State private var width: CGFloat?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch row.kind {
            case .toggle(let on, let off):
                Toggle(isOn: Binding(get: { row.value == on }, set: { change($0 ? on : off) })) { label }
                    .toggleStyle(CreamToggleStyle())
                    .shellTarget("\(targetPrefix)\(row.id)", enabled: row.enabled) { change(row.value == on ? off : on) }
            case .choice(let options):
                let labels = options.map(\.label)
                let scale = ChoicePresentation.textScale(typeSize)
                switch ChoicePresentation.resolve(labels: labels, width: width, textScale: scale) {
                case .segmented:
                    // Equal segments across the card. If the real layout still cannot hold them, the compact row. Only the segments
                    // decide: the label wraps to the card, so a long note (Picture, #545) does not push the row into the list.
                    ViewThatFits(in: .horizontal) {
                        VStack(alignment: .leading, spacing: 12) {
                            label.frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
                            segmented([options])
                        }
                        valueRow(options)
                    }
                case .list:
                    valueRow(options)
                }
            case .range(let min, let max, let step, let unit):
                HStack(alignment: .firstTextBaseline) {
                    label
                    Spacer(minLength: 8)
                    Text((Double(row.value) ?? min).formatted(.number.precision(.fractionLength(0...2))) + unit)
                        .shellText(15, .bold).monospacedDigit().foregroundStyle(ShellPalette.cream)
                }
                HStack(spacing: 10) {
                    rangeButton("minus", min: min, max: max, delta: -step)
                    if min < max && step > 0 {
                        Slider(value: Binding(get: { Double(row.value) ?? min }, set: { change(String($0)) }), in: min...max, step: step)
                            .frame(minHeight: 44).tint(ShellPalette.cream).accessibilityLabel(row.label)
                    }
                    rangeButton("plus", min: min, max: max, delta: step)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { new in if width.map({ abs($0 - new) > 0.5 }) ?? true { width = new } }
            .disabled(!row.enabled).opacity(row.enabled ? 1 : 0.45)
            .accessibilityIdentifier("setting.\(row.id)")
    }
    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.label).shellType(ShellType.settingLabel).fixedSize(horizontal: false, vertical: true)
            if !row.note.isEmpty { Text(row.note).shellType(ShellType.note).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true) }
            if row.fromShell { FromSettingsMark() }
        }
    }
    private func segmented(_ rows: [[SettingOption]]) -> some View {
        SegmentedChoice(label: row.label, rows: rows, value: row.value, targetPrefix: "\(targetPrefix)\(row.id).", enabled: row.enabled,
                        change: change)
    }
    /// Many or long options: label and current value in one compact row that opens the list.
    private func valueRow(_ options: [SettingOption]) -> some View {
        ChoiceValueRow(row: row, valueLabel: options.first { $0.id == row.value }?.label ?? row.value) {
            pickChoice?(ChoiceRequest(gameID: gameID, row: row))
        }
        .shellTarget("\(targetPrefix)\(row.id)", enabled: row.enabled, radius: 11) { pickChoice?(ChoiceRequest(gameID: gameID, row: row)) }
    }
    private func rangeButton(_ symbol: String, min: Double, max: Double, delta: Double) -> some View {
        let action = { change(String(Swift.min(max, Swift.max(min, (Double(row.value) ?? min) + delta)))) }
        return Button { if !ignoresPress() { action() } } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).background(.white.opacity(0.055), in: Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.10)))
        .accessibilityLabel(ShellStrings.text(symbol == "minus" ? "Decrease" : "Increase") + " " + row.label)
        .shellTarget("\(targetPrefix)\(row.id).\(symbol)", enabled: row.enabled, radius: 22, action: action)
    }
}

/// The Mac's segmented choice, across the whole card: a dim track, equal segments, the chosen value in cream. Each inner
/// array is one line of segments. A focus target per option, `targetPrefix` plus the option's ID.
struct SegmentedChoice: View {
    let label: String
    let rows: [[SettingOption]]
    let value: String
    let targetPrefix: String
    var enabled = true
    let change: (String) -> Void
    @Environment(\.shellIgnoresPress) private var ignoresPress
    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, options in
                EqualRow(spacing: 2) {
                    ForEach(options) { option in
                        let chosen = value == option.id
                        // The system's echo of a controller button picks nothing (the shell's focus took the button).
                        Button { if !ignoresPress() { change(option.id) } } label: {
                            Text(option.label).shellText(13.5, chosen ? .bold : .medium).lineLimit(1)
                                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(chosen ? .black : .white.opacity(0.75))
                                .background(chosen ? ShellPalette.cream : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label + ", " + option.label)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                        .shellTarget(targetPrefix + option.id, enabled: enabled, radius: 8) { change(option.id) }
                    }
                }
            }
        }
        .padding(3)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.08)))
    }
}

/// Says that a row shows the shell settings' choice, because the game has none of its own.
struct FromSettingsMark: View {
    var body: some View {
        Text(ShellStrings.text("From Settings")).shellType(ShellType.note).foregroundStyle(ShellPalette.cream.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Children side by side in equal widths that fill the row. Its ideal width is the widest child times the count, so
/// a `ViewThatFits` can fall back when the labels would not fit at equal widths.
struct EqualRow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let natural = (sizes.map(\.width).max() ?? 0) * CGFloat(subviews.count) + gaps
        let width = proposal.width.map { $0.isFinite ? $0 : natural } ?? natural
        let cell = subviews.isEmpty ? 0 : (width - gaps) / CGFloat(subviews.count)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let cell = (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (cell + spacing), y: bounds.minY),
                          proposal: ProposedViewSize(width: cell, height: bounds.height))
        }
    }
}
