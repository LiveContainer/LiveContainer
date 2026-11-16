import SwiftUI

/// The button test: an Xbox controller drawn whole, each button lighting up while it is held, the sticks moving and the
/// triggers filling as they are pulled. Every button belongs to the test while it is open, so a controller closes it by
/// holding B. Touch closes it with ×, a keyboard with Escape.
struct ButtonTestView: View {
    let snapshot: PadSnapshot?
    let close: () -> Void
    /// How long B is held to close.
    static let holdToClose: Double = 1.5
    @State private var holding = false
    @State private var holdTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellIgnoresPress) private var ignoresPress

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ShellStrings.text("Button test")).shellType(ShellType.flowTitle(20)).lineLimit(1)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("buttonTest.title")
                    Text(snapshot.map { $0.name.isEmpty ? ShellStrings.text("Controller") : $0.name } ?? ShellStrings.text("Press any button on a controller"))
                        .shellType(ShellType.note).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 8)
                // The system's echo of a controller button does not close the test. Holding B, which goes past this
                // button, still does.
                Button { if !ignoresPress() { close() } } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle()).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ShellStrings.text("Close"))
                .accessibilityIdentifier("buttonTest.close")
                .shellTarget("test.close", radius: 22, action: close)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
            Rectangle().fill(ShellPalette.hairline).frame(height: 1)
            XboxControllerDiagram(snapshot: snapshot ?? PadSnapshot())
                .aspectRatio(XboxControllerDiagram.design.width / XboxControllerDiagram.design.height, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ShellStrings.text("Controller"))
                .accessibilityValue(pressedText)
                .accessibilityIdentifier("buttonTest.diagram")
            Text(pressedText).shellText(14.5, .semibold).foregroundStyle(ShellPalette.cream)
                .lineLimit(2).frame(maxWidth: .infinity, minHeight: 40).multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("buttonTest.pressed")
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                    Circle().trim(from: 0, to: holding ? 1 : 0).stroke(ShellPalette.cream, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(verbatim: "B").font(ShellFonts.fixed(10, weight: .bold))
                }.frame(width: 22, height: 22).accessibilityHidden(true)
                Text(ShellStrings.text("Hold B to close")).shellText(13, .medium, relativeTo: .footnote).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity).padding(.bottom, 18).padding(.top, 4)
        }
        .frame(maxWidth: 620)
        .background(Color(red: 0.075, green: 0.075, blue: 0.082), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.5), radius: 40)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("buttonTest")
        .onChange(of: snapshot?.pressed.contains(.b) ?? false) { _, held in held ? startHold() : stopHold() }
        .onDisappear { holdTask?.cancel() }
    }

    private var pressedText: String {
        let pressed = PadElement.allCases.filter { snapshot?.pressed.contains($0) == true }.map(XboxControllerDiagram.name)
        return pressed.isEmpty ? ShellStrings.text("No button held") : pressed.joined(separator: " + ")
    }

    private func startHold() {
        withAnimation(.linear(duration: Self.holdToClose)) { holding = true }
        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(for: .seconds(Self.holdToClose))
            if !Task.isCancelled { close() }
        }
    }
    private func stopHold() {
        holdTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { holding = false }
    }
}

/// An Xbox controller in outline, drawn in a 320 × 220 design space and scaled to fit. Held buttons light up: the face
/// buttons in their own colours, everything else in cream.
struct XboxControllerDiagram: View {
    let snapshot: PadSnapshot
    /// The mapping card's drawing: the buttons carry the Switch names of their places and one quiet colour. False: the
    /// button test, with Xbox's names and colours.
    var switchNames = false
    /// Buttons drawn with a cream ring: the ones the mapping changed.
    var marked: Set<PadElement> = []
    /// A tap on a button, which also makes each button a VoiceOver element. Nil: the drawing is a picture (the button test).
    var tap: ((PadElement) -> Void)? = nil
    /// What VoiceOver says a button sends, on the mapping card.
    var value: (PadElement) -> String = { _ in "" }
    static let design = CGSize(width: 320, height: 220)

    static func name(_ element: PadElement) -> String {
        switch element {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .leftBumper: "LB"
        case .rightBumper: "RB"
        case .leftTrigger: "LT"
        case .rightTrigger: "RT"
        case .leftStick: "LS"
        case .rightStick: "RS"
        case .view: "View"
        case .menu: "Menu"
        case .home: "Xbox"
        case .up: ShellStrings.text("D-pad up")
        case .down: ShellStrings.text("D-pad down")
        case .left: ShellStrings.text("D-pad left")
        case .right: ShellStrings.text("D-pad right")
        }
    }

    /// Where each element sits in the design space and how large it is, shared by the drawing, the rings and the hotspots.
    /// The shoulders' frames are their outlines' bounds (`shoulder`).
    nonisolated static func frame(_ e: PadElement) -> (center: CGPoint, size: CGSize) {
        if let outline = shoulder(e) {
            let r = outline.boundingRect
            return (CGPoint(x: r.midX, y: r.midY), r.size)
        }
        return switch e {
        case .leftTrigger, .rightTrigger, .leftBumper, .rightBumper: (.zero, .zero)
        case .leftStick: (CGPoint(x: 88, y: 92), CGSize(width: 46, height: 46))
        case .rightStick: (CGPoint(x: 202, y: 140), CGSize(width: 46, height: 46))
        case .up: (CGPoint(x: 118, y: 128), CGSize(width: 12, height: 12))
        case .down: (CGPoint(x: 118, y: 152), CGSize(width: 12, height: 12))
        case .left: (CGPoint(x: 106, y: 140), CGSize(width: 12, height: 12))
        case .right: (CGPoint(x: 130, y: 140), CGSize(width: 12, height: 12))
        case .y: (CGPoint(x: 240, y: 70), CGSize(width: 20, height: 20))
        case .x: (CGPoint(x: 219, y: 92), CGSize(width: 20, height: 20))
        case .b: (CGPoint(x: 261, y: 92), CGSize(width: 20, height: 20))
        case .a: (CGPoint(x: 240, y: 114), CGSize(width: 20, height: 20))
        case .view: (CGPoint(x: 138, y: 92), CGSize(width: 14, height: 14))
        case .menu: (CGPoint(x: 182, y: 92), CGSize(width: 14, height: 14))
        case .home: (CGPoint(x: 160, y: 60), CGSize(width: 22, height: 22))
        }
    }

    // MARK: The shoulders

    /// A bumper's spine: it runs along the body's upper corner and top edge, a little outside them, so the slab drawn
    /// round it overhangs the body as a real bumper does. The left side, the right one mirrors it.
    private nonisolated static let bumperStart = CGPoint(x: 40, y: 55), bumperControl = CGPoint(x: 58, y: 35), bumperEnd = CGPoint(x: 116, y: 41)
    private nonisolated static let bumperThickness: CGFloat = 13
    /// A trigger: a paddle above and behind the bumper's outer half, tilted out, rounder on top. The left side.
    private nonisolated static let triggerCenter = CGPoint(x: 64, y: 14)
    private nonisolated static let triggerSize = CGSize(width: 34, height: 22)
    nonisolated static let triggerTilt: CGFloat = -10
    private nonisolated static let triggerRadii = (top: CGFloat(11), bottom: CGFloat(5))

    nonisolated static func isRight(_ e: PadElement) -> Bool { e == .rightBumper || e == .rightTrigger }
    private nonisolated static func mirrored(_ p: CGPoint, _ right: Bool) -> CGPoint { right ? CGPoint(x: design.width - p.x, y: p.y) : p }

    /// A shoulder button's outline in the design space, `grow` points wider all round (for the ring and the hit test), nil
    /// for every other element. The one source of the shoulders' drawing, ring, hotspot and hit test.
    nonisolated static func shoulder(_ e: PadElement, grow: CGFloat = 0) -> Path? {
        let right = isRight(e)
        switch e {
        case .leftBumper, .rightBumper:
            var spine = Path()
            spine.move(to: mirrored(bumperStart, right))
            spine.addQuadCurve(to: mirrored(bumperEnd, right), control: mirrored(bumperControl, right))
            return spine.strokedPath(StrokeStyle(lineWidth: bumperThickness + 2 * grow, lineCap: .round))
        case .leftTrigger, .rightTrigger:
            return paddle(grow: grow).applying(triggerPlacement(e))
        default:
            return nil
        }
    }

    /// A trigger's paddle in its own frame: centred on the origin, upright, its base (the edge a pull fills from) at the
    /// bottom, y = +height / 2.
    private nonisolated static func paddle(grow: CGFloat = 0) -> Path {
        let size = CGSize(width: triggerSize.width + 2 * grow, height: triggerSize.height + 2 * grow)
        return UnevenRoundedRectangle(topLeadingRadius: triggerRadii.top + grow, bottomLeadingRadius: triggerRadii.bottom + grow,
                                      bottomTrailingRadius: triggerRadii.bottom + grow, topTrailingRadius: triggerRadii.top + grow,
                                      style: .continuous)
            .path(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
    }

    /// Turns a paddle's own frame into the drawing's: tilted out with the shoulder, then moved to its place.
    private nonisolated static func triggerPlacement(_ e: PadElement) -> CGAffineTransform {
        let right = isRight(e)
        let center = mirrored(triggerCenter, right)
        return CGAffineTransform(rotationAngle: (right ? -triggerTilt : triggerTilt) * .pi / 180)
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }

    /// The pulled part of a trigger, `level` from 0 to 1, in the drawing's space: the paddle cut across its own axis at
    /// that height from its base, so it tilts with the paddle and meets its outline exactly. 0 is empty, 1 the whole paddle.
    nonisolated static func triggerFill(_ e: PadElement, level: Double) -> Path {
        guard e == .leftTrigger || e == .rightTrigger, level > 0 else { return Path() }
        let outline = paddle()
        guard level < 1 else { return outline.applying(triggerPlacement(e)) }
        let h = triggerSize.height, w = triggerSize.width
        // Wider and deeper than the paddle below the cut, so only the cut itself comes from this rectangle.
        let below = Path(CGRect(x: -w, y: h / 2 - h * level, width: 2 * w, height: h * level + h))
        return outline.intersection(below).applying(triggerPlacement(e))
    }

    /// The rest of a trigger, the part of the paddle a pull has not reached.
    nonisolated static func triggerRest(_ e: PadElement, level: Double) -> Path {
        guard let outline = shoulder(e) else { return Path() }
        return level > 0 ? outline.subtracting(triggerFill(e, level: level)) : outline
    }

    /// Where a shoulder's name sits and how it turns: on the bumper's spine, following its slope, in the trigger's middle.
    nonisolated static func shoulderLabel(_ e: PadElement) -> (point: CGPoint, angle: CGFloat) {
        let right = isRight(e)
        if e == .leftTrigger || e == .rightTrigger { return (mirrored(triggerCenter, right), right ? -triggerTilt : triggerTilt) }
        // The spine at t = 0.55, and its slope there.
        let t: CGFloat = 0.55
        let a = bumperStart, c = bumperControl, b = bumperEnd
        let p = CGPoint(x: (1 - t) * (1 - t) * a.x + 2 * t * (1 - t) * c.x + t * t * b.x,
                        y: (1 - t) * (1 - t) * a.y + 2 * t * (1 - t) * c.y + t * t * b.y)
        let dx = 2 * (1 - t) * (c.x - a.x) + 2 * t * (b.x - c.x), dy = 2 * (1 - t) * (c.y - a.y) + 2 * t * (b.y - c.y)
        let angle = atan2(dy, dx) * 180 / .pi
        return (mirrored(p, right), right ? -angle : angle)
    }

    /// The text on an element: Xbox's names for the test, the Switch names by position on the mapping card.
    private func label(_ e: PadElement) -> String {
        guard switchNames, let button = PadMap.button(at: e) else { return Self.name(e) }
        return button
    }

    var body: some View {
        GeometryReader { geometry in
            let s = min(geometry.size.width / Self.design.width, geometry.size.height / Self.design.height)
            ZStack(alignment: .topLeading) {
                drawing(s: s)
                ForEach(PadElement.allCases.filter(marked.contains), id: \.self) { ring($0, s: s) }
                if let tap { hotspots(s: s, tap: tap) }
            }
            .frame(width: Self.design.width * s, height: Self.design.height * s)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                // The nearest button to the touch, so the close face buttons each get the most room a finger can have.
                guard let tap, let e = Self.nearest(to: CGPoint(x: point.x / s, y: point.y / s)) else { return }
                tap(e)
            }
            .allowsHitTesting(tap != nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The mappable element nearest a point of the design space, within a finger's reach (nil for the body or the Xbox button).
    nonisolated static func nearest(to point: CGPoint) -> PadElement? {
        let candidates = PadElement.allCases.filter { PadMap.button(at: $0) != nil }
        let distances = candidates.map { e -> (PadElement, CGFloat) in
            // A shoulder by its outline, not its bounds: the bumper's bounds would cover the body under its curve.
            if shoulder(e) != nil {
                let reach = stride(from: 0, through: 20, by: 2).first { shoulder(e, grow: CGFloat($0))?.contains(point) == true }
                return (e, reach.map(CGFloat.init) ?? .infinity)
            }
            let f = frame(e)
            // To the element's edge, so a wide bumper is as easy to hit at its end as at its middle.
            let dx = max(0, abs(point.x - f.center.x) - f.size.width / 2), dy = max(0, abs(point.y - f.center.y) - f.size.height / 2)
            return (e, hypot(dx, dy))
        }
        guard let best = distances.min(by: { $0.1 < $1.1 }), best.1 <= 18 else { return nil }
        return best.0
    }

    /// One VoiceOver button per mappable element, at least 44 points, over the drawing. Touch goes through the nearest-button tap.
    private func hotspots(s: CGFloat, tap: @escaping (PadElement) -> Void) -> some View {
        ForEach(PadElement.allCases.filter { PadMap.button(at: $0) != nil }, id: \.self) { e in
            let f = Self.frame(e)
            let button = PadMap.button(at: e) ?? ""
            Color.clear
                .frame(width: max(44, f.size.width * s), height: max(44, f.size.height * s))
                .position(x: f.center.x * s, y: f.center.y * s)
                .accessibilityElement()
                .accessibilityLabel(PadMap.label(button) + ", " + PadMap.place(button))
                .accessibilityValue(value(e))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { tap(e) }
                .accessibilityIdentifier("padMapping.drawing.\(button)")
        }
    }

    /// A cream ring around a button the mapping changed, in the button's own shape.
    @ViewBuilder private func ring(_ e: PadElement, s: CGFloat) -> some View {
        let f = Self.frame(e)
        let line = max(1.5, 2 * s)
        let size = CGSize(width: f.size.width + 7, height: f.size.height + 7)
        switch e {
        case .leftBumper, .rightBumper, .leftTrigger, .rightTrigger:
            // The shoulder's own outline, 3.5 points out, as far as the other rings sit from their buttons.
            DesignShape(path: Self.shoulder(e, grow: 3.5) ?? Path()).stroke(ShellPalette.cream, lineWidth: line)
                .frame(width: Self.design.width * s, height: Self.design.height * s)
        case .up, .down, .left, .right:
            place(RoundedRectangle(cornerRadius: 6 * s).stroke(ShellPalette.cream, lineWidth: line), center: f.center, size: size, s: s)
        default:
            place(Circle().stroke(ShellPalette.cream, lineWidth: line), center: f.center, size: size, s: s)
        }
    }

    @ViewBuilder private func drawing(s: CGFloat) -> some View {
                // Back to front: the triggers behind, the body, the bumpers over the body's edge.
                trigger(.leftTrigger, value: snapshot.leftTrigger, s: s)
                trigger(.rightTrigger, value: snapshot.rightTrigger, s: s)
                ControllerBody()
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                    .overlay(ControllerBody().stroke(Color.white.opacity(0.35), lineWidth: max(1, 1.6 * s)))
                    .frame(width: Self.design.width * s, height: Self.design.height * s)
                bumper(.leftBumper, s: s)
                bumper(.rightBumper, s: s)
                stick(.leftStick, at: CGPoint(x: 88, y: 92), offset: snapshot.leftStick, s: s)
                stick(.rightStick, at: CGPoint(x: 202, y: 140), offset: snapshot.rightStick, s: s)
                dpad(center: CGPoint(x: 118, y: 140), s: s)
                // One quiet colour for the face buttons, in the test as on the card: held, they turn cream like every other button.
                face(.y, at: CGPoint(x: 240, y: 70), s: s)
                face(.x, at: CGPoint(x: 219, y: 92), s: s)
                face(.b, at: CGPoint(x: 261, y: 92), s: s)
                face(.a, at: CGPoint(x: 240, y: 114), s: s)
                small(.view, symbol: switchNames ? "minus" : "rectangle.on.rectangle", at: CGPoint(x: 138, y: 92), s: s)
                small(.menu, symbol: switchNames ? "plus" : "line.3.horizontal", at: CGPoint(x: 182, y: 92), s: s)
                home(at: CGPoint(x: 160, y: 60), s: s)
    }
    private static let neutral = Color(white: 0.82)

    private func held(_ e: PadElement) -> Bool { snapshot.pressed.contains(e) }

    private func place(_ view: some View, center: CGPoint, size: CGSize, s: CGFloat) -> some View {
        view.frame(width: size.width * s, height: size.height * s)
            .position(x: center.x * s, y: center.y * s)
    }

    /// The colour of a shoulder at rest: opaque, a step lighter than the body, so a bumper reads in front of the body's edge.
    private static let shoulderIdle = Color(red: 0.17, green: 0.17, blue: 0.18)

    /// A trigger fills from its base as far as it is pulled, and wholly while it is held as a button.
    private func trigger(_ e: PadElement, value: Double, s: CGFloat) -> some View {
        let outline = DesignShape(path: Self.shoulder(e) ?? Path())
        let level = max(0, min(1, held(e) && value < 0.05 ? 1 : value))
        let on = level > 0.05
        let nameAt = Self.shoulderLabel(e)
        // The pulled part and the rest, cut along the paddle's own axis and bounded by its outline (Self.triggerFill).
        let pulled = DesignShape(path: Self.triggerFill(e, level: level)), rest = DesignShape(path: Self.triggerRest(e, level: level))
        func name(_ color: Color) -> some View {
            Text(label(e)).font(ShellFonts.fixed(10.5 * s, weight: .heavy)).foregroundStyle(color)
                .rotationEffect(.degrees(nameAt.angle))
                .position(x: nameAt.point.x * s, y: nameAt.point.y * s)
        }
        return ZStack(alignment: .topLeading) {
            rest.fill(Self.shoulderIdle)
            pulled.fill(ShellPalette.cream)
            // The name in white over the rest and in black over the pulled part, split by the same tilted cut.
            name(.white.opacity(0.75)).mask { rest.fill() }
            name(.black).mask { pulled.fill() }
            outline.stroke(Color.white.opacity(on ? 0.9 : 0.4), lineWidth: max(1, 1.4 * s))
        }
        .frame(width: Self.design.width * s, height: Self.design.height * s)
    }

    /// A bumper: a slab along the body's top edge, over it. Cream while held.
    private func bumper(_ e: PadElement, s: CGFloat) -> some View {
        let on = held(e)
        let outline = DesignShape(path: Self.shoulder(e) ?? Path())
        let name = Self.shoulderLabel(e)
        return ZStack(alignment: .topLeading) {
            outline.fill(on ? ShellPalette.cream : Self.shoulderIdle)
            outline.stroke(Color.white.opacity(on ? 0.9 : 0.4), lineWidth: max(1, 1.4 * s))
            Text(label(e)).font(ShellFonts.fixed(9.5 * s, weight: .heavy)).foregroundStyle(on ? .black : .white.opacity(0.75))
                .rotationEffect(.degrees(name.angle))
                .position(x: name.point.x * s, y: name.point.y * s)
        }
        .frame(width: Self.design.width * s, height: Self.design.height * s)
    }

    private func stick(_ e: PadElement, at c: CGPoint, offset: CGPoint, s: CGFloat) -> some View {
        let on = held(e)
        let moved = hypot(offset.x, offset.y) > 0.15
        return ZStack {
            place(Circle().fill(Color.black.opacity(0.35)).overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: max(1, s))),
                  center: c, size: CGSize(width: 46, height: 46), s: s)
            place(Circle().fill(on ? ShellPalette.cream : Color(white: moved ? 0.42 : 0.26))
                    .overlay(Circle().stroke(Color.white.opacity(on || moved ? 0.9 : 0.4), lineWidth: max(1, 1.4 * s))),
                  center: CGPoint(x: c.x + offset.x * 10, y: c.y - offset.y * 10), size: CGSize(width: 30, height: 30), s: s)
        }
    }

    private func dpad(center c: CGPoint, s: CGFloat) -> some View {
        let arms: [(PadElement, CGFloat, CGFloat)] = [(.up, 0, -12), (.down, 0, 12), (.left, -12, 0), (.right, 12, 0)]
        return ZStack {
            place(RoundedRectangle(cornerRadius: 3 * s).fill(Color.white.opacity(0.10)), center: c, size: CGSize(width: 12, height: 12), s: s)
            ForEach(arms, id: \.0) { e, dx, dy in
                place(RoundedRectangle(cornerRadius: 3 * s).fill(held(e) ? ShellPalette.cream : Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 3 * s).stroke(Color.white.opacity(held(e) ? 0.9 : 0.35), lineWidth: max(1, s))),
                      center: CGPoint(x: c.x + dx, y: c.y + dy), size: CGSize(width: 12, height: 12), s: s)
            }
        }
    }

    private func face(_ e: PadElement, at c: CGPoint, s: CGFloat) -> some View {
        let on = held(e)
        return place(
            ZStack {
                Circle().fill(on ? ShellPalette.cream : Color.black.opacity(0.35))
                Circle().stroke(on ? Color.white.opacity(0.9) : Self.neutral.opacity(0.8), lineWidth: max(1, 1.5 * s))
                Text(label(e)).font(ShellFonts.fixed(11 * s, weight: .heavy)).foregroundStyle(on ? .black : Self.neutral)
            }
            .shadow(color: on ? ShellPalette.cream.opacity(0.6) : .clear, radius: 8 * s),
            center: c, size: CGSize(width: 20, height: 20), s: s)
    }

    private func small(_ e: PadElement, symbol: String, at c: CGPoint, s: CGFloat) -> some View {
        let on = held(e)
        return place(
            ZStack {
                Circle().fill(on ? ShellPalette.cream : Color.black.opacity(0.35))
                Circle().stroke(Color.white.opacity(on ? 0.9 : 0.35), lineWidth: max(1, s))
                Image(systemName: symbol).font(.system(size: 6 * s, weight: .bold)).foregroundStyle(on ? .black : .white.opacity(0.7))
            },
            center: c, size: CGSize(width: 14, height: 14), s: s)
    }

    private func home(at c: CGPoint, s: CGFloat) -> some View {
        let on = held(.home)
        return place(
            ZStack {
                Circle().fill(on ? ShellPalette.cream : Color.black.opacity(0.35))
                Circle().stroke(Color.white.opacity(on ? 0.9 : 0.45), lineWidth: max(1, 1.4 * s))
                Image(systemName: "xmark").font(.system(size: 8 * s, weight: .heavy)).foregroundStyle(on ? .black : .white.opacity(0.75))
            },
            center: c, size: CGSize(width: 22, height: 22), s: s)
    }
}

/// A path of the drawing's design space, scaled to the rect it is drawn in (the whole drawing).
private struct DesignShape: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / XboxControllerDiagram.design.width, sy = rect.height / XboxControllerDiagram.design.height
        return path.applying(CGAffineTransform(scaleX: sx, y: sy).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

/// The outline of an Xbox controller: a broad top, the two grips curving down and in, a shallow bottom between them.
private struct ControllerBody: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / XboxControllerDiagram.design.width, sy = rect.height / XboxControllerDiagram.design.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(160, 46))
        path.addCurve(to: p(262, 44), control1: p(200, 46), control2: p(236, 36))
        path.addCurve(to: p(310, 150), control1: p(292, 54), control2: p(304, 100))
        path.addCurve(to: p(268, 212), control1: p(318, 196), control2: p(296, 220))
        path.addCurve(to: p(214, 168), control1: p(244, 206), control2: p(232, 172))
        path.addCurve(to: p(160, 162), control1: p(196, 164), control2: p(178, 162))
        path.addCurve(to: p(106, 168), control1: p(142, 162), control2: p(124, 164))
        path.addCurve(to: p(52, 212), control1: p(88, 172), control2: p(76, 206))
        path.addCurve(to: p(10, 150), control1: p(24, 220), control2: p(2, 196))
        path.addCurve(to: p(58, 44), control1: p(16, 100), control2: p(28, 54))
        path.addCurve(to: p(160, 46), control1: p(84, 36), control2: p(120, 46))
        path.closeSubpath()
        return path
    }
}
