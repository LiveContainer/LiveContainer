// S2Arm modification: add the sorting entry, keep transformed neighbours mounted and align the title during scrolling.
import SwiftUI
#if canImport(QuartzCore)
import QuartzCore   // CADisplayLink for the deck momentum driver on macOS (the probe/test platform)
#endif

/// The library when it is wider than it is tall: one card in the middle, its neighbours turned back, the title and
/// state underneath. The card is the button: a tap on the centred card does what the game needs (Play, choose its
/// data, how to fix it). The backdrop (the blurred banner) is drawn by the library behind the safe area.
struct CoverFlowView: View, Equatable {
    let games: [GameDetail]
    let selected: GameDetail
    let controllers: Int
    /// The controller hints at the bottom, while a controller or keyboard is in use.
    let showsHints: Bool
    /// The screen's safe areas around this view, so the cards can sit in the middle of the whole screen.
    var screenInsets = EdgeInsets()
    /// The Controllers and Settings chips sit in the side column (SideBar), not in the top bar.
    var chipsInSideBar = false
    /// The game settings button sits at the top of the side column, not in the top bar.
    var settingsInSideBar = false
    let select: (String) -> Void
    let primary: (GameDetail) -> Void
    let openSettings: () -> Void
    let openControllers: () -> Void
    let openShellSettings: () -> Void
    @State private var centredID: String?
    /// How far the carousel is scrolled: 0 with the first card in the middle.
    @State private var scrolled: CGFloat = 0
    /// True from the first touch of a scroll until it has settled.
    @State private var userScrolling = false
    /// The card nearest the middle when the current touch began, also mid-snap, for one card per gesture.
    @State private var gestureStart = 0
    /// False while the carousel scrolls, decelerates or snaps: a tap on the centre card then does nothing.
    @State private var settled = true
    /// The card in the middle when the current touch began. A tap is judged against this snapshot, not against
    /// whatever is selected by the time the finger lifts.
    @State private var touchStartID: String?
    @State private var touchActive = false
    /// When the selection last changed: on the shelf (no scroll phases) a centre-card tap counts only once the
    /// switch animation has had its 0.32s.
    @State private var lastSwitchAt = Date.distantPast
    /// The carousel's latest scroll velocity in points per millisecond, sampled from the geometry changes, so
    /// the landing card can be committed the moment the snap is decided instead of when the scroll settles.
    @State private var scrollVelocity: CGFloat = 0
    @State private var lastOffsetAt: Date?
    // MARK: Deck train state (one to three games)

    /// The train's scroll amount in card units (1.0 = one stride); at rest it is exactly the selected index.
    /// Card units, not points, so a rest value can never be poisoned by a transitional layout width.
    @State private var deckOffset: CGFloat = 0
    /// The offset when the current drag began, and the drag's unclamped logical offset (raw finger travel in card
    /// units): the landing projection reads the logical value, the display value is rubber-banded at the ends.
    @State private var deckDragStart: CGFloat = 0
    @State private var deckDragLogical: CGFloat = 0
    /// Drag tail samples (last 120ms), for the true release velocity.
    @State private var deckDragSamples: [(time: Date, logical: CGFloat)] = []
    @State private var deckDragging = false
    /// False from the start of any deck scroll until 0.32s after its landing was committed (the epoch rule).
    @State private var deckIsSettled = true
    @State private var deckEpoch = 0
    /// Free momentum after a fast flick: a display-link driver integrates friction decay straight
    /// into `deckOffset`; there is no predetermined target while it runs.
    @State private var deckMomentumActive = false
    @State private var deckMomentumVelocity: CGFloat = 0
    @State private var deckDriver = DeckMomentumDriver()
    /// Last deck tap adjudication: the same touch delivered twice is judged once.
    @State private var deckTapAdjudicatedAt = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Re-render only for what is drawn: the games' tiles, the selection and the hints. Settings changes elsewhere do
    /// not reach the carousel.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.games.map(\.game) == rhs.games.map(\.game) && lhs.selected.game == rhs.selected.game
            && lhs.controllers == rhs.controllers && lhs.showsHints == rhs.showsHints && lhs.screenInsets == rhs.screenInsets
            && lhs.chipsInSideBar == rhs.chipsInSideBar && lhs.settingsInSideBar == rhs.settingsInSideBar
    }

    var body: some View {
        GeometryReader { geometry in
            let short = geometry.size.height < 520
            // The centred card sits in the middle of the whole screen, the top bar laid over it. The title and state
            // go under the card at a fixed distance, so the card is only as tall as leaves room for them above the
            // bottom edge, and never so wide that the neighbours vanish.
            let height = geometry.size.height
            let middle = (height + screenInsets.top + screenInsets.bottom) / 2 - screenInsets.top
            let gap: CGFloat = short ? 10 : 24
            let words = Self.infoHeight(short: short)
            let below: CGFloat = short ? 4 : 56          // the hint row on a tablet, a margin on a phone
            let byBottom = 2 * (height - middle - gap - words - below)
            let byTop = 2 * (middle - Self.barTop(short: short) - Self.barHeight - (short ? 6 : 16))
            let cardHeight = max(90, min(byBottom, byTop, geometry.size.width * 0.54 * 9 / 16) / 1.06)
            let cover = cardHeight * 16 / 9
            let displayed = CoverFlowSelection.game(games: games, selected: selected, offset: scrolled,
                                                     stride: cover * 1.04, scrolling: userScrolling && games.count > 3)
            ZStack(alignment: .top) {
                if games.count <= 3 {
                    // The deck's full-area drag host (the carousel host is the whole
                    // screen). The train's own frame is only the card band, and a drag is recognised
                    // only where a hit-testable view carries it into the gesture — beside the cards,
                    // toward the screen's edges, the band's gaps reached no gesture at all, so a swipe
                    // that started there did nothing (device report). This layer is that host: the
                    // whole area, under everything else, carrying the same drag. A touch takes exactly
                    // one hit path, so a touch on a card still goes through the train's own gesture
                    // and the two never double-fire; the bar, the hints and the words stay in front,
                    // their buttons keep their taps, and a drag through their empty ground scrolls
                    // the deck.
                    Rectangle()
                        .fill(.white.opacity(0.001))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(deckDrag(stride: cover + cover * 0.04))
                        .accessibilityHidden(true)
                }
                VStack(spacing: 0) {
                    Group {
                        if games.count <= 3 { train(width: geometry.size.width, cover: cover) } else { carousel(width: geometry.size.width, cover: cover) }
                    }.frame(height: cardHeight * 1.06)
                    info(displayed, short: short, width: geometry.size.width)
                        .padding(.top, gap).padding(.horizontal, 24)
                }
                .padding(.top, middle - cardHeight * 1.06 / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                topBar(short: short, displayed: displayed).padding(.horizontal, 24).padding(.top, Self.barTop(short: short))
                if !short {
                    // The hint row keeps its place when it is hidden, so nothing moves when it appears.
                    hints.opacity(showsHints ? 1 : 0).padding(.bottom, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected.id)
        .onAppear { centredID = selected.id }
        // Snapshot the centred card at the start of every touch, before anything in that touch can move the
        // selection. Simultaneous and distance-free, so it never takes part in the gestures themselves.
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !touchActive { touchActive = true; touchStartID = selected.id } }
            .onEnded { _ in touchActive = false })
        .onChange(of: selected.id) { _, id in
            lastSwitchAt = Date()
            // The deck train follows an external selection change with its own settle animation (guarded against
            // the player's drag and momentum inside `syncDeckOffset`).
            syncDeckOffset()
            // A selection from the D-pad or a tap scrolls the carousel. Never while the player is touching it or it is
            // still moving: the player's gesture always wins.
            guard centredID != id, !userScrolling else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { centredID = id }
        }
    }

    /// The title and state under the card: two lines of title reserved, then the state line.
    static func infoHeight(short: Bool) -> CGFloat {
        let size: CGFloat = short ? 18 : 28
        return size * 1.3 * 2 + 8 + 34
    }

    /// The distance from the top of the safe area to the top bar. A phone on its side has no status bar, so the chips
    /// need their own air above them there. The bar is one centred row, so the title and the chips share a centre.
    static func barTop(short: Bool) -> CGFloat { short ? 12 : 16 }
    static let barHeight: CGFloat = 44

    private func topBar(short: Bool, displayed: GameDetail) -> some View {
        let position = (games.firstIndex { $0.id == displayed.id } ?? 0) + 1
        return ViewThatFits(in: .horizontal) {
            topBarContents(short: short, position: position, compact: false)
            topBarContents(short: short, position: position, compact: true)
        }
        .dynamicTypeSize(...(short ? DynamicTypeSize.xxLarge : DynamicTypeSize.accessibility5))
    }

    private func topBarContents(short: Bool, position: Int, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            SectionHeading(title: ShellStrings.text("Your games")).fixedSize()
            Text(ShellStrings.text("\(position) of \(games.count)")).shellText(12, .medium, relativeTo: .caption)
                .monospacedDigit().foregroundStyle(.white.opacity(0.45)).padding(.leading, 4).fixedSize()
            // S2Arm: the version for screenshots, after the count; the first thing to give way when the row is tight.
            LibraryVersionBadge().padding(.leading, 6).layoutPriority(-1)
            Spacer(minLength: 12)
            if short && showsHints && !compact {
                // Keep optional controller hints only when the whole row fits.
                hints.fixedSize()
                Spacer(minLength: 12)
            }
            GameOrderButton(gameCount: games.count, iconOnly: compact).fixedSize()
            if !settingsInSideBar {
                Button(action: openSettings) { Image(systemName: "slider.horizontal.3").frame(minWidth: 18) }
                    .buttonStyle(ChipButtonStyle()).fixedSize()
                    .accessibilityLabel(ShellStrings.text("Game settings") + ", " + selected.game.title)
                    .accessibilityIdentifier("settings.open")
                    .shellTarget("lib.settings", radius: 22, action: openSettings)
            }
            if !chipsInSideBar {
                PlayerChip(compact: compact).fixedSize()   // S2Arm (#623): who is playing, before Controllers
                ControllerChip(count: controllers, action: openControllers).fixedSize()
                ShellSettingsChip(action: openShellSettings).fixedSize()
            }
        }
    }
    private var selectedIndex: Int { games.firstIndex { $0.id == selected.id } ?? 0 }

    /// More than three games: a carousel that moves one card per gesture, the neighbours turned back a little and
    /// tucked behind the middle card, a deck rather than a row.
    private func carousel(width: CGFloat, cover: CGFloat) -> some View {
        let spacing = cover * 0.04
        let stride = cover + spacing
        let margin = max(0, (width - cover) / 2)
        let visible = CoverFlowWindow.indices(count: games.count, offset: scrolled, width: width, cover: cover)
        return ScrollView(.horizontal) {
            // Keep stable scroll slots for every ID, mounting art only around the transformed visible region.
            HStack(spacing: spacing) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, detail in
                    Group {
                        if visible.contains(index) || detail.id == selected.id {
                            coverButton(detail, cover: cover)
                                .modifier(FlowTilt(place: CGFloat(index) - scrolled / stride, cover: cover, flat: reduceMotion))
                        } else {
                            Color.clear.frame(width: cover, height: cover * 9 / 16)
                                .accessibilityHidden(true)
                        }
                    }
                    .id(detail.id)
                }
            }.scrollTargetLayout()
        }
        .scrollTargetBehavior(CardSnap(stride: stride, count: games.count, start: gestureStart))
        .scrollPosition(id: $centredID, anchor: .center)
        .contentMargins(.horizontal, margin, for: .scrollContent)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x + $0.contentInsets.leading } action: { old, offset in
            scrolled = offset
            // Keep the latest velocity (points per millisecond, positive toward the later cards), sampled here so
            // the phase change below can predict the snap's landing card from the same rule the snap itself uses.
            let now = Date()
            if let last = lastOffsetAt {
                let dt = now.timeIntervalSince(last) * 1000
                if dt > 0 { scrollVelocity = (offset - old) / CGFloat(dt) }
            }
            lastOffsetAt = now
        }
        .onScrollPhaseChange { old, phase, context in
            // A touch scroll goes interacting, decelerating, maybe animating (the snap), then idle. Only once it has
            // settled does the card in the middle become the selection, read from the final offset itself, so a stale
            // value can never send the carousel back. A scroll this view animates starts from idle and never sets the
            // flag, so it never selects.
            settled = phase == .idle
            if phase == .interacting && old != .interacting {
                let offset = context.geometry.contentOffset.x + context.geometry.contentInsets.leading
                gestureStart = min(games.count - 1, max(0, Int((offset / stride).rounded())))
            }
            if phase == .decelerating && old == .interacting {
                // Landing commit (the landing rule): the snap target is decided as the finger lifts, so commit
                // the selection in that same frame — the backdrop, title and counter crossfade while the card is
                // still travelling, not a beat after it lands. Predicted with CardSnap's own rule from the release
                // offset and velocity; the idle pass below still corrects from the final offset if this missed.
                // While the finger is down nothing is committed, so an undecided drag never flickers the backdrop.
                let offset = context.geometry.contentOffset.x + context.geometry.contentInsets.leading
                let card = CardSnap.card(target: offset + scrollVelocity * 200, velocity: scrollVelocity,
                                         stride: stride, count: games.count, start: gestureStart)
                if games[card].id != selected.id { select(games[card].id) }
            }
            switch phase {
            case .interacting, .decelerating: userScrolling = true
            case .idle:
                if userScrolling {
                    let offset = context.geometry.contentOffset.x + context.geometry.contentInsets.leading
                    let index = min(games.count - 1, max(0, Int((offset / stride).rounded())))
                    if games[index].id != selected.id { select(games[index].id) }
                }
                userScrolling = false
            default: break
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: Deck train (one to three games)

    /// One to three games on the same rigid train that every count can share (
    /// ported here for the ≤3 branch; the >3 ScrollView carousel above keeps its own mechanism): one shared
    /// offset in card units drives every card through `DeckCardTransform`, whose animatableData is the offset
    /// itself, so position, turn, scale, brightness, opacity and zIndex of every card are pure functions of the
    /// same interpolated scalar in any frame — no card has its own animation clock. The selected
    /// card is therefore centred at every rest position, the drag follows the finger 1:1, and the landing is
    /// decided by the landing rule (logical offset + 220ms velocity projection, clamped only at the ends),
    /// with free momentum for fast flicks. Card size is the same `cover` the carousel uses; the
    /// old shelf's per-count cap (cover ÷ (1 + (n−1)×0.8)) was the retired "whole row on screen" sizing and
    /// goes with it.
    private func train(width: CGFloat, cover: CGFloat) -> some View {
        let stride = cover + cover * 0.04
        let areaH = cover * 9 / 16 * 1.06
        return ZStack {
            ForEach(Array(games.enumerated()), id: \.element.id) { index, detail in
                coverButton(detail, cover: cover, onTapOverride: { deckTapCard(index: index) })
                    .modifier(DeckCardTransform(index: index, offset: deckOffset, width: width, stride: stride,
                                                cover: cover, areaH: areaH, reduceMotion: reduceMotion))
            }
        }
        .frame(width: width, height: areaH)
        .contentShape(Rectangle())
        .gesture(deckDrag(stride: stride))
        .onAppear { snapDeckToFocus() }
        .onChange(of: games.map(\.id)) { _, _ in snapDeckToFocus() }
        .onDisappear { stopDeckMomentum() }
    }

    /// The drag: the display offset follows the finger 1:1 (rubber-banded ×0.35 past the ends), the logical
    /// offset stays unclamped for the landing projection, and the selection follows the nearest card as the
    /// drag crosses each midpoint, so the title, counter and backdrop crossfade while travelling.
    private func deckDrag(stride: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if !deckDragging {
                    deckDragging = true
                    // A finger landing on a moving train stops the momentum driver first; the drag starts from
                    // the offset of this very frame, no jump.
                    stopDeckMomentum()
                    deckDragStart = deckOffset
                    deckDragSamples = [(time: value.time, logical: deckOffset)]
                    beginDeckScroll()
                }
                let logical = deckDragStart - value.translation.width / stride
                deckDragLogical = logical
                deckDragSamples.append((time: value.time, logical: logical))
                deckDragSamples.removeAll { value.time.timeIntervalSince($0.time) > 0.12 }
                deckOffset = DeckMath.rubberBand(logical: logical, count: games.count)
                let nearest = min(games.count - 1, max(0, Int(logical.rounded())))
                if nearest != selectedIndex { select(games[nearest].id) }
            }
            .onEnded { value in
                deckDragging = false
                // Release velocity toward the later cards, in card units (DragGesture's points/sec
                // ÷ 1000 ÷ stride = cards/ms for the projection; ×1000 for the per-second tail estimate).
                let velocity = -value.velocity.width / 1000 / stride
                let card = DeckMath.cardSnap(logicalCards: deckDragLogical, velocityCards: velocity, count: games.count)
                // The momentum gate and the driver's initial velocity use the tail-sampled true release
                // velocity; the low-speed path below keeps the damped value verbatim.
                let velocityPerSecond = DeckMath.releaseVelocity(samples: deckDragSamples, endTime: value.time,
                                                                 endLogical: deckDragLogical, fallback: velocity * 1000)
                let estimatedCard = DeckMath.cardSnap(logicalCards: deckDragLogical, velocityCards: velocityPerSecond / 1000,
                                                      count: games.count)
                let estimatedDistance = CGFloat(estimatedCard) - deckOffset
                let projectedDistance = CGFloat(card) - deckOffset
                if !reduceMotion,
                   abs(velocityPerSecond) > DeckMath.momentumSnapVelocity,
                   abs(estimatedDistance) > 1,
                   deckOffset >= 0,
                   deckOffset <= CGFloat(games.count - 1) {
                    startDeckMomentum(velocityPerSecond: velocityPerSecond)
                } else {
                    withAnimation(deckSettleAnimation(distanceCards: projectedDistance, releaseVelocityCards: velocity)) {
                        deckOffset = CGFloat(card)
                    }
                    if games.indices.contains(card) { select(games[card].id) }
                    finishDeckScroll(epoch: deckEpoch)
                }
            }
    }

    /// A tap on a train card, judged by the tap rule (with a frontal gate): the focus is read
    /// as it stands at adjudication time — never from a touch-start snapshot — so a side card can only ever be
    /// centred, and the centred card acts only once the train has settled exactly frontal. A long press opens
    /// the card menu (GameTileMenu, a context menu) and never reaches this tap path, so no guard is needed.
    private func deckTapCard(index idx: Int) {
        stopDeckMomentum()
        let place = CGFloat(idx) - deckOffset
        deckTap(index: idx, isSettled: deckIsSettled && !deckDragging, isFrontal: abs(place) <= 0.02) {
            beginDeckScroll()
            withAnimation(deckSettleAnimation(distanceCards: CGFloat(idx) - deckOffset)) {
                deckOffset = CGFloat(idx)
            }
            select(games[idx].id)
            finishDeckScroll(epoch: deckEpoch)
        }
    }

    private func deckTap(index idx: Int, isSettled: Bool, isFrontal: Bool, focusAction: () -> Void) {
        if Date().timeIntervalSince(deckTapAdjudicatedAt) < 0.4 { return }
        deckTapAdjudicatedAt = Date()
        if idx != selectedIndex {
            focusAction()
        } else if isSettled && isFrontal {
            primary(games[idx])
        } else if !isFrontal {
            focusAction()
        }
    }

    /// The landing animation: within one card the original timing curve, its duration growing
    /// with the distance; a multi-card release with a velocity goes on the near-constant-speed Bézier, its
    /// duration near-linear in the distance. Reduced motion is a 0.2 linear.
    private func deckSettleAnimation(distanceCards: CGFloat, releaseVelocityCards: CGFloat? = nil) -> Animation {
        if reduceMotion { return .linear(duration: 0.2) }
        let strides = Double(abs(distanceCards))
        if strides > 1, releaseVelocityCards != nil {
            return .timingCurve(0.40, 0.46, 0.80, 1, duration: min(0.85, 0.10 + 0.15 * strides))
        }
        return .timingCurve(0.22, 0.61, 0.36, 1, duration: min(0.55, 0.3 + 0.09 * max(0, strides - 1)))
    }

    /// Free momentum: after a fast flick the offset keeps the release velocity and decays by
    /// friction (λ = 2.6), integrated analytically per frame straight into the offset state — no target is
    /// predetermined; the travel is v₀/λ. When the speed falls to the snap threshold, or the train reaches an
    /// end, the remainder (≤ ½ card) is snapped with the short curve and the focus is aligned unconditionally.
    private func startDeckMomentum(velocityPerSecond: CGFloat) {
        beginDeckScroll()
        deckMomentumActive = true
        deckMomentumVelocity = velocityPerSecond
        deckDriver.onTick = { [self] dt in deckMomentumTick(dt: dt) }
        deckDriver.start()
    }

    private func deckMomentumTick(dt: CGFloat) {
        let velocity = deckMomentumVelocity
        let step = DeckMath.momentumStep(offset: deckOffset, velocity: velocity, dt: dt)
        deckMomentumVelocity = step.velocity
        var next = step.offset
        let maxCards = CGFloat(games.count - 1)
        var hitBound = false
        if next <= 0, velocity < 0 {
            next = 0
            hitBound = true
        } else if next >= maxCards, velocity > 0 {
            next = maxCards
            hitBound = true
        }
        deckOffset = next
        let nearest = min(games.count - 1, max(0, Int(next.rounded())))
        if nearest != selectedIndex { select(games[nearest].id) }
        if hitBound {
            endDeckMomentum(snapTo: Int(next))
        } else if abs(deckMomentumVelocity) <= DeckMath.momentumSnapVelocity {
            endDeckMomentum(snapTo: nearest)
        }
    }

    /// Momentum's only normal exit: stop the driver, snap to the integer card and align the selection to the
    /// same index, unconditionally.
    private func endDeckMomentum(snapTo card: Int) {
        stopDeckMomentum()
        withAnimation(deckSettleAnimation(distanceCards: CGFloat(card) - deckOffset)) {
            deckOffset = CGFloat(card)
        }
        if games.indices.contains(card) { select(games[card].id) }
        finishDeckScroll(epoch: deckEpoch)
    }

    private func stopDeckMomentum() {
        deckDriver.stop()
        deckMomentumActive = false
        deckMomentumVelocity = 0
    }

    private func beginDeckScroll() {
        deckEpoch += 1
        deckIsSettled = false
    }

    private func finishDeckScroll(epoch: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            if deckEpoch == epoch { deckIsSettled = true }
        }
    }

    /// The offset restated as the selected index, without animation (appearance, list changes): the epoch bump
    /// also voids any in-flight settle timer, and the train counts as settled from this frame.
    private func snapDeckToFocus() {
        guard games.count <= 3, !deckDragging else { return }
        stopDeckMomentum()
        deckEpoch += 1
        deckIsSettled = true
        let target = CGFloat(selectedIndex)
        guard deckOffset != target else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { deckOffset = target }
    }

    /// An external selection change (D-pad, a tap elsewhere, the host) animates the train to match — never
    /// while the player's drag or the momentum driver owns the offset (the sync guard).
    private func syncDeckOffset() {
        guard games.count <= 3, !deckDragging, !deckMomentumActive else { return }
        let target = CGFloat(selectedIndex)
        guard abs(deckOffset - target) > 0.001 else { return }
        beginDeckScroll()
        withAnimation(deckSettleAnimation(distanceCards: target - deckOffset)) {
            deckOffset = target
        }
        finishDeckScroll(epoch: deckEpoch)
    }

    /// Whether a tap on the centred card may act now. On the carousel the scroll phases say so; on the shelf
    /// there are no phases, so the switch animation gets the same 0.32s grace as the deck.
    private var deckSettled: Bool {
        games.count <= 3 ? Date().timeIntervalSince(lastSwitchAt) >= 0.32 : settled
    }

    private func coverButton(_ detail: GameDetail, cover: CGFloat, onTapOverride: (() -> Void)? = nil) -> some View {
        let chosen = detail.id == selected.id
        return Button {
            // The deck train judges taps itself (see `deckTapCard`); the carousel path below is unchanged.
            if let onTapOverride {
                onTapOverride()
                return
            }
            // The centred card acts like the game's primary action — judged by the tap rule, not by what is
            // centred when the finger lifts: the touch froze the centred card when it began (`touchStartID`), so a
            // card that was a side card at touch-down only comes to the middle, even if it is centred by now; and
            // the centred card starts only if it was already centred at touch-down and the deck has settled — a
            // second tap inside the switch animation cannot start a game the player was still travelling to.
            if chosen {
                if (touchStartID ?? detail.id) == detail.id, deckSettled { primary(detail) }
                return
            }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { centredID = detail.id }
            select(detail.id)
        } label: {
            CoverView(game: detail.game, radius: cover * 0.03, showsState: true)
                .frame(width: cover, height: cover * 9 / 16)
                .shadow(color: .black.opacity(0.5), radius: cover * 0.05, y: cover * 0.03)
        }
        .buttonStyle(.plain)
        // A long press on a card: its settings and Delete game… (GameTileMenu).
        .modifier(GameTileMenu(detail: detail, select: select, openSettings: openSettings))
        .shellTarget("lib.tile.\(detail.id)", radius: cover * 0.03) { primary(detail) }
        .accessibilityLabel(detail.game.title + ", " + detail.game.state.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityHint(chosen ? detail.game.state.actionTitle : ShellStrings.text("Double-tap to select"))
        .accessibilityIdentifier("tile.\(detail.id)")
    }

    /// Under the centre card, the same on a phone and a tablet: the title with room for two lines, then one line of
    /// state. For a game that cannot start, that line is the way out: a small chip that says what is wrong and what to
    /// do. The reserved space stays fixed while the words follow the card nearest the centre.
    private func info(_ displayed: GameDetail, short: Bool, width: CGFloat) -> some View {
        let game = displayed.game
        let size: CGFloat = short ? 18 : 28
        return ZStack(alignment: .top) {
            VStack(spacing: 8) {
                Text("M\nM").shellType(ShellType.flowTitle(size))
                StateChip(game: game) {}.allowsHitTesting(false)
            }.hidden().accessibilityHidden(true)
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if game.showsNewNote { NewDot(size: max(8, size * 0.012)).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 } }
                    Text(game.title).shellType(ShellType.flowTitle(size))
                        .lineLimit(2).truncationMode(.tail).multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.35), radius: 10)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("hero.title")
                }
                // A ready game needs no words: its green dot says it. A game that cannot start gets one small line, its
                // way out in the state's colour. The space is reserved either way.
                if game.showsNewNote {
                    Text(ShellStrings.text("Installed – have fun!")).shellType(ShellType.button).foregroundStyle(.white.opacity(0.7))
                        .frame(minHeight: 34).accessibilityIdentifier("hero.new")
                } else if game.state == .playable {
                    Color.clear.frame(height: 34).accessibilityHidden(true)
                } else {
                    StateAction(game: game) { if settled { primary(displayed) } }
                }
            }
        }
        .frame(maxWidth: min(560, width - 48))
        .dynamicTypeSize(...(short ? DynamicTypeSize.xxLarge : DynamicTypeSize.accessibility1))
    }

    private var hints: some View {
        HStack(spacing: 24) {
            GlyphHint(role: .activate, label: selected.game.state.actionTitle)
            GlyphHint(role: .settings, label: ShellStrings.text("Game settings"))
            GlyphHint(role: .controllers, label: ShellStrings.text("Controllers"))
        }
        .frame(minHeight: 24)
        .accessibilityHidden(true)
    }
}

/// FlowTilt compresses distant card centres to 0.49 cover widths apart (1.04 stride minus 0.55 offset).
/// Distant centres also move 0.27 cover widths outwards. Full card bounds cover the tilt; one extra slot preloads each edge.
enum CoverFlowWindow {
    static func indices(count: Int, offset: CGFloat, width: CGFloat, cover: CGFloat) -> Range<Int> {
        guard count > 0, cover > 0, cover.isFinite, width.isFinite, offset.isFinite else { return 0..<0 }
        let centre = min(CGFloat(count - 1), max(0, offset / (cover * 1.04)))
        let radius = max(1, (max(0, width) / 2 + cover * 0.23) / (cover * 0.49)) + 1
        let lower = Int(max(0, floor(centre - radius)))
        let upper = Int(min(CGFloat(count), ceil(centre + radius) + 1))
        return lower..<upper
    }
}

enum CoverFlowSelection {
    static func game(games: [GameDetail], selected: GameDetail, offset: CGFloat, stride: CGFloat, scrolling: Bool) -> GameDetail {
        guard scrolling, !games.isEmpty, stride > 0, stride.isFinite, offset.isFinite else { return selected }
        let position = min(CGFloat(games.count - 1), max(0, (offset / stride).rounded()))
        return games[Int(position)]
    }
}

/// The way out for a game that cannot start, as one small tappable line in the state's colour: "How to fix ›".
/// VoiceOver reads the state with it.
struct StateAction: View {
    let game: GameTile
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                // Arriving: what is happening and how far, nothing to press. A stopped or failed install: what happened, then the way out.
                Text(game.state.isArriving ? game.state.title : game.state.installPhase != nil ? game.state.title + " · " + game.state.actionTitle : game.state.actionTitle)
                    .shellType(ShellType.button).monospacedDigit()
                if !game.state.isArriving { Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)) }
            }
            .foregroundStyle(game.state.color)
            .lineLimit(1)
            .padding(.horizontal, 12).frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(game.state.isArriving)
        .accessibilityLabel(game.state.title + ", " + game.state.actionTitle)
        .accessibilityIdentifier("state.chip")
        .shellTarget("lib.chip", radius: 17, action: action)
    }
}

/// What is wrong and what to do, as one small tappable line: "Game files damaged · How to fix".
struct StateChip: View {
    let game: GameTile
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(game.state.color).frame(width: 7, height: 7)
                Text(game.state.title.uppercased()).shellType(ShellType.eyebrow)
                    .foregroundStyle(game.state.color)
                Text("·").foregroundStyle(.white.opacity(0.4))
                Text(game.state.chipAction).shellType(ShellType.button)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).opacity(0.6)
            }
            .lineLimit(1)
            .padding(.horizontal, 14).frame(minHeight: 34)
            .background(.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
            .contentShape(Capsule().inset(by: -6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(game.state.title + ", " + game.state.actionTitle)
        .accessibilityIdentifier("state.chip")
        .shellTarget("lib.chip", radius: 17, action: action)
    }
}

/// Moves the carousel one card per gesture, like paging: a flick goes to the neighbour of the card the touch began on,
/// a slow drag settles on the card nearest the middle. The target is always a card close by, so the snap is short
/// instead of a long glide, and a second swipe that starts mid-snap counts from where the carousel is.
struct CardSnap: ScrollTargetBehavior {
    let stride: CGFloat
    let count: Int
    /// The card nearest the middle when the touch began.
    let start: Int
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let card = Self.card(target: target.rect.origin.x, velocity: context.velocity.dx, stride: stride, count: count, start: start)
        target.rect.origin.x = CGFloat(card) * stride
    }
    /// The card a gesture ends on. `target` is where the scroll would rest, in content points (0 with the first card in
    /// the middle), `velocity` the release speed in points per millisecond, positive toward the later cards.
    static func card(target: CGFloat, velocity: CGFloat, stride: CGFloat, count: Int, start: Int) -> Int {
        let nearest = Int((target / stride).rounded())
        let card: Int
        if velocity > flickVelocity { card = max(start + 1, min(nearest, start + 1)) }
        else if velocity < -flickVelocity { card = min(start - 1, max(nearest, start - 1)) }
        else { card = nearest }
        return min(count - 1, max(0, card))
    }
    /// Above this release speed (points per millisecond) the gesture counts as a flick.
    static let flickVelocity: CGFloat = 0.3
}

/// A card's turn by its place: up to 24 degrees back, smaller and darker, pulled in behind its nearer neighbour.
/// The nearer card is always drawn on top. Reduced motion keeps them flat.
private struct FlowTilt: ViewModifier {
    let place: CGFloat
    let cover: CGFloat
    let flat: Bool
    func body(content: Content) -> some View {
        let near = max(-1, min(1, place))
        // The tilt has its own, wider clamp: a card a place and a half away reaches the 45° cap,
        // while the scale and offset below keep the original ±1 `near`, byte for byte.
        let tilt = max(-1.5, min(1.5, place))
        let far = place > 1 ? place - 1 : place < -1 ? place + 1 : 0
        content
            .rotation3DEffect(.degrees(flat ? 0 : -tilt * 30), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .scaleEffect(1 - abs(near) * 0.22)
            .offset(x: -near * cover * 0.28 - far * cover * 0.55)
            .brightness(-abs(near) * 0.25 - min(abs(far), 1) * 0.1)
            .zIndex(-Double(abs(place)))
    }
}

/// The deck train's pure rules, as tuned for the shelf,
/// factored out so the probe can pin them numerically.
enum DeckMath {
    /// The landing card: logical offset plus a 220ms velocity projection, rounded, clamped only at the ends —
    /// a slow drag lands on the nearest card, a flick travels several. Velocities are in cards per millisecond.
    static func cardSnap(logicalCards: CGFloat, velocityCards: CGFloat, count: Int) -> Int {
        let projected = logicalCards + velocityCards * 220
        return min(count - 1, max(0, Int(projected.rounded())))
    }

    /// The display offset for a logical drag offset: 1:1 inside the range, the overshoot rubber-banded ×0.35.
    static func rubberBand(logical: CGFloat, count: Int) -> CGFloat {
        let maxCards = CGFloat(count - 1)
        if logical < 0 { return logical * 0.35 }
        if logical > maxCards { return maxCards + (logical - maxCards) * 0.35 }
        return logical
    }

    /// The true release velocity in cards per second, from the drag's last-120ms samples:
    /// DragGesture's own velocity is a whole-gesture damped average and understates a flick's tail speed by up
    /// to half. Falls back to the damped value when the window spans under 50ms or the slope points against it;
    /// the slope is clamped to ±60 cards/sec against sample noise only.
    static func releaseVelocity(samples: [(time: Date, logical: CGFloat)], endTime: Date, endLogical: CGFloat,
                                fallback: CGFloat) -> CGFloat {
        let window = samples.filter { endTime.timeIntervalSince($0.time) <= 0.12 }
        guard let first = window.first else { return fallback }
        let span = endTime.timeIntervalSince(first.time)
        guard span >= 0.05 else { return fallback }
        let slope = (endLogical - first.logical) / CGFloat(span)
        if fallback != 0, slope != 0, (slope > 0) != (fallback > 0) { return fallback }
        return min(60, max(-60, slope))
    }

    /// Momentum friction: v(t) = v₀·e^(−λt), total travel v₀/λ.
    static let momentumDecay: CGFloat = 2.6
    /// Below this speed (cards/sec) momentum hands over to the snap: the rest is at most half a card.
    static let momentumSnapVelocity: CGFloat = 1.2

    /// One momentum frame, solved analytically so the result is frame-rate independent:
    /// Δoffset = v/λ·(1 − e^(−λΔt)), and the velocity after the frame.
    static func momentumStep(offset: CGFloat, velocity: CGFloat, dt: CGFloat) -> (offset: CGFloat, velocity: CGFloat) {
        let decay = CGFloat(exp(Double(-momentumDecay * dt)))
        return (offset + velocity / momentumDecay * (1 - decay), velocity * decay)
    }
}

/// Every place-derived transform of one train card: the animatable data
/// is the train's shared offset itself, the index a fixed input, so a transaction animates exactly one scalar
/// and every property of every card is recomputed from the same interpolated offset each frame. The formulas
/// and their order are fixed (turn −clamp(place, ±1.5)×30° at perspective 0.45 
/// scale 1 − |near|×0.22, pull-in near×cover×0.28, far retreat far×cover×0.55, brightness, edge fade
/// |place| 2.0 → 2.8). The tap itself is not here: the card is a Button (see `coverButton`), which supplies
/// the content shape and the tap; plain views would carry an onTapGesture
/// instead — the one deliberate difference. Internal (not private) so the probe can render fractional-offset
/// states and verify every card's placement is a pure function of the one shared offset.
struct DeckCardTransform: ViewModifier {
    let index: Int
    var offset: CGFloat
    let width: CGFloat
    let stride: CGFloat
    let cover: CGFloat
    let areaH: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let place = CGFloat(index) - offset
        let near = max(-1, min(1, place))
        let tilt = max(-1.5, min(1.5, place))
        let far = place > 1 ? place - 1 : place < -1 ? place + 1 : 0
        let edgeOpacity = min(1, max(0, (2.8 - Double(abs(place))) / 0.8))
        return content
            .rotation3DEffect(.degrees(reduceMotion ? 0 : -tilt * 30), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .scaleEffect(1 - abs(near) * 0.22)
            .brightness(-abs(near) * 0.25 - min(abs(far), 1) * 0.1)
            .position(x: width / 2 + place * stride - near * cover * 0.28 - far * cover * 0.55, y: areaH / 2)
            .zIndex(-Double(abs(place)))
            .opacity(edgeOpacity)
            .allowsHitTesting(edgeOpacity > 0.05)
    }
}

/// The Animatable conformance, isolated to the main actor: this module's types are main-actor isolated by
/// default. SwiftUI drives the modifier on the
/// main actor, so the isolated conformance is the one it consumes.
extension DeckCardTransform: @MainActor Animatable {
    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }
}

/// The momentum driver's frame clock: a CADisplayLink feeding dt in
/// seconds (the first frame only records the time; dt is clamped to 0.05). `start` only invalidates the old
/// clock and never clears `onTick` — the caller's contract is to assign `onTick` first and then start; `stop`
/// is the only place that clears it, breaking the driver → closure → state cycle. (Clearing it in `start`
/// (the driver spun with no callback and flicks froze mid-train.) On macOS the
/// target/selector display link does not exist, so a 120Hz run-loop timer feeds the same tick contract —
/// the only platform difference, and the integration math (DeckMath) is identical.
@MainActor
private final class DeckMomentumDriver: NSObject {
    private var displayLink: CADisplayLink?
    private var timer: Timer?
    private var lastTimestamp: CFTimeInterval = 0
    var onTick: ((CGFloat) -> Void)?

    func start() {
        invalidateClock()
        lastTimestamp = 0
        #if canImport(UIKit)
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        #else
        let timer = Timer(timeInterval: 1.0 / 120, target: self, selector: #selector(stepTimer),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        #endif
    }

    func stop() {
        invalidateClock()
        onTick = nil
    }

    private func invalidateClock() {
        displayLink?.invalidate()
        displayLink = nil
        timer?.invalidate()
        timer = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        tick(now: link.timestamp)
    }

    @objc private func stepTimer() {
        tick(now: Date().timeIntervalSinceReferenceDate)
    }

    private func tick(now: CFTimeInterval) {
        if lastTimestamp == 0 {
            lastTimestamp = now
            return
        }
        let dt = CGFloat(now - lastTimestamp)
        lastTimestamp = now
        onTick?(min(dt, 0.05))
    }
}

/// The blurred cover behind Cover Flow. It crossfades as the middle cover changes.
struct CoverFlowBackdrop: View {
    let game: GameTile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            ShellPalette.background
            ArtView(game: game, backdrop: true)
                .scaleEffect(1.3)
                .blur(radius: 60, opaque: true)
                .saturation(1.25)
                .opacity(0.75)
                .id(game.id)
                .transition(.opacity)
            // Darker toward the edges and the bottom, so the type and the covers keep their contrast.
            RadialGradient(colors: [.clear, ShellPalette.background.opacity(0.75)], center: .init(x: 0.5, y: 0.4),
                           startRadius: 80, endRadius: 900)
            LinearGradient(colors: [.black.opacity(0.25), .clear, ShellPalette.background.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(reduceMotion ? .linear(duration: 0.2) : .easeInOut(duration: 0.45), value: game.id)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The controller count on top of art, which opens Controllers.
struct ControllerChip: View {
    let count: Int
    /// In the side column (SideBar): the count under the symbol, so the chip is as narrow as the gear.
    var vertical = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Image(systemName: count == 0 ? "gamecontroller" : "gamecontroller.fill")
                Text("\(count)").monospacedDigit()
            }
            .frame(width: vertical ? SideBar.chipWidth - 28 : nil, height: vertical ? SideBar.heights[0] : nil)
        }
        .buttonStyle(ChipButtonStyle())
        .accessibilityLabel(ShellStrings.text("Controllers") + ", \(count)")
        .accessibilityIdentifier("controllers.open")
        .shellTarget("lib.controllers", radius: 22, action: action)
    }
}

/// The gear at the top-right corner, which opens the shell's own settings.
struct ShellSettingsChip: View {
    var vertical = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape").frame(minWidth: 18)
                .frame(width: vertical ? SideBar.chipWidth - 28 : nil, height: vertical ? SideBar.heights[1] : nil)
        }
            .buttonStyle(ChipButtonStyle())
            .accessibilityLabel(ShellStrings.text("Settings"))
            .accessibilityIdentifier("shellSettings.open")
            .shellTarget("lib.shellSettings", radius: 22, action: action)
    }
}
