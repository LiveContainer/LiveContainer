// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 S2Arm contributors
import SwiftUI

private struct ShellOpenGameOrderKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var shellOpenGameOrder: (() -> Void)? {
        get { self[ShellOpenGameOrderKey.self] }
        set { self[ShellOpenGameOrderKey.self] = newValue }
    }
}

struct GameOrderButton: View {
    let gameCount: Int
    var iconOnly = false
    @Environment(\.shellOpenGameOrder) private var open

    var body: some View {
        if gameCount > 1, let open {
            Button(action: open) {
                if iconOnly {
                    Image(systemName: "arrow.up.arrow.down").frame(minWidth: 18)
                } else {
                    Label(ShellStrings.text("Reorder"), systemImage: "arrow.up.arrow.down")
                }
            }
            .buttonStyle(ChipButtonStyle())
            .accessibilityLabel(ShellStrings.text("Reorder"))
            .accessibilityIdentifier("library.reorder")
            .shellTarget("lib.reorder", radius: 22, action: open)
        }
    }
}

/// List owns the vertical drag and landing animation; the host receives a single stable-ID move.
struct GameOrderView: View {
    let games: [GameDetail]
    let reorder: (([String], String?) -> Bool)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(ShellStrings.text("Drag the handle up or down to reorder."))
                    .shellText(15).foregroundStyle(.secondary).padding(.horizontal, 20)
                List {
                    ForEach(games) { detail in
                        HStack(spacing: 18) {
                            CoverView(game: detail.game, radius: 10, showsState: false)
                                .frame(width: 112, height: 63)
                            Text(detail.game.title).shellType(ShellType.cardTitle)
                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("reorder.tile.\(detail.id)")
                        .listRowBackground(ShellPalette.surface)
                    }
                    .onMove(perform: moveRows)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                #if os(iOS)
                .environment(\.editMode, .constant(.active))
                #endif
            }
            .padding(.top, 16)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShellPalette.background)
            .navigationTitle(ShellStrings.text("Reorder games"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ShellStrings.text("Done")) { dismiss() }
                        .accessibilityIdentifier("reorder.done")
                }
            }
        }
        .tint(ShellPalette.cream)
    }

    private func moveRows(from offsets: IndexSet, to destination: Int) {
        let ids = games.map(\.id)
        guard let change = GameOrderMove(ids: ids, offsets: offsets, destination: destination) else { return }
        _ = reorder?(change.sources, change.before)
    }
}

/// List's destination uses the original indices; the host's destination is the next remaining game ID.
struct GameOrderMove {
    let sources: [String]
    let before: String?

    init?(ids: [String], offsets: IndexSet, destination: Int) {
        guard !offsets.isEmpty, offsets.allSatisfy(ids.indices.contains),
              (0...ids.count).contains(destination) else { return nil }
        sources = offsets.map { ids[$0] }
        var reordered = ids
        reordered.move(fromOffsets: offsets, toOffset: destination)
        guard reordered != ids, let last = sources.last, let lastIndex = reordered.firstIndex(of: last) else { return nil }
        before = reordered.indices.contains(lastIndex + 1) ? reordered[lastIndex + 1] : nil
    }
}
