import SwiftUI

/// The touch controls' layout editor (#414), a screen of the shell settings: the controls of one layout drawn as the game draws them, on
/// this device's screen at its own proportions. Drag a control and it snaps to steps of a quarter key. Where it would cover another
/// control or leave its area it turns red and goes back when let go. The area it may use shows while it is chosen. A chosen control also
/// moves step by step with the arrows, a controller (A picks it up, the D-pad moves it, A or B puts it down) or VoiceOver's actions.
/// Reset this control and Reset all controls return one control or the whole shown layout to the built-in places, Reset all after
/// a question. The engine places every control again on the
/// device, so nothing the editor stores can break a game's layout.
struct TouchLayoutEditorView: View {
    @Bindable var model: TouchLayoutEditorModel
    var close: () -> Void
    /// Where the column beside the preview starts scrolled: the top, or the end for the captures of what lies below.
    var columnAnchor: UnitPoint = .top
    @Environment(\.shellFocus) private var focus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The system's echo of a controller button: the editor's buttons do nothing for it (the shell's focus took it).
    @Environment(\.shellIgnoresPress) private var ignoresPress
    /// The drag in progress: the control, where its offset started, and the spot drawn under the finger when the engine refuses it.
    @State private var drag: DragState?
    @State private var bounce: CGSize = .zero

    private struct DragState: Equatable {
        var control: TouchLayout.Control
        var start: TouchLayout.Offset
        var refused: TouchLayout.Offset?
        var travelled: CGFloat = 0
    }

    /// The width of the Arrange button in the shell settings, the same in every language (the longest label fits at the type's size).
    static let buttonWidth: CGFloat = 148
    static let arrowSize: CGFloat = 48

    var body: some View {
        GeometryReader { proxy in
            // Held sideways the preview takes the room the column beside it leaves: on a phone it is then nearly as large as the game.
            let wide = proxy.size.width > proxy.size.height * 1.1 && proxy.size.width >= 600
            if wide {
                let column = Self.column(width: proxy.size.width), aspect = screen.size.width / screen.size.height
                let w = max(200, min(proxy.size.width - column - 20 - 32, (proxy.size.height - 24) * aspect))
                HStack(alignment: .top, spacing: 20) {
                    canvas.frame(width: w, height: w / aspect)
                        .frame(maxHeight: .infinity)
                    // Everything else scrolls in the column: on the smallest phone it is taller than the screen.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) { header; pickers; panel(compact: true) }.padding(.vertical, 12)
                    }
                    .scrollIndicators(.automatic)
                    .defaultScrollAnchor(columnAnchor)
                    .frame(width: column)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        pickers
                        canvas
                        if !model.kind.split && proxy.size.width < 560 {
                            Label(ShellStrings.text("Turn the phone sideways for a larger preview."), systemImage: "rotate.right")
                                .shellType(ShellType.note).foregroundStyle(.white.opacity(0.55))
                        }
                        panel(compact: false)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(drag != nil)
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: model.stepCount)
        .sensoryFeedback(.warning, trigger: model.rejectCount)
    }

    /// The column beside the preview held sideways: about a third of the width, never narrower than the buttons need.
    static func column(width: CGFloat) -> CGFloat { min(340, max(250, (width * 0.34).rounded())) }

    // MARK: Header and pickers

    private var header: some View {
        HStack(alignment: .center) {
            Text(ShellStrings.text("Arrange controls")).shellType(ShellType.pageTitle)
                .lineLimit(1).minimumScaleFactor(0.7).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { if !ignoresPress() { close() } } label: { Text(ShellStrings.text("Done")) }
                .buttonStyle(ChipButtonStyle())
                .accessibilityIdentifier("touchLayout.done")
                .shellTarget("lay.done", radius: 22, action: close)
        }
    }

    /// The rows report to the editor, not to a game or the shell settings (LibraryView.pickChoice).
    static let gameID = "touchLayout"
    static let layoutRow = "lay.layout", poseRow = "lay.pose", togetherRow = "lay.together"

    private var pickers: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layoutRow = SettingRow(id: Self.layoutRow, label: ShellStrings.text("Layout"),
                                       note: ShellStrings.text("Switch in the game with the button at the top centre. 3D adds the D-pad, L3 and R3."),
                                       kind: .choice([SettingOption("2d", "2D"), SettingOption("3d", "3D")]),
                                       value: model.kind.full ? "3d" : "2d")
            SettingControl(gameID: Self.gameID, row: layoutRow, targetPrefix: "lay.row.") { value in
                model.setKind(.of(full: value == "3d", split: model.kind.split))
            }.equatable()
            if model.upright != nil {
                let poseRow = SettingRow(id: Self.poseRow, label: ShellStrings.text("Screen"),
                                         kind: .choice([SettingOption("over", ShellStrings.text("Over the picture")),
                                                        SettingOption("below", ShellStrings.text("Below the picture"))]),
                                         value: model.kind.split ? "below" : "over")
                SettingControl(gameID: Self.gameID, row: poseRow, targetPrefix: "lay.row.") { value in
                    model.setKind(.of(full: model.kind.full, split: value == "below"))
                }.equatable()
            }
        }
    }

    // MARK: The preview

    private var screen: PadScreen { model.editing.screen }

    private var canvas: some View {
        let g = model.geo
        let active = drag?.control ?? model.selected
        return GeometryReader { proxy in
            let k = proxy.size.width / screen.size.width
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.scaleBy(x: k, y: k)
                    drawBackdrop(g, in: &context)
                    if let active { drawGuides(for: active, g, k: k, in: &context) }
                    for c in g.drawnControls where !isActive(c, active) { draw(c, g, k: k, in: &context) }
                }
                if let active {
                    Canvas { context, _ in
                        context.scaleBy(x: k, y: k)
                        for c in g.drawnControls where isActive(c, active) { draw(c, g, k: k, highlight: drag?.refused == nil ? .chosen : .refused, in: &context) }
                    }
                    .offset(x: activeOffset(g).width * k, y: activeOffset(g).height * k)
                    .allowsHitTesting(false)
                }
                accessibilityElements(g, k: k)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(k: k))
        }
        .aspectRatio(screen.size.width / screen.size.height, contentMode: .fit)
        .background(PadDrawing.backdrop)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 3))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ShellStrings.text("Preview of the touch controls"))
        .accessibilityIdentifier("touchLayout.preview")
    }

    /// Where the active control is drawn beyond its kept place: under the finger on a refused spot, or on its way back.
    private func activeOffset(_ g: PadGeo) -> CGSize {
        if let drag, let refused = drag.refused {
            let kept = model.dragOffset(drag.control)
            return CGSize(width: CGFloat(refused.dx - kept.dx) * g.step + bounce.width, height: CGFloat(refused.dy - kept.dy) * g.step + bounce.height)
        }
        return bounce
    }

    /// The active control and the controls that move with it: the diamond's keys while they move together.
    private func isActive(_ c: TouchLayout.Control, _ active: TouchLayout.Control?) -> Bool {
        guard let active else { return false }
        return model.editing.mover(c) == model.editing.mover(active)
    }

    private func drawBackdrop(_ g: PadGeo, in context: inout GraphicsContext) {
        // The picture: the whole screen over which the controls float, or its own area above the controls on a split screen.
        let picture = g.region.separated ? g.region.game : g.region.game.intersection(CGRect(origin: .zero, size: screen.size))
        context.fill(Path(roundedRect: picture, cornerRadius: 10), with: .color(.white.opacity(g.region.separated ? 0.07 : 0.03)))
        if g.region.separated {
            context.fill(Path(g.region.controls), with: .color(.black.opacity(0.18)))
        }
    }

    private func drawGuides(for active: TouchLayout.Control, _ g: PadGeo, k: CGFloat, in context: inout GraphicsContext) {
        let m = model.editing.mover(active)
        // The area it may use: a calm cream tint with a dashed edge.
        if let area = model.editing.allowedArea(active) {
            let path = Path(roundedRect: area.insetBy(dx: 1, dy: 1), cornerRadius: 14)
            context.fill(path, with: .color(ShellPalette.cream.opacity(0.06)))
            context.stroke(path, with: .color(ShellPalette.cream.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5 / k, dash: [8 / k, 6 / k]))
        }
        // Its built-in place, dashed, once it has moved.
        if model.editing.isMoved(m) {
            var built = model.editing
            built.putBack(m)
            let home = built.geo
            for c in home.drawnControls where model.editing.mover(c) == m {
                for shape in Self.shapes(c, home) {
                    context.stroke(PadDrawing.outline(shape), with: .color(ShellPalette.cream.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5 / k, dash: [5 / k, 5 / k]))
                }
            }
        }
    }

    private enum Highlight { case none, chosen, refused }

    /// The keys in the editor: brighter than in the settings' small preview, with lines of the same width at every preview size. The
    /// chosen control is filled cream with dark type and a soft halo, a refused spot red, so it reads at a glance.
    private func draw(_ c: TouchLayout.Control, _ g: PadGeo, k: CGFloat, highlight: Highlight = .none, in context: inout GraphicsContext) {
        var style = PadDrawing.Style(fill: .white.opacity(0.17), line: .white.opacity(0.62), text: .white.opacity(0.9), ring: .white.opacity(0.07),
                                     lineWidth: 1.5 / k)
        var halo: Color?
        switch highlight {
        case .none: break
        case .chosen:
            style.fill = ShellPalette.cream.opacity(model.held ? 1 : 0.9); style.line = ShellPalette.cream; style.text = .black.opacity(0.85)
            style.ring = ShellPalette.cream.opacity(0.22); style.lineWidth = 2.5 / k
            halo = ShellPalette.cream.opacity(model.held ? 0.5 : 0.32)
        case .refused:
            style.fill = DeleteStyle.red.opacity(0.9); style.line = DeleteStyle.red; style.text = .white
            style.ring = DeleteStyle.red.opacity(0.25); style.lineWidth = 2.5 / k
            halo = DeleteStyle.red.opacity(0.4)
        }
        for shape in Self.shapes(c, g) {
            if let halo { context.stroke(PadDrawing.outline(shape), with: .color(halo), lineWidth: (model.held ? 12 : 9) / k) }
            PadDrawing.draw(shape, in: &context, style: style)
        }
    }

    /// The drawn shapes of one control, in the gamepad's look.
    static func shapes(_ c: TouchLayout.Control, _ g: PadGeo) -> [TouchPadPreviewGeometry.Shape] {
        switch c {
        case .face: (0..<4).map { .circle(g.faceKey[$0], g.faceR, label: ["A", "B", "X", "Y"][$0]) }
        case .a: [.circle(g.faceKey[0], g.faceR, label: "A")]
        case .b: [.circle(g.faceKey[1], g.faceR, label: "B")]
        case .x: [.circle(g.faceKey[2], g.faceR, label: "X")]
        case .y: [.circle(g.faceKey[3], g.faceR, label: "Y")]
        case .stick: [.ring(g.stick, g.stickR, knob: g.knobR)]
        case .dpad: [.dpad(g.dpad, g.dpadR)]
        case .zl, .l, .zr, .r:
            [.drop(g.drop[PadGeo.dropIndex(c)], g.dropR[PadGeo.dropIndex(c)], tipRight: c == .zr || c == .r, label: c.title)]
        case .l3: [.circle(g.click[0], g.clickR, label: "L3")]
        case .r3: [.circle(g.click[1], g.clickR, label: "R3")]
        case .minus: [.pill(g.pill[0], label: "−")]
        case .plus: [.pill(g.pill[1], label: "+")]
        }
    }

    // MARK: Touch

    private func dragGesture(k: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let t = CGSize(width: value.translation.width / k, height: value.translation.height / k)
                if drag == nil {
                    let start = CGPoint(x: value.startLocation.x / k, y: value.startLocation.y / k)
                    // A finger is wider than a key in a small preview: anything within about 22 points of the screen counts.
                    guard let c = model.editing.control(at: start, slop: max(22 / k, 6)) else { return }
                    bounce = .zero
                    model.select(c)
                    drag = DragState(control: c, start: model.dragOffset(c))
                }
                guard var d = drag else { return }
                d.travelled = max(d.travelled, hypot(value.translation.width, value.translation.height))
                if d.travelled < 4 { drag = d; return }   // a tap chooses the control and moves nothing
                let result = model.dragTo(d.control, from: d.start, by: t)
                d.refused = result.kept ? nil : result.offset
                drag = d
            }
            .onEnded { _ in
                guard let d = drag else { model.select(nil); return }
                if let refused = d.refused {
                    // Back to its kept place, from under the finger.
                    let g = model.geo, kept = model.dragOffset(d.control)
                    bounce = CGSize(width: CGFloat(refused.dx - kept.dx) * g.step, height: CGFloat(refused.dy - kept.dy) * g.step)
                    drag = nil
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25)) { bounce = .zero }
                    model.dragEnded(rejected: true)
                } else {
                    drag = nil
                    if d.travelled >= 4 { model.dragEnded(rejected: false) }
                }
            }
    }

    // MARK: VoiceOver and the controller

    /// One element per control over the picture: VoiceOver names it and moves it with its actions, a controller focuses it (A picks it
    /// up). They take no touches, the drag above does.
    private func accessibilityElements(_ g: PadGeo, k: CGFloat) -> some View {
        let controls = model.together ? [TouchLayout.Control.face] + g.drawnControls.filter { !$0.isFaceKey } : g.drawnControls
        return ForEach(controls, id: \.self) { c in accessibilityElement(c, g, k: k) }
    }

    // S2Arm 本地补丁（11-07）：原样从上面的 ForEach 闭包挪出，只把三元表达式提成有类型的局部变量；Xcode 27.1 Release iOS 下原写法
    //   「unable to type-check this expression in reasonable time」，带游戏库的容器壳编不过。行为不变。见 UPSTREAM.md「本地补丁」。
    private func accessibilityElement(_ c: TouchLayout.Control, _ g: PadGeo, k: CGFloat) -> some View {
        let box: CGRect = g.box(of: c)?.box ?? .zero
        let value: String = ShellStrings.text(model.editing.isMoved(c) ? "Moved" : "In its place")
        let traits: AccessibilityTraits = model.selected.map { model.editing.mover($0) == c } == true ? [.isButton, .isSelected] : .isButton
        let radius: CGFloat = max(box.width, box.height) * k / 2
        return Color.clear
            .frame(width: max(box.width * k, 30), height: max(box.height * k, 30))
            .position(x: box.midX * k, y: box.midY * k)
            .accessibilityElement()
            .accessibilityLabel(c.title)
            .accessibilityValue(value)
            .accessibilityAddTraits(traits)
            .accessibilityAction { model.select(c) }
            .accessibilityAction(named: ShellStrings.text("Move up")) { voiceOverMove(c, 0, -1) }
            .accessibilityAction(named: ShellStrings.text("Move down")) { voiceOverMove(c, 0, 1) }
            .accessibilityAction(named: ShellStrings.text("Move left")) { voiceOverMove(c, -1, 0) }
            .accessibilityAction(named: ShellStrings.text("Move right")) { voiceOverMove(c, 1, 0) }
            .accessibilityAction(named: ShellStrings.text("Reset this control")) { model.select(c); model.putBack() }
            .shellTarget("lay.ctl.\(c.rawValue)", radius: radius) { model.pickUp(c) }
            .allowsHitTesting(false)
    }

    private func voiceOverMove(_ c: TouchLayout.Control, _ dx: Int, _ dy: Int) {
        model.select(c)
        let outcome = model.nudge(dx: dx, dy: dy)
        let text = outcome == .moved ? ShellStrings.text("Moved") : outcome == .atEdge ? ShellStrings.text("At the edge") : ShellStrings.text("No room there")
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: The panel

    /// What is chosen, the arrows, the diamond's switch, the two resets and the note. compact: the column beside the preview, with the
    /// arrows in one row. Otherwise the arrows in a cross with the resets beside them, or under them where the width is short.
    private func panel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                status
                if compact {
                    arrowRow.frame(maxWidth: .infinity)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 18) { arrowCross; resets.frame(width: Self.resetWidth) }
                        VStack(alignment: .leading, spacing: 14) { arrowCross.frame(maxWidth: .infinity); resets }
                    }
                }
                let together = SettingRow(id: Self.togetherRow, label: ShellStrings.text("Move A B X Y together"),
                                          kind: .toggle(on: "1", off: "0"), value: model.together ? "1" : "0")
                SettingControl(gameID: Self.gameID, row: together, targetPrefix: "lay.row.") { model.setTogether($0 == "1") }
                    .equatable()
            }
            .shellCard(padding: compact ? 14 : 18)
            if compact { resets }
            Text(ShellStrings.text("Drag a control to move it. Tap one to choose it, then move it step by step with the arrows. Where a control would cover another or leave the screen, it goes back. For every game."))
                .shellType(ShellType.note).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The width of the two resets beside the arrows on an upright screen, the same in every language.
    static let resetWidth: CGFloat = 236

    /// Reset this control (the chosen one) and Reset all controls (the shown layout), one above the other and as wide as each other.
    /// Reset all asks first, in place, and the question starts on Cancel: it takes the button's place in the focus.
    private var resets: some View {
        VStack(alignment: .leading, spacing: 8) {
            let canPutBack = model.selected.map { model.editing.isMoved($0) } ?? false
            Button { if !ignoresPress() { model.putBack() } } label: { resetLabel("Reset this control", "arrow.uturn.backward") }
                .buttonStyle(ShellButtonStyle(fills: true))
                .disabled(!canPutBack)
                .accessibilityIdentifier("touchLayout.putBack")
                .shellTarget("lay.putBack", enabled: canPutBack) { model.putBack() }
            if model.confirmingReset {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ShellStrings.text("Put every control of the \(model.kind.full ? "3D" : "2D") layout back in its built-in place?"))
                        .shellType(ShellType.note).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("touchLayout.resetQuestion")
                    Button { if !ignoresPress() { model.reset() } } label: { resetLabel("Reset all controls", "arrow.counterclockwise") }
                        .buttonStyle(ShellButtonStyle(fills: true, destructive: true))
                        .accessibilityIdentifier("touchLayout.resetConfirm")
                        .shellTarget("lay.resetConfirm") { model.reset() }
                    Button { if !ignoresPress() { model.cancelReset() } } label: { Text(ShellStrings.text("Cancel")).lineLimit(1).minimumScaleFactor(0.8) }
                        .buttonStyle(ShellButtonStyle(fills: true))
                        .accessibilityIdentifier("touchLayout.resetCancel")
                        .shellTarget("lay.reset") { model.cancelReset() }
                }
                .padding(10)
                .background(DeleteStyle.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DeleteStyle.red.opacity(0.35)))
            } else {
                Button { if !ignoresPress() { model.askReset() } } label: { resetLabel("Reset all controls", "arrow.counterclockwise") }
                    .buttonStyle(ShellButtonStyle(fills: true, destructive: true))
                    .disabled(model.layoutIsBuiltIn)
                    .accessibilityIdentifier("touchLayout.reset")
                    .shellTarget("lay.reset", enabled: !model.layoutIsBuiltIn) { model.askReset() }
            }
        }
    }

    private func resetLabel(_ text: String.LocalizationValue, _ symbol: String) -> some View {
        Label { Text(ShellStrings.text(text)).lineLimit(1).minimumScaleFactor(0.75) } icon: { Image(systemName: symbol) }
    }

    /// The chosen control and what to do next, or why it went back. It takes the card's whole width, so the words never wrap word by word.
    private var status: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: model.selected == nil ? "hand.tap" : model.held ? "hand.draw" : "scope")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(model.rejected ? DeleteStyle.red : ShellPalette.cream)
                .frame(width: 36, height: 36)
                .background((model.rejected ? DeleteStyle.red : ShellPalette.cream).opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let c = model.selected {
                    let m = model.editing.mover(c)
                    Text(m.title).shellType(ShellType.cardTitle)
                    Text(model.rejected ? ShellStrings.text("No room there. It went back to where it was.")
                         : model.held ? ShellStrings.text("Move it with the D-pad. A or B puts it down.")
                         : ShellStrings.text(model.editing.isMoved(m) ? "Moved" : "In its place"))
                        .shellType(ShellType.note)
                        .foregroundStyle(model.rejected ? DeleteStyle.red : .white.opacity(0.65))
                } else {
                    Text(ShellStrings.text("Choose a control")).shellType(ShellType.cardTitle)
                    Text(model.rejected ? ShellStrings.text("No room there. It went back to where it was.") : ShellStrings.text("Tap a control in the picture."))
                        .shellType(ShellType.note).foregroundStyle(model.rejected ? DeleteStyle.red : .white.opacity(0.65))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("touchLayout.status")
    }

    /// The four arrows in one row, held sideways where height is short: one step of the chosen control each.
    private var arrowRow: some View {
        HStack(spacing: 8) {
            arrow("chevron.left", "Move left", "left", -1, 0)
            arrow("chevron.up", "Move up", "up", 0, -1)
            arrow("chevron.down", "Move down", "down", 0, 1)
            arrow("chevron.right", "Move right", "right", 1, 0)
        }
        .disabled(model.selected == nil)
    }

    /// Four arrows in a cross, on an upright screen.
    private var arrowCross: some View {
        let gap = Color.clear.frame(width: Self.arrowSize, height: Self.arrowSize)
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow { gap; arrow("chevron.up", "Move up", "up", 0, -1); gap }
            GridRow { arrow("chevron.left", "Move left", "left", -1, 0); gap; arrow("chevron.right", "Move right", "right", 1, 0) }
            GridRow { gap; arrow("chevron.down", "Move down", "down", 0, 1); gap }
        }
        .disabled(model.selected == nil)
    }

    private func arrow(_ symbol: String, _ label: String.LocalizationValue, _ id: String, _ dx: Int, _ dy: Int) -> some View {
        Button { if !ignoresPress() { model.nudge(dx: dx, dy: dy) } } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).frame(width: Self.arrowSize, height: Self.arrowSize)
        }
        .buttonStyle(RoundIconButtonStyle(size: Self.arrowSize))
        .opacity(model.selected == nil ? 0.4 : 1)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(ShellStrings.text(label))
        .accessibilityIdentifier("touchLayout.\(id)")
        .shellTarget("lay.arrow.\(id)", enabled: model.selected != nil, radius: Self.arrowSize / 2) { model.nudge(dx: dx, dy: dy) }
    }
}

/// The Arrangement row of the shell settings' Touch controls group: whether the controls are where they are built in, and the button
/// that opens the editor.
struct TouchArrangeRow: View {
    var arranged: Bool
    @Environment(\.shellOpenTouchLayout) private var open
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ShellStrings.text("Arrangement")).shellType(ShellType.settingLabel)
                Text(ShellStrings.text(arranged ? "Your own" : "Built in")).shellType(ShellType.note).foregroundStyle(.white.opacity(0.5))
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(ShellStrings.text("Arrange…")) { open?() }
                .buttonStyle(ShellButtonStyle(fills: true)).frame(width: TouchLayoutEditorView.buttonWidth)
                .accessibilityIdentifier("shellSettings.arrange")
                .accessibilityHint(ShellStrings.text("Move single controls where your thumbs want them."))
                .shellTarget("shs.arrange") { open?() }
        }
    }
}

private struct ShellOpenTouchLayoutKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    /// Opens the touch controls' layout editor. The library provides it.
    var shellOpenTouchLayout: (() -> Void)? {
        get { self[ShellOpenTouchLayoutKey.self] }
        set { self[ShellOpenTouchLayoutKey.self] = newValue }
    }
}

extension TouchLayout.Control {
    /// The control's name, for the status line and VoiceOver.
    var title: String {
        switch self {
        case .face: "A B X Y"
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .stick: ShellStrings.text("Left stick")
        case .dpad: ShellStrings.text("D-pad")
        case .zl: "ZL"
        case .l: "L"
        case .zr: "ZR"
        case .r: "R"
        case .l3: "L3"
        case .r3: "R3"
        case .minus: ShellStrings.text("Minus")
        case .plus: ShellStrings.text("Plus")
        }
    }
}
