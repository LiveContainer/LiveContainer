// S2Arm modification: add an entry to the dedicated game sorting list.
import SwiftUI

/// A Recently played row starts its game, or opens the same fix as Play (game data, an app update).
enum RecentRow {
    /// Space above and below the hairline between two rows, so a title never touches it.
    static let separatorGap: CGFloat = 10
    static let minHeight: CGFloat = 60
    static func glyph(_ state: GameState) -> String { state.actionSymbol }
}

/// The library when it is taller than it is wide: the chosen game's banner as the hero with the title under it,
/// then the collection, then recently played. In one column the primary action sits at the bottom for the thumb.
/// With regular width (an iPad or an unfolded foldable held upright) the collection becomes a grid of wide cards and
/// Play and the settings button move into the hero. Settings themselves only appear when asked for.
struct PortraitLibrary: View, Equatable {
    let games: [GameDetail]
    let selected: GameDetail
    let wide: Bool
    let size: CGSize
    let topInset: CGFloat
    /// The home indicator's height. Without a bottom bar the library scrolls under it to the bottom edge.
    var bottomInset: CGFloat = 0
    /// The Controllers and Settings chips sit in the side column (SideBar), not over the hero.
    var chipsInSideBar = false
    /// The game settings button sits at the top of the side column, so Play has the bar to itself.
    var settingsInSideBar = false
    let controllers: Int
    let select: (String) -> Void
    let primary: (GameDetail) -> Void
    let openSettings: () -> Void
    let openControllers: () -> Void
    let openShellSettings: () -> Void
    @Binding var position: ScrollPosition
    @State private var rowID: String?
    /// Set while the row itself chose the game, so it does not scroll under the finger.
    @State private var rowSelecting = false
    @Environment(\.shellFocus) private var focus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// A short screen (the folded foldable is about 1.4:1) gets a smaller hero and smaller covers, so the hero,
    /// the row and Play all fit without scrolling.
    private var short: Bool { size.height + topInset < 700 }
    /// One height for the hero per layout, a little under half the screen, so "Your games" sits high.
    private var heroHeight: CGFloat {
        let tall = size.height + topInset
        return wide ? min(tall * 0.42, size.width * 0.62) : tall * 0.42
    }
    /// Whole cards only, the gap as wide as the margin: the next card starts exactly at the screen edge, so the edge
    /// falls between cards and never through a name or a status. Long names end in an ellipsis inside their card.
    private var coverSize: CGFloat {
        let target: CGFloat = typeSize.isAccessibilitySize ? 300 : short ? 140 : 160
        let available = size.width - 48
        let count = max(1, ((available + 24) / (target + 24)).rounded(.down))
        return (available - (count - 1) * 24) / count
    }

    /// Re-render only for what is drawn: the games' tiles, the selection and the sizes. A setting changed in the panel
    /// above does not redraw the library underneath.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.games.map(\.game) == rhs.games.map(\.game) && lhs.selected.game == rhs.selected.game && lhs.wide == rhs.wide
            && lhs.size == rhs.size && lhs.topInset == rhs.topInset && lhs.bottomInset == rhs.bottomInset
            && lhs.controllers == rhs.controllers && lhs.chipsInSideBar == rhs.chipsInSideBar
            && lhs.settingsInSideBar == rhs.settingsInSideBar
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HeroView(game: selected.game, width: size.width, topInset: topInset, height: heroHeight,
                             titleSize: wide ? 34 : short ? 24 : 32, short: short) {
                        if wide {
                            HStack(spacing: 12) {
                                Button { primary(selected) } label: {
                                    Label(selected.game.state.actionTitle, systemImage: selected.game.state.actionSymbol)
                                }
                                .buttonStyle(PrimaryPillStyle())
                                .accessibilityLabel(selected.game.state.actionTitle + ", " + selected.game.title)
                                .accessibilityIdentifier("state.action")
                                .shellTarget("lib.play", radius: 25) { primary(selected) }
                                if !settingsInSideBar { settingsButton }
                            }.padding(.top, 8)
                        }
                    }
                    collection.padding(.top, short ? 6 : 14)
                    recent.padding(.top, 34)
                }.padding(.bottom, 28 + (wide ? bottomInset : 0))
            }
            .scrollPosition($position)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: wide ? [.top, .bottom] : .top)
            .safeAreaInset(edge: .bottom, spacing: 0) { if !wide { bottomBar } }
            .overlay(alignment: .top) {
                // S2Arm: the version for screenshots, level with the chips, in one row with them so it gives way first on a
                // narrow phone; the player (#623) before Controllers, so the name says whose saves Play opens.
                HStack(spacing: 10) {
                    LibraryVersionBadge().layoutPriority(-1)
                    Spacer(minLength: 8)
                    if !chipsInSideBar {
                        PlayerChip()
                        ControllerChip(count: controllers, action: openControllers)
                        ShellSettingsChip(action: openShellSettings)
                    }
                }
                .frame(minHeight: 44).padding(.top, 6).padding(.leading, 24).padding(.trailing, 16)
            }
            .onChange(of: focus.id) { _, id in
                guard let id, id.hasPrefix("lib.tile.") || id.hasPrefix("lib.recent.") else { return }
                let target = id.hasPrefix("lib.tile.") ? String(id.dropFirst("lib.tile.".count)) : id
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeading(title: ShellStrings.text("Your games"), trailing: "\(games.count)")
                GameOrderButton(gameCount: games.count)
            }.padding(.horizontal, 24)
            if wide {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 22, alignment: .top)],
                          alignment: .leading, spacing: 24) {
                    ForEach(games) { tile($0) }
                }.padding(.horizontal, 24)
            } else {
                ScrollView(.horizontal) {
                    // Not lazy: every cover is a focus target, so the D-pad can reach the ones still off screen.
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(games) { tile($0).frame(width: coverSize) }
                    }.scrollTargetLayout().padding(.vertical, 6)
                }
                .contentMargins(.horizontal, 24, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $rowID, anchor: .leading)
                // A game chosen elsewhere (at launch, in Recently played, after a fold) comes into view.
                .onAppear { rowID = selected.id }
                .onChange(of: selected.id) { _, id in
                    guard !rowSelecting else { rowSelecting = false; return }
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { rowID = id }
                }
                // A scroll view draws under the safe-area insets, but the covers are sized for the width inside them.
                // Where the system keeps a strip at the side (the iPhone Duo's outer screen, #511) the next card would
                // show there, cut at the screen edge. Clipped to its frame the edge falls between cards again.
                .clipped()
                .padding(.vertical, -6)
            }
        }
    }

    private func tile(_ detail: GameDetail) -> some View {
        let chosen = detail.id == selected.id
        return Button { rowSelecting = !chosen; select(detail.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                CoverView(game: detail.game, showsState: true)
                    .shellTarget("lib.tile.\(detail.id)") { primary(detail) }
                HStack(spacing: 6) {
                    if detail.game.showsNewNote { NewDot(size: 7) }
                    Text(detail.game.title).shellType(ShellType.cardTitle).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        .foregroundStyle(.white.opacity(chosen ? 1 : 0.86))
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                // The dot on the card carries the state. Words only where the game needs something, the line kept for
                // every card so the row stays even.
                Text(detail.game.showsNewNote ? ShellStrings.text("Installed – have fun!") : detail.game.state == .playable ? " " : detail.game.state.title)
                    .shellType(ShellType.status).foregroundStyle(detail.game.showsNewNote ? .white.opacity(0.7) : detail.game.state.color).lineLimit(1)
                    .padding(.top, 4)
                    .accessibilityHidden(detail.game.state == .playable && !detail.game.showsNewNote)
                // The Mac's selection mark: a cream bar under the chosen game.
                Capsule().fill(ShellPalette.cream).frame(height: 3).padding(.top, 10).opacity(chosen ? 1 : 0)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detail.game.title + ", " + detail.game.state.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("tile.\(detail.id)")
        .modifier(GameTileMenu(detail: detail, select: select, openSettings: openSettings))
        .id(detail.id)
    }

    @ViewBuilder private var recent: some View {
        let recent = games.filter { $0.game.recentlyPlayed != nil }
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(title: ShellStrings.text("Recently played")).padding(.bottom, 8)
                ForEach(recent) { detail in
                    Button { primary(detail) } label: {
                        HStack(spacing: 14) {
                            CoverView(game: detail.game, radius: 6).frame(width: 78, height: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(detail.game.title).shellText(15, .semibold).multilineTextAlignment(.leading)
                                Text(detail.game.recentlyPlayed ?? "").shellText(12.5).foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer(minLength: 8)
                            // The glyph of what the row does: the same one Play wears for this game's state.
                            Image(systemName: RecentRow.glyph(detail.game.state)).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5)).accessibilityHidden(true)
                        }.frame(minHeight: RecentRow.minHeight).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(detail.game.state.actionTitle + ", " + detail.game.title)
                    .shellTarget("lib.recent.\(detail.id)") { primary(detail) }
                    .id("lib.recent.\(detail.id)")
                    if detail.id != recent.last?.id {
                        Rectangle().fill(ShellPalette.hairline).frame(height: 1).padding(.leading, 92)
                            .padding(.vertical, RecentRow.separatorGap)
                    }
                }
            }.padding(.horizontal, 24)
        }
    }

    private var settingsButton: some View {
        Button(action: openSettings) { Image(systemName: "slider.horizontal.3") }
            .buttonStyle(RoundIconButtonStyle())
            .accessibilityLabel(ShellStrings.text("Game settings"))
            .accessibilityIdentifier("settings.open")
            .shellTarget("lib.settings", radius: 25, action: openSettings)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { primary(selected) } label: {
                Label(selected.game.state.actionTitle, systemImage: selected.game.state.actionSymbol)
            }
            .buttonStyle(PrimaryPillStyle(expands: true))
            .accessibilityLabel(selected.game.state.actionTitle + ", " + selected.game.title)
            .accessibilityIdentifier("state.action")
            .shellTarget("lib.play", radius: 25) { primary(selected) }
            if !settingsInSideBar { settingsButton }
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
        .background {
            LinearGradient(stops: [.init(color: ShellPalette.background.opacity(0), location: 0),
                                   .init(color: ShellPalette.background, location: 0.4)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// The chosen game's banner filling the whole hero, darkened toward the bottom where the state, the title and what to
/// do next sit. The hero has one height for every game: the words are bottom-aligned, so a short title simply shows
/// more of the banner and a long one covers more of it. Nothing below moves when the selection changes.
struct HeroView<Accessory: View>: View {
    let game: GameTile
    let width: CGFloat
    let topInset: CGFloat
    /// The hero's height including the status bar. It grows only if the reserved words need more.
    let height: CGFloat
    var titleSize: CGFloat = 34
    /// A short screen (the folded foldable): one line of hint.
    var short = false
    @ViewBuilder let accessory: () -> Accessory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The hidden template reserves the longest case (two lines of title, the meta line and the hint), so the
            // hero keeps its height. The words are bottom-aligned inside it and crossfade.
            ZStack(alignment: .bottomLeading) {
                HeroText(status: GameState.needsGameData, title: "M\nM", meta: "M",
                         explanation: short ? "M" : "M\nM", titleSize: titleSize, hintLines: short ? 1 : 2)
                    .hidden().accessibilityHidden(true)
                HeroText(status: game.state, title: game.title, meta: meta,
                         // The hint only where the game cannot start. For a playable game the meta line is enough.
                         explanation: game.state == .playable ? "" : game.state.explanation,
                         titleSize: titleSize, hintLines: short ? 1 : 2)
                    .id(game.id).transition(.opacity)
            }
            .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.25), value: game.id)
            accessory()
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 60)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
        .background {
            ZStack {
                ArtView(game: game, lettering: false)
                // Dark under the status bar, clear across the art, then deep toward the words at the bottom.
                LinearGradient(stops: [.init(color: .black.opacity(0.5), location: 0),
                                       .init(color: .clear, location: 0.22),
                                       .init(color: .clear, location: 0.36),
                                       .init(color: .black.opacity(0.55), location: 0.62),
                                       .init(color: ShellPalette.background.opacity(0.94), location: 0.88),
                                       .init(color: ShellPalette.background, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .leading, endPoint: .center)
            }
            .id(game.id).transition(.opacity)
            .animation(reduceMotion ? .linear(duration: 0.15) : .easeInOut(duration: 0.35), value: game.id)
            .accessibilityHidden(true)
        }
        .clipped()
    }

    private var meta: String {
        ShellFormat.metaLine(game.subtitle, game.recentlyPlayed)
    }
}

/// The hero's words: the state, the title on at most two lines (the full name is in settings), the meta line and a
/// hint of at most two lines.
struct HeroText: View {
    let status: GameState
    let title: String
    let meta: String
    let explanation: String
    let titleSize: CGFloat
    var hintLines = 2
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusLabel(state: status, prominent: true)
            Text(title).shellType(ShellType.heroTitle(titleSize))
                .lineLimit(2).truncationMode(.tail)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("hero.title")
            if !meta.isEmpty {
                Text(meta).shellType(ShellType.meta).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
            }
            if !explanation.isEmpty {
                Text(explanation).shellType(ShellType.body).foregroundStyle(.white.opacity(0.78)).lineLimit(hintLines).padding(.top, 2)
            }
        }
    }
}
