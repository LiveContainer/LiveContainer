// S2Arm modification: present a dedicated sorting list and guard background library input while it is open.
import SwiftUI

/// How the library arranges itself. Only the available size decides, never the device model or orientation,
/// so a Stage Manager window, Split View and a foldable opening while the app runs all follow the same rules.
enum ShellLayout: Equatable {
    /// Compact and taller than wide: one column, settings over the whole library when asked for.
    case column
    /// Regular width and height, not wide: the library alone with a grid of cards, settings as a panel when asked for.
    case grid
    /// Wider than tall: Cover Flow. Settings as a panel on the right (regular) or over the whole library (compact).
    case coverFlow(regular: Bool)

    static func resolve(_ size: CGSize, accessibilityText: Bool) -> ShellLayout {
        let regular = size.width >= 600 && size.height >= 500
        if size.width > size.height * 1.2 { return .coverFlow(regular: regular) }
        return regular && !accessibilityText ? .grid : .column
    }

    /// The widest the overlay Settings and Controllers get: a panel from the trailing edge over the dimmed library.
    static let overlayWidth: CGFloat = 520
    /// Fork difference (kept across upstream syncs): a landscape panel on a phone is capped well under the 520,
    /// following the NX2/GameCase rule — at the full width it took three fifths of the screen and its rows
    /// stretched. `width` here is the safe-area width, so this is min(520, screen width × 0.44 less the safe
    /// area); tablets and regular windows keep the 520.
    func overlayWidth(_ width: CGFloat) -> CGFloat {
        if case .coverFlow(let regular) = self, !regular { return min(Self.overlayWidth, width * 0.44) }
        return Self.overlayWidth
    }
    /// Settings drop in as that overlay wherever the library stays in view beside it (at least 120 points of it), and
    /// take the whole screen where it would not: a phone held upright, a folded foldable, a narrow window.
    /// The float threshold stays on the 520 cap, as before.
    func settingsFloat(_ width: CGFloat) -> Bool { self != .column && width >= Self.overlayWidth + 120 }
    /// The settings' width: the overlay, or the whole width.
    func paneWidth(_ width: CGFloat) -> CGFloat { settingsFloat(width) ? min(width, overlayWidth(width)) : width }
    var isCoverFlow: Bool { if case .coverFlow = self { true } else { false } }
}

/// A presentation-only shell. Selection, focus, navigation and scroll positions are local UI state.
/// All game effects are supplied by the host through actions.
public struct LibraryView: View {
    public let games: [GameDetail]
    public let controllers: [ControllerInfo]
    public let globalPadMap: PadMap
    /// The controller's state while the button test is open, from the host.
    public let padSnapshot: PadSnapshot?
    public var actions: ShellActions
    public var input: ShellInputLog
    /// The sequence of the last input event acted on.
    @State private var inputSeen: Int
    @State private var selectedID: String?
    @State private var settingsOpen: Bool
    /// The settings pane has finished sliding in: its focus ring shows only then, not ahead of it where it will stop.
    @State private var settingsArrived: Bool
    /// Counts the opening and closing of the settings pane, so a wait for one opening does not act on a later one.
    @State private var settingsOpenings = 0
    @State private var shellSettingsOpen: Bool
    @State private var controllersOpen: Bool
    /// The game whose How to fix or How to update explanation is open.
    @State private var helpGameID: String?
    /// The game whose Delete question is open, and whether its saves go too.
    @State private var deleteGameID: String?
    @State private var deleteSaves = false
    /// The choice whose option list is open.
    @State private var choice: ChoiceRequest?
    /// The button-mapping card, while open.
    @State private var padMapping: PadMappingState?
    @State private var buttonTestOpen: Bool
    /// The touch controls' layout editor, while open (over the shell settings).
    @State private var touchLayout: TouchLayoutEditorModel?
    @State private var focus: FocusAppearance
    @State private var targets = FocusTargetBuffer()
    @State private var settingsPosition = ScrollPosition()
    /// How far the left-edge swipe has dragged the open settings or Controllers to the right.
    @State private var edgeDrag: CGFloat = 0
    @State private var libraryPosition = ScrollPosition()
    @State private var gameOrderOpen = false
    @State private var layout: ShellLayout = .column
    @State private var returnFocus: String?
    /// The device that sent the last input, for the glyphs.
    @State private var device: InputDevice = .controller(.neutral)
    /// True after a touch: the controller hints and the focus ring step back until the next controller or key press.
    @State private var touchMode: Bool
    @State private var gate = InputGate()
    @FocusState private var keyboardFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The side column of iPhone Duo (#622): the captures set it, otherwise the system's values from SideBarProbe.
    @Environment(\.shellSideBar) private var sideBarOverride
    @State private var probedSideBar = SideBar(edge: nil)
    /// S2Arm (#623): the player chip, when the host has players; it takes a place in the side column too.
    @Environment(\.shellPlayer) private var shellPlayer

    public init(games: [GameDetail], controllers: [ControllerInfo] = [], actions: ShellActions = ShellActions(),
                input: ShellInputLog = ShellInputLog(), initialSelection: String? = nil, initialDetailOpen: Bool = false,
                initialControllersOpen: Bool = false, initialShellSettingsOpen: Bool = false, initialFocusVisible: Bool = false,
                globalPadMap: PadMap = PadMap(), padSnapshot: PadSnapshot? = nil,
                initialPadMapping: String? = nil, initialButtonTestOpen: Bool = false) {
        self.games = games
        self.controllers = controllers
        self.globalPadMap = globalPadMap
        self.padSnapshot = padSnapshot
        _padMapping = State(initialValue: initialPadMapping.map { PadMappingState(gameID: $0) })
        _buttonTestOpen = State(initialValue: initialButtonTestOpen)
        self.actions = actions
        self.input = input
        _inputSeen = State(initialValue: input.last)
        let first = initialSelection ?? games.first?.id
        _selectedID = State(initialValue: first)
        _settingsOpen = State(initialValue: initialDetailOpen)
        _settingsArrived = State(initialValue: initialDetailOpen)
        _controllersOpen = State(initialValue: initialControllersOpen)
        _shellSettingsOpen = State(initialValue: initialShellSettingsOpen)
        _focus = State(initialValue: FocusAppearance(id: initialFocusVisible ? "lib.tile.\(first ?? "")" : nil, visible: initialFocusVisible))
        _touchMode = State(initialValue: !initialFocusVisible)
    }
    private var selected: GameDetail? { games.first { $0.id == selectedID } ?? games.first }

    public var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let whole = CGSize(width: geometry.size.width + insets.leading + insets.trailing,
                               height: geometry.size.height + insets.top + insets.bottom)
            let layout = ShellLayout.resolve(whole, accessibilityText: typeSize.isAccessibilitySize)
            let width = geometry.size.width
            let pane = layout.paneWidth(width)
            // The Controllers and shell-settings overlays share the settings pane's width rule.
            let overlay = min(width, layout.overlayWidth(width))
            // Settings only when asked for. A panel floats over the dimmed library where there is room, otherwise the
            // settings take the whole screen and the library steps out of the way.
            let floating = layout.settingsFloat(width)
            let paneCovers = settingsOpen && !floating
            let panelOverLibrary = settingsOpen && floating
            // The chips go into the side column where the system has one. At the accessibility text sizes they stay in the header.
            let side = typeSize.isAccessibilitySize ? nil : (sideBarOverride ?? probedSideBar)
                .place(screen: whole, insets: insets, bottom: shellPlayer == nil ? SideBar.heights : [SideBar.playerHeight] + SideBar.heights,
                       top: games.isEmpty ? [] : SideBar.topHeights)
            let column = side?.bottom
            ZStack(alignment: .topLeading) {
                if layout.isCoverFlow, let selected { CoverFlowBackdrop(game: selected.game) } else { ShellPalette.background.ignoresSafeArea() }
                if games.isEmpty {
                    EmptyLibraryView()
                        .overlay(alignment: .top) {   // S2Arm: the version for screenshots and the player (#623), level with the chips
                            HStack(spacing: 10) {
                                LibraryVersionBadge().layoutPriority(-1)
                                Spacer(minLength: 8)
                                if column == nil {
                                    PlayerChip()
                                    ControllerChip(count: controllers.count, action: openControllers)
                                    ShellSettingsChip(action: openShellSettings)
                                }
                            }
                            .frame(minHeight: 44).padding(.top, 6).padding(.leading, 24).padding(.trailing, 16)
                        }
                    if let column { sideChips(column, insets: insets) }
                } else if let selected {
                    library(selected, layout: layout, size: geometry.size, insets: insets, chipsInSideBar: column != nil,
                            settingsInSideBar: side?.top != nil)
                        .frame(width: width, height: geometry.size.height)
                        .opacity(paneCovers && edgeDrag == 0 ? 0 : 1)
                        .allowsHitTesting(!settingsOpen)
                        .accessibilityHidden(settingsOpen || helpGameID != nil || deleteGameID != nil)
                    if let side {
                        Group {
                            sideChips(side.bottom, insets: insets)
                            if let top = side.top, !settingsOpen {
                                SideBarTopChip(symbol: "slider.horizontal.3", label: ShellStrings.text("Game settings") + ", " + selected.game.title,
                                               identifier: "settings.open", target: "lib.settings", action: openSettings)
                                    .sideBarFrame(top, insets: insets)
                            }
                        }
                        .opacity(paneCovers && edgeDrag == 0 ? 0 : 1)
                        .allowsHitTesting(!settingsOpen)
                        .accessibilityHidden(settingsOpen || helpGameID != nil || deleteGameID != nil)
                    }
                    if panelOverLibrary {
                        // The same dimming and dismissal as the Controllers overlay.
                        Color.black.opacity(0.55 * (settingsOpen && !controllersOpen ? 1 - min(1, edgeDrag / pane) : 1)).ignoresSafeArea()
                            .onTapGesture { closeSettings() }
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                    // One settings view in one place for every layout, so its state, scroll position and focus survive
                    // a fold, a rotation or a Stage Manager resize.
                    settingsPane(selected, floating: floating, width: pane, backInSideBar: side?.top != nil,
                                 insets: floating ? EdgeInsets(top: insets.top, leading: 0, bottom: insets.bottom, trailing: insets.trailing)
                                                  : insets)
                        .transformEnvironment(\.shellFocus) { if !settingsArrived { $0.visible = false } }
                        .frame(width: pane)
                        .frame(maxHeight: .infinity)
                        // Presented like Controllers: the page colour edge to edge, a hairline toward the library.
                        .background { ShellPalette.background.ignoresSafeArea() }
                        .overlay(alignment: .leading) {
                            if floating { Rectangle().fill(ShellPalette.hairline).frame(width: 1).ignoresSafeArea() }
                        }
                        .offset(x: settingsOpen ? (controllersOpen ? 0 : edgeDrag) : pane + 40)
                        .opacity(settingsOpen ? 1 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .allowsHitTesting(settingsOpen)
                        .accessibilityHidden(!settingsOpen || choice != nil || padMapping != nil || deleteGameID != nil)
                        .accessibilityAddTraits(settingsOpen ? .isModal : [])
                    if let top = side?.top, settingsOpen {
                        // Back at the top of the side column, where the system's bars put an app's own navigation.
                        SideBarTopChip(symbol: "chevron.left", label: ShellStrings.text("Library"), identifier: "library.back",
                                       target: "set.back", action: closeSettings)
                            .sideBarFrame(top, insets: insets)
                            .opacity(1 - min(1, edgeDrag / pane))
                            .accessibilityHidden(choice != nil || padMapping != nil || deleteGameID != nil)
                    }
                }
                // Every dialog and panel above the library keeps its place while it goes: a ZStack child that is
                // removed loses its order, and its exit (the slide out of Controllers and the shell settings) played
                // behind the library, so it looked cut off.
                if let id = helpGameID, let game = games.first(where: { $0.id == id })?.game { Group {
                    Color.black.opacity(0.55).ignoresSafeArea().accessibilityHidden(true)
                        .onTapGesture { closeHelp() }
                        .transition(.opacity)
                    StateHelpView(game: game, actions: guardedActions, onClose: closeHelp)
                        .frame(maxWidth: 460)
                        .background(Color(red: 0.075, green: 0.075, blue: 0.082), in: RoundedRectangle(cornerRadius: 26))
                        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.10)))
                        .shadow(color: .black.opacity(0.5), radius: 40)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityAddTraits(.isModal)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }.zIndex(1) }
                if let id = deleteGameID, let game = games.first(where: { $0.id == id })?.game { Group {
                    Color.black.opacity(0.55).ignoresSafeArea().accessibilityHidden(true)
                        .onTapGesture { closeDelete() }
                        .transition(.opacity)
                    DeleteGameView(game: game, saves: Binding(get: { deleteSaves }, set: { if !fromSystemEcho { deleteSaves = $0 } }), delete: { confirmDelete(id) }, cancel: closeDelete)
                        .frame(maxWidth: 460)
                        .background(Color(red: 0.075, green: 0.075, blue: 0.082), in: RoundedRectangle(cornerRadius: 26))
                        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.10)))
                        .shadow(color: .black.opacity(0.5), radius: 40)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityAddTraits(.isModal)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }.zIndex(2) }
                if controllersOpen { Group {
                    Color.black.opacity(0.55 * (1 - min(1, edgeDrag / overlay))).ignoresSafeArea().accessibilityHidden(true)
                        .onTapGesture { back() }
                    ControllersView(controllers: controllers, onBack: back, padMap: globalPadMap, showsMapping: actions.onGlobalPadMapChange != nil)
                        .accessibilityHidden(choice != nil || padMapping != nil || buttonTestOpen)
                        .frame(width: overlay)
                        .frame(maxHeight: .infinity)
                        .background { ShellPalette.background.ignoresSafeArea() }
                        .overlay(alignment: .leading) { Rectangle().fill(ShellPalette.hairline).frame(width: 1).ignoresSafeArea() }
                        .offset(x: edgeDrag)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityAddTraits(.isModal)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }.zIndex(3) }
                if shellSettingsOpen { Group {
                    Color.black.opacity(0.55 * (1 - min(1, edgeDrag / overlay))).ignoresSafeArea().accessibilityHidden(true)
                        .onTapGesture { back() }
                    ShellSettingsView(actions: guardedActions, onClose: closeShellSettings)
                        .frame(width: overlay)
                        .frame(maxHeight: .infinity)
                        .background { ShellPalette.background.ignoresSafeArea() }
                        .overlay(alignment: .leading) { Rectangle().fill(ShellPalette.hairline).frame(width: 1).ignoresSafeArea() }
                        .offset(x: edgeDrag)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityHidden(touchLayout != nil)
                        .accessibilityAddTraits(.isModal)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }.zIndex(4) }
                if let touchLayout { Group {
                    // The whole screen, so the preview is as large as the device allows.
                    ShellPalette.background.ignoresSafeArea().accessibilityHidden(true)
                    TouchLayoutEditorView(model: touchLayout, close: closeTouchLayout)
                        .accessibilityAddTraits(.isModal)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }.zIndex(5) }
                if let choice { Group {
                    Color.black.opacity(0.55).ignoresSafeArea().accessibilityHidden(true)
                        .onTapGesture { closeChoice() }
                        .transition(.opacity)
                    ChoicePickerView(request: choice, pick: pickChoice, close: closeChoice)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }.zIndex(6) }
                if let padMapping { Group {
                    Color.black.opacity(0.55).ignoresSafeArea().accessibilityHidden(true)
                        .onTapGesture { closePadMapping() }
                        .transition(.opacity)
                    PadMappingCard(title: padMappingTitle(padMapping.gameID), rows: padMappingRows(padMapping.gameID),
                                   inherited: padMapping.gameID == ControllersView.mappingID ? nil : globalPadMap, openRow: padMapping.row,
                                   open: openPadRow, pick: pickPadValue, backToList: closePadRow, reset: resetPadMapping, close: closePadMapping)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }.zIndex(7) }
                if buttonTestOpen { Group {
                    Color.black.opacity(0.7).ignoresSafeArea().accessibilityHidden(true)
                        .onTapGesture { closeButtonTest() }
                        .transition(.opacity)
                    ButtonTestView(snapshot: padSnapshot, close: closeButtonTest)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }.zIndex(8) }
            }
            .coordinateSpace(name: "shell")
            .background { SideBarProbe { probedSideBar = $0 }.ignoresSafeArea().accessibilityHidden(true) }
            .environment(\.shellOpenTouchLayout, { openTouchLayout(whole, insets) })
            .background {
                EdgeSwipeBack(enabled: (settingsOpen || controllersOpen || shellSettingsOpen) && choice == nil && helpGameID == nil && deleteGameID == nil
                                  && padMapping == nil && !buttonTestOpen && touchLayout == nil,
                              changed: { edgeDrag = $0 },
                              ended: { finishEdgeSwipe(travel: $0, velocity: $1, span: controllersOpen || shellSettingsOpen ? overlay : pane) },
                              cancelled: cancelEdgeSwipe)
            }
            // Every target on screen. Which of them the D-pad reaches is decided when it is used (`isLive`), from the
            // state at that moment: a filter here would run only when some target changes, and closing a panel changes
            // none, so the closed panel's targets stayed and the focus on the button that opened it was taken for lost.
            .onPreferenceChange(FocusTargets.self) { all in targets.values = all.filter { $0.frame.width > 1 } }
            .onAppear { self.layout = layout }
            .onChange(of: layout) { _, new in self.layout = new }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: layout)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: settingsOpen)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: controllersOpen)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: shellSettingsOpen)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: helpGameID)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: deleteGameID)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: choice)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: padMapping)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: buttonTestOpen)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: touchLayout != nil)
        .environment(\.shellPickChoice, { request in openChoice(request) })
        .environment(\.shellOpenPadMapping, { id in openPadMapping(id) })
        .environment(\.shellOpenButtonTest, { openButtonTest() })
        .environment(\.shellIgnoresPress, { [gate] in gate.isSystemEcho })
        .environment(\.shellShowHelp, { game in openHelp(game.id) })
        .environment(\.shellAskDelete, actions.onDeleteGame == nil ? nil : { game in openDelete(game.id) })
        .environment(\.shellManageSaves, guardedActions.onManageSaves)
        .environment(\.shellOpenGameOrder, actions.onReorderGames == nil ? nil : {
            guard libraryPressAllowed, noteTouch() else { return }
            gameOrderOpen = true
        })
        #if os(iOS)
        .fullScreenCover(isPresented: $gameOrderOpen) {
            GameOrderView(games: games, reorder: actions.onReorderGames)
                .preferredColorScheme(.dark)
        }
        #else
        .sheet(isPresented: $gameOrderOpen) {
            GameOrderView(games: games, reorder: actions.onReorderGames)
                .preferredColorScheme(.dark)
        }
        #endif
        .environment(\.shellFocus, focus)
        .environment(\.shellInputDevice, device)
        .foregroundStyle(.white)
        .font(ShellFonts.font(15)).tint(ShellPalette.cream).preferredColorScheme(.dark)
        .onChange(of: input) { _, log in
            // Every event since the last update, in order: several can come between two updates.
            for event in log.since(inputSeen) {
                // A button let go only restarts the window for the system's echo, which comes as the button comes up.
                if event.released { if case .controller = event.device { gate.controllerUp(event.action) }; continue }
                handle(event.action, from: event.device)
            }
            inputSeen = log.last
        }
        // A hardware keyboard, as on the Mac: arrows move, Return activates, Escape goes back, O opens game settings,
        // Y opens controllers.
        .focusable().focused($keyboardFocus).focusEffectDisabled()
        .onAppear { keyboardFocus = true }
        // The host's Home Screen quick action Settings: the library's own settings, the same as its gear button
        .onReceive(NotificationCenter.default.publisher(for: .shellOpenSettings)) { _ in openShellSettings() }
        .onAnyTouch { gate.touch() }
        .onKeyPress(.leftArrow) { handle(.left, from: .keyboard); return .handled }
        .onKeyPress(.rightArrow) { handle(.right, from: .keyboard); return .handled }
        .onKeyPress(.upArrow) { handle(.up, from: .keyboard); return .handled }
        .onKeyPress(.downArrow) { handle(.down, from: .keyboard); return .handled }
        .onKeyPress(.return) { handle(.activate, from: .keyboard); return .handled }
        .onKeyPress(.escape) { handle(.back, from: .keyboard); return .handled }
        .onKeyPress("o") { handle(.settings, from: .keyboard); return .handled }
        .onKeyPress("y") { handle(.controllers, from: .keyboard); return .handled }
        .onDisappear { targets.values.removeAll() }
        .onChange(of: settingsOpen) { _, open in
            settingsArrived = false
            settingsOpenings += 1
            guard open else { return }
            // The pane slides in over 0.3 s (the animation on settingsOpen). Only for this opening: closed and opened
            // again within the 0.3 s, the first opening's wait would show the ring while the pane still slides.
            let opening = settingsOpenings
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.3)) {
                if settingsOpen && settingsOpenings == opening { settingsArrived = true }
            }
        }
        .onChange(of: games.map(\.id)) { _, ids in
            if !ids.contains(selectedID ?? "") { selectedID = ids.first; settingsOpen = false }
        }
    }

    /// The Controllers and Settings chips in the side column, `column` in the screen's coordinates.
    private func sideChips(_ column: CGRect, insets: EdgeInsets) -> some View {
        SideBarChips(controllers: controllers.count, openControllers: openControllers, openShellSettings: openShellSettings)
            .sideBarFrame(column, insets: insets)
    }

    @ViewBuilder private func library(_ selected: GameDetail, layout: ShellLayout, size: CGSize, insets: EdgeInsets,
                                      chipsInSideBar: Bool, settingsInSideBar: Bool) -> some View {
        if layout.isCoverFlow {
            CoverFlowView(games: games, selected: selected, controllers: controllers.count, showsHints: !touchMode, screenInsets: insets,
                          chipsInSideBar: chipsInSideBar, settingsInSideBar: settingsInSideBar,
                          select: select, primary: primary, openSettings: openSettings, openControllers: openControllers,
                          openShellSettings: openShellSettings)
                .equatable()
                .transition(.opacity)
        } else {
            PortraitLibrary(games: games, selected: selected, wide: layout == .grid, size: size, topInset: insets.top, bottomInset: insets.bottom,
                            chipsInSideBar: chipsInSideBar, settingsInSideBar: settingsInSideBar,
                            controllers: controllers.count, select: select, primary: primary,
                            openSettings: openSettings, openControllers: openControllers, openShellSettings: openShellSettings,
                            position: $libraryPosition)
                .equatable()
                .transition(.opacity)
        }
    }

    /// The settings for the selected game: its banner as the header, with the title over it and Back on top, then
    /// the primary action and the setting groups. A panel or the whole screen, the same view.
    /// The settings for the selected game: its banner as the header, with the title below it and Back on top, then
    /// the primary action and the setting groups. A panel or the whole screen, the same view. The banner runs edge to
    /// edge under the status bar and the settings scroll under the home indicator, while Back, the words and the
    /// settings keep their insets.
    private func settingsPane(_ selected: GameDetail, floating: Bool, width: CGFloat, backInSideBar: Bool, insets: EdgeInsets) -> some View {
        return ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PaneBanner(game: selected.game, width: width + insets.leading + insets.trailing,
                                   leading: insets.leading, trailing: insets.trailing, topInset: insets.top).id("set.top")
                        GameDetailView(detail: selected, actions: guardedActions, showsPrimaryAction: true, showsHeader: false)
                            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 32 + insets.bottom)
                            // A phone on its side: a readable column, not rows stretched across the whole width.
                            .frame(maxWidth: 640, alignment: .leading)
                            // A floating pane sits on the screen's trailing edge, so the window's trailing
                            // safe inset is positional — the pane's own frame already ends at the safe edge,
                            // and padding the content by that inset a second time stacks 59pt of dead space
                            // on the trailing side only (device-measured: card margins 24 leading / 83
                            // trailing). Inside a floating pane the horizontal margins are the content's
                            // own 24 on both sides; the banner above still bleeds edge to edge with the
                            // full insets. Full-screen panes keep the insets. (The same ruling GameCase's
                            // settings column ships with.)
                            .padding(.leading, floating ? 0 : insets.leading)
                            .padding(.trailing, floating && !SensorEdge.onTrailing ? 0 : insets.trailing)   // 灵动岛转到右边时照扣，不然右侧开关被它盖住（SensorEdge）
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollPosition($settingsPosition)
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .all)
                .onChange(of: focus.id) { _, id in
                    guard let id, id.hasPrefix("set.") else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: id == "set.back" ? .top : .center)
                    }
                }
            }
            // In the side column (SideBar) Back sits at the column's top instead.
            if !backInSideBar { HStack(spacing: 0) {
                Button(action: closeSettings) {
                    if typeSize.isAccessibilitySize { Image(systemName: "chevron.left").frame(minWidth: 24) }
                    else { Label(ShellStrings.text("Library"), systemImage: "chevron.left") }
                }
                .buttonStyle(ChipButtonStyle())
                .accessibilityLabel(ShellStrings.text("Library"))
                .accessibilityIdentifier("library.back")
                .shellTarget("set.back", radius: 22, action: closeSettings)
                Spacer(minLength: 0)
            }
            .padding(.leading, 16 + insets.leading).padding(.trailing, 16 + insets.trailing)
            .padding(.top, 6)
            .accessibilityElement(children: .contain) }
        }
    }

    // MARK: Actions and focus

    /// The system's echo of a controller button (see `SystemEchoWindow`), for the actions that close or go back: they
    /// do not change the touch mode, but the echo must not close the panel the button just opened.
    private var fromSystemEcho: Bool { gate.isSystemEcho }
    /// `actions` for the views that change settings or data themselves (a switch, a row, a button in the settings): the
    /// system's echo of a controller button changes nothing through them.
    private var guardedActions: ShellActions {
        let gate = gate
        func echo() -> Bool { gate.isSystemEcho }
        var a = actions
        let o = actions
        a.onSelect = { if !echo() { o.onSelect($0) } }
        a.onPlay = { if !echo() { o.onPlay($0) } }
        a.onChange = { if !echo() { o.onChange($0, $1, $2) } }
        a.onPickGameData = { if !echo() { o.onPickGameData($0) } }
        a.onUseAppData = o.onUseAppData.map { act in { if !echo() { act($0) } } }
        a.onPickCloudSaves = o.onPickCloudSaves.map { act in { if !echo() { act($0) } } }
        a.onDisableCloudSaves = o.onDisableCloudSaves.map { act in { if !echo() { act($0) } } }
        a.onResetDefaults = o.onResetDefaults.map { act in { if !echo() { act($0) } } }
        a.onShowLog = o.onShowLog.map { act in { if !echo() { act($0) } } }
        a.onAppUpdate = o.onAppUpdate.map { act in { if !echo() { act() } } }
        a.onPickShellData = o.onPickShellData.map { act in { if !echo() { act() } } }
        a.onPickShellCloud = o.onPickShellCloud.map { act in { if !echo() { act() } } }
        a.onUseShellCloud = o.onUseShellCloud.map { act in { if !echo() { act($0) } } }
        a.onClearShellData = o.onClearShellData.map { act in { if !echo() { act() } } }
        a.onClearShellCloud = o.onClearShellCloud.map { act in { if !echo() { act() } } }
        a.onReportProblem = o.onReportProblem.map { act in { if !echo() { act() } } }
        a.onGlobalPadMapChange = o.onGlobalPadMapChange.map { act in { if !echo() { act($0, $1) } } }
        a.onGlobalPadMapReset = o.onGlobalPadMapReset.map { act in { if !echo() { act() } } }
        a.onDeleteGame = o.onDeleteGame.map { act in { if !echo() { act($0, $1) } } }
        a.onManageSaves = o.onManageSaves.map { act in { if !echo() { act($0) } } }
        return a
    }
    /// An action that did not come from a controller or key came from touch: hints and focus ring step back. False when
    /// it came from neither but is the system's echo of a controller button (see `SystemEchoWindow`): the shell's own
    /// focus already took that button, so the press is not acted on.
    private func noteTouch() -> Bool {
        guard !gate.handling else { return true }
        if gate.isSystemEcho { return false }
        if !touchMode { touchMode = true }
        if focus.visible { focus.visible = false }
        return true
    }
    /// A press on the library's own buttons that the shell may act on: from `handle`, or with nothing over the library.
    /// Under a dialog or a panel no finger reaches the library (it takes no hits there), so a press on its buttons is the
    /// system's echo of a controller button, whatever the window says: a finger that came down elsewhere just before the
    /// echo (a tap in the settings pane right after A) ends the window, and Play behind the pane started the game.
    private var libraryPressAllowed: Bool { !gameOrderOpen && FocusLayer.libraryTakesPress(fromShell: gate.handling, under: topLayer) }
    private func primary(_ detail: GameDetail) {
        guard libraryPressAllowed, noteTouch() else { return }
        if detail.game.state.needsHelp { openHelp(detail.id); return }
        switch detail.game.state {
        case .playable: actions.onPlay(detail.id)
        case .needsGameData: actions.onPickGameData(detail.id)
        case .needsAppUpdate: actions.onAppUpdate?()
        case .broken: actions.onShowLog?(detail.id)
        case .installing(let stage): if stage.phase == .failed { actions.onPlay(detail.id) }   // 重试解开；传着 / 解着按了不动
        }
    }
    private func select(_ id: String) {
        guard libraryPressAllowed, noteTouch() else { return }
        guard id != selectedID else { return }
        selectedID = id
        actions.onSelect(id)
        settingsPosition.scrollTo(edge: .top)
    }
    /// The swipe lets go: past a third of the panel or flung to the right, it finishes the slide out from where the
    /// finger is and then closes without a second animation. Otherwise the panel springs back.
    private func finishEdgeSwipe(travel: CGFloat, velocity: CGFloat, span: CGFloat) {
        guard travel > span / 3 || velocity > 600 else { cancelEdgeSwipe(); return }
        let close = {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { back(); edgeDrag = 0 }
        }
        if reduceMotion { close(); return }
        withAnimation(.smooth(duration: 0.25), completionCriteria: .logicallyComplete) { edgeDrag = span + 40 } completion: { close() }
    }
    private func cancelEdgeSwipe() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { edgeDrag = 0 }
    }
    private func openSettings() {
        guard !shellSettingsOpen else { return }
        guard noteTouch() else { return }
        settingsOpen = true
        focus.id = "set.back"
    }
    private func closeSettings() {
        guard !fromSystemEcho else { return }
        settingsOpen = false
        focus.id = "lib.settings"
    }
    private func openControllers() { guard !shellSettingsOpen else { return }; guard noteTouch() else { return }; controllersOpen = true; focus.id = "ctl.close" }
    private func openShellSettings() { guard noteTouch() else { return }; shellSettingsOpen = true; focus.id = "shs.close" }
    private func closeShellSettings() { guard !fromSystemEcho else { return }; shellSettingsOpen = false; focus.id = "lib.shellSettings" }
    private func openTouchLayout(_ window: CGSize, _ insets: EdgeInsets) {
        guard noteTouch() else { return }
        touchLayout = TouchLayoutEditorModel.forDevice(window: window, insets: insets)
        focus.id = "lay.done"
    }
    private func closeTouchLayout() { guard !fromSystemEcho else { return }; touchLayout = nil; focus.id = "shs.arrange" }
    private func openHelp(_ id: String) { guard !fromSystemEcho else { return }; returnFocus = focus.id; helpGameID = id; focus.id = "help.done" }
    private func closeHelp() { guard !fromSystemEcho else { return }; helpGameID = nil; focus.id = returnFocus }
    /// The question starts on Cancel, with the saves kept.
    private func openDelete(_ id: String) { guard noteTouch() else { return }; returnFocus = focus.id; deleteSaves = false; deleteGameID = id; focus.id = "del.cancel" }
    private func closeDelete() { guard !fromSystemEcho else { return }; deleteGameID = nil; focus.id = returnFocus }
    private func confirmDelete(_ id: String) {
        guard !fromSystemEcho else { return }
        let saves = deleteSaves
        deleteGameID = nil
        settingsOpen = false
        focus.id = nil
        actions.onDeleteGame?(id, saves)
    }
    private func openChoice(_ request: ChoiceRequest) {
        guard noteTouch() else { return }
        returnFocus = focus.id
        choice = request
        focus.id = "pick." + request.row.value
    }
    private func closeChoice() {
        guard !fromSystemEcho else { return }
        guard let request = choice else { return }
        choice = nil
        let prefix = request.gameID == ShellSettingsRows.gameID ? ShellSettingsRows.targetPrefix : request.gameID == TouchLayoutEditorView.gameID ? "lay.row." : "set.row."
        focus.id = prefix + request.row.id
    }
    private func pickChoice(_ value: String) {
        guard noteTouch() else { return }
        guard let request = choice else { return }
        if value != request.row.value {
            if request.gameID == TouchLayoutEditorView.gameID { touchLayout?.apply(row: request.row.id, value: value) }
            else if request.gameID == ShellSettingsRows.gameID { ShellSettingsRows.apply(request.row.id, value: value, to: .current) }
            else { actions.onChange(request.gameID, request.row.id, value) }
        }
        closeChoice()
    }
    // The mapping card: the shell's map or a game's, a row's options in place of the rows once one is picked.
    private func padMappingRows(_ id: String) -> [SettingRow] {
        if id == ControllersView.mappingID { return PadMappingRows.global(globalPadMap) }
        return games.first { $0.id == id }.map(PadMappingRows.game) ?? []
    }
    private func padMappingTitle(_ id: String) -> String {
        if id == ControllersView.mappingID { return ShellStrings.text("All games") }
        return games.first { $0.id == id }?.game.title ?? ""
    }
    private func openPadMapping(_ id: String) {
        guard noteTouch() else { return }
        returnFocus = focus.id
        padMapping = PadMappingState(gameID: id)
        // The swap's current segment, or the first button while a game's swap is neither on, off nor the shell's.
        let swap = padMappingRows(id).first
        focus.id = swap?.value == "custom" ? "map.row.pad.A" : "map.swap." + (swap?.value ?? "")
    }
    private func closePadMapping() { guard !fromSystemEcho else { return }; padMapping = nil; focus.id = returnFocus }
    private func openPadRow(_ row: String) {
        guard noteTouch() else { return }
        padMapping?.row = row
        focus.id = "map.opt." + (padMappingRows(padMapping?.gameID ?? "").first { $0.id == row }?.value ?? "")
    }
    private func closePadRow() {
        guard !fromSystemEcho else { return }
        guard let row = padMapping?.row else { return }
        padMapping?.row = nil
        focus.id = "map.row." + row
    }
    private func pickPadValue(_ row: String, _ value: String) {
        guard noteTouch() else { return }
        guard let id = padMapping?.gameID else { return }
        if id == ControllersView.mappingID { actions.onGlobalPadMapChange?(row, value) } else { actions.onChange(id, row, value) }
        closePadRow()
    }
    private func resetPadMapping() {
        guard noteTouch() else { return }
        guard let id = padMapping?.gameID else { return }
        let global = id == ControllersView.mappingID
        if global { actions.onGlobalPadMapReset?() } else { actions.onChange(id, PadMappingRows.resetID, "") }
        // Reset is disabled now: the focus goes to the swap, which is back at its default.
        focus.id = "map.swap." + (global ? "0" : PadMappingRows.follow)
    }
    private func openButtonTest() { guard noteTouch() else { return }; buttonTestOpen = true; focus.id = "test.close"; actions.onButtonTest(true) }
    private func closeButtonTest() {
        guard buttonTestOpen else { return }
        buttonTestOpen = false
        actions.onButtonTest(false)
        focus.id = "ctl.test"
    }
    private func back() {
        guard !fromSystemEcho else { return }
        if buttonTestOpen { closeButtonTest() }
        else if padMapping?.row != nil { closePadRow() }
        else if padMapping != nil { closePadMapping() }
        else if choice != nil { closeChoice() }
        else if let touchLayout {
            if touchLayout.held { touchLayout.putDown() } else if touchLayout.confirmingReset { touchLayout.cancelReset() } else { closeTouchLayout() }
        }
        else if helpGameID != nil { closeHelp() }
        else if deleteGameID != nil { closeDelete() }
        else if controllersOpen { controllersOpen = false; focus.id = "lib.controllers" }
        else if shellSettingsOpen { closeShellSettings() }
        else if settingsOpen { closeSettings() }
        else { actions.onBack() }
    }
    private func handle(_ action: ShellInput.Action, from source: InputDevice) {
        gate.handling = true
        defer { gate.handling = false }
        if case .controller = source { gate.controller(action) }
        if gameOrderOpen {
            if action == .back { gameOrderOpen = false }
            return
        }
        // Every controller button belongs to the button test while it is open: it closes on B held, touch or Escape.
        if buttonTestOpen, case .controller = source { return }
        if device != source { device = source }
        if touchMode { touchMode = false }
        focus.visible = true
        // A control the editor holds: the D-pad (or the arrow keys) moves it, A or B puts it down.
        if let touchLayout, touchLayout.held, choice == nil {
            switch action {
            case .left, .right, .up, .down: touchLayout.nudge(action); return
            case .activate, .back: touchLayout.putDown(); return
            default: break
            }
        }
        let live = liveTargets
        if focus.id == nil || !live.contains(where: { $0.id == focus.id }) {
            focus.id = defaultFocus
            if action != .activate && action != .back && action != .settings && action != .controllers { return }
        }
        switch action {
        case .activate: live.first { $0.id == focus.id }?.activate()
        case .back: back()
        case .settings: openSettings()
        case .controllers: openControllers()
        case .left, .right:
            // In Cover Flow the focused cover is always the middle one: left and right move the carousel by one.
            if layout.isCoverFlow, let id = focus.id, id.hasPrefix("lib.tile."), let index = games.firstIndex(where: { $0.id == selected?.id }) {
                let next = min(games.count - 1, max(0, index + (action == .left ? -1 : 1)))
                select(games[next].id)
                focus.id = "lib.tile.\(games[next].id)"
                return
            }
            move(action)
        default: move(action)
        }
    }
    /// The targets the D-pad reaches now: the open dialog's or panel's own, else the library's.
    private var liveTargets: [FocusTarget] { targets.values.filter { isLive($0.id) } }
    private func isLive(_ id: String) -> Bool { FocusLayer.isLive(id, under: topLayer) }
    /// The dialog or panel on top, in the order of `FocusLayer`.
    private var topLayer: FocusLayer? {
        if buttonTestOpen { return .buttonTest }
        if padMapping != nil { return .padMapping }
        if choice != nil { return .choice }
        if touchLayout != nil { return .touchLayout }
        if controllersOpen { return .controllers }
        if shellSettingsOpen { return .shellSettings }
        if helpGameID != nil { return .help }
        if deleteGameID != nil { return .delete }
        if settingsOpen { return .settings }
        return nil
    }
    private func move(_ action: ShellInput.Action) {
        let live = liveTargets
        let candidates = layout.isCoverFlow
            ? live.filter { !$0.id.hasPrefix("lib.tile.") || $0.id == "lib.tile.\(selected?.id ?? "")" }
            : live
        focus.id = FocusNavigation.next(from: focus.id, action: action, targets: candidates)
        if let id = focus.id, id.hasPrefix("lib.tile.") { select(String(id.dropFirst("lib.tile.".count))) }
    }
    private var defaultFocus: String? {
        if buttonTestOpen { return "test.close" }
        if let padMapping { return padMapping.row == nil ? "map.close" : "map.back" }
        if let choice { return "pick." + choice.row.value }
        if touchLayout != nil { return "lay.done" }
        if helpGameID != nil { return "help.done" }
        if deleteGameID != nil { return "del.cancel" }
        if controllersOpen { return "ctl.close" }
        if shellSettingsOpen { return "shs.close" }
        if settingsOpen { return "set.back" }
        return selected.map { "lib.tile.\($0.id)" } ?? "lib.controllers"
    }
}

/// The top of the settings: the game's banner, whole and fading into the panel, then its state and title below it,
/// so the banner's own logo and the title never overlap. Capped in height for a phone on its side.
private struct PaneBanner: View {
    let game: GameTile
    /// The full width, edge to edge under the side safe areas.
    let width: CGFloat
    /// The side safe areas: the words keep them, the banner does not.
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
    /// The status bar's height where the banner runs under it.
    var topInset: CGFloat = 0
    var body: some View {
        let hasBanner = game.banner != nil
        // A banner gets its full width and 16:9 height. Square or portrait art is never cropped into a tile: it shows
        // whole as a rounded cover above the words, on a heavily blurred fill of itself.
        let bannerHeight = hasBanner ? min(width * 9 / 16, 220) + topInset : topInset + 64
        // On a wide screen the cover sits beside the words, on a narrow one above them, aligned to the same edge.
        let layout = width >= 560 ? AnyLayout(HStackLayout(alignment: .bottom, spacing: 22))
                                  : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        layout {
            if !hasBanner { CoverThumbnail(game: game).frame(width: 96, height: 96) }
            // The words are bottom-aligned in a block that always reserves two lines of title, as in the library
            // hero: a short title shows more banner above it instead of leaving a hole.
            ZStack(alignment: .bottomLeading) {
                words(title: "M\nM").hidden().accessibilityHidden(true)
                words(title: game.title)
            }
        }
        .padding(.leading, leading + 24).padding(.trailing, trailing + 24)
        .padding(.top, bannerHeight - (hasBanner ? 22 : 0))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            // The art runs on past the header and fades into the page over a long distance, so there is no line where
            // the header ends and the settings begin.
            GeometryReader { geometry in
                let tall = geometry.size.height + 160
                Group {
                    if hasBanner {
                        // The banner fills the header edge to edge, cropped as needed, darker under the words.
                        ArtView(game: game, lettering: false)
                            .overlay {
                                LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.4), location: 0.6),
                                                       .init(color: .black.opacity(0.55), location: 1)], startPoint: .top, endPoint: .bottom)
                            }
                    } else {
                        ArtView(game: game, backdrop: true)
                            .scaleEffect(1.4)
                            .blur(radius: 40, opaque: true)
                            .saturation(1.2)
                            .overlay(Color.black.opacity(0.38))
                    }
                }
                .frame(width: width, height: tall)
                .clipped()
                .overlay(alignment: .top) {
                    // Darker under the status bar, so the time and battery stay legible on any art.
                    if topInset > 0 {
                        LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: topInset + 50)
                    }
                }
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: 0.45),
                                           .init(color: .black.opacity(0.55), location: 0.68),
                                           .init(color: .black.opacity(0.18), location: 0.85),
                                           .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func words(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusLabel(state: game.state, prominent: true)
            Text(title).shellType(ShellType.pageTitle).lineLimit(2)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("detail.title")
            HStack(spacing: 8) {
                SectionHeading(title: ShellStrings.text("Game settings"))
                if !game.subtitle.isEmpty {
                    Text(game.subtitle).shellType(ShellType.note).foregroundStyle(.white.opacity(0.5))
                }
            }.padding(.top, 2)
        }
    }
}

/// A game's square art shown whole: the icon, or the placeholder cover when there is none.
private struct CoverThumbnail: View {
    let game: GameTile
    var body: some View {
        Group {
            if let icon = game.icon {
                Image(decorative: icon.image, scale: 1).resizable().interpolation(.high).scaledToFill()
            } else if let banner = game.banner {
                Image(decorative: banner.image, scale: 1).resizable().interpolation(.high).scaledToFill()
            } else {
                PlaceholderArt(title: game.title, seed: game.id)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .accessibilityHidden(true)
    }
}
