import CoreGraphics
import Foundation

/// A screen the touch controls are laid out on, as the engine sees it: the game view's size in points, its safe-area insets and,
/// on a foldable, the fold.
public struct PadScreen: Equatable, Sendable {
    public struct Insets: Equatable, Sendable {
        public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat
        public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
            self.top = top; self.left = left; self.bottom = bottom; self.right = right
        }
    }
    public var size: CGSize
    public var insets: Insets
    public var partiallyOpen = false
    /// The fold (a division region), nil for none.
    public var division: CGRect?
    /// iPhone Duo's inner display upright: the picture keeps only the top inset (front_ios.m's duoPortrait).
    public var topSafeOnly = false

    public init(size: CGSize, insets: Insets = Insets(), partiallyOpen: Bool = false, division: CGRect? = nil, topSafeOnly: Bool = false) {
        self.size = size; self.insets = insets; self.partiallyOpen = partiallyOpen; self.division = division; self.topSafeOnly = topSafeOnly
    }

    /// iPhone Pro Max held sideways, the screen the settings preview has always shown.
    public static let proMax = PadScreen(size: CGSize(width: 932, height: 430), insets: Insets(left: 59, bottom: 21, right: 59))
    /// iPad Pro 13 inch upright: the controls below the picture.
    public static let iPadUpright = PadScreen(size: CGSize(width: 1032, height: 1376), insets: Insets(top: 24, bottom: 20))
    /// iPhone Duo's inner display upright, with the fold across the middle.
    public static let duoUpright = PadScreen(size: CGSize(width: 669, height: 951), insets: Insets(top: 62, bottom: 34),
                                             division: CGRect(x: 0, y: 455.5, width: 669, height: 40), topSafeOnly: true)
}

/// The touch controls' geometry, a Swift copy of the engine's `DmPadGeometry.h` (patches 0065 to 0067 and the arrangement of
/// DM_TOUCH_LAYOUT): `dm_layout`, `dm_pad_geo_at`, the fit test, the size and stick fallbacks and `dm_pad_arrange`, line by line, so the
/// layout editor shows and accepts exactly what the engine will draw. `TouchPadGeometryTests` pins it to points the engine's own
/// test program computes. The engine stays the truth on the device.
struct PadGeo: Equatable {
    // dm_layout: the overlay layout, or the split one with the controls below the picture.
    struct Region: Equatable { var game: CGRect, controls: CGRect, separated: Bool, topSafeOnly: Bool }

    struct Shape: Equatable {
        var c: CGPoint
        var r: CGFloat
        var rect: CGRect
        var isRect: Bool
        var within: CGRect
        var id: Int
        init(c: CGPoint = .zero, r: CGFloat = 0, rect: CGRect = .null, isRect: Bool = false, within: CGRect, id: Int) {
            self.c = c; self.r = r; self.rect = rect; self.isRect = isRect; self.within = within; self.id = id
        }
        var box: CGRect { isRect ? rect : CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }
    }
    // dm_pad_shapes ids.
    static let shapeFace = 0, shapeStick = 4, shapeDpad = 5, shapeDrop = 6, shapeTip = 10, shapeClick = 14, shapePill = 16, shapeSwap = 18

    var u: CGFloat = 0
    var safe: CGRect = .null, corner: CGRect = .null
    var portrait = false
    var face: CGPoint = .zero, faceGap: CGFloat = 0, faceR: CGFloat = 0, faceHitR: CGFloat = 0
    var stick: CGPoint = .zero, stickR: CGFloat = 0, knobR: CGFloat = 0
    var dpad: CGPoint = .zero, dpadR: CGFloat = 0, armW: CGFloat = 0, armIn: CGFloat = 0
    var drop: [CGPoint] = Array(repeating: .zero, count: 4), dropR: [CGFloat] = Array(repeating: 0, count: 4)   // ZL, L, ZR, R
    var click: [CGPoint] = [.zero, .zero], clickR: CGFloat = 0                                                   // L3, R3
    var pill: [CGRect] = [.zero, .zero]                                                                          // −, +
    var swap: CGPoint = .zero, swapR: CGFloat = 0
    var faceKey: [CGPoint] = Array(repeating: .zero, count: 4)                                                  // A, B, X, Y
    var faceSplit = false
    var moved: Set<TouchLayout.Control> = [], dropped: Set<TouchLayout.Control> = []
    var full = false
    var region = Region(game: .zero, controls: .zero, separated: false, topSafeOnly: false)

    /// A quarter of a face key's width: one step of the arrangement.
    var step: CGFloat { faceR / 2 }

    // MARK: DmLayout.h

    static func aspectFit(_ b: CGRect) -> CGRect {
        var w = b.width, h = b.height
        if w <= 0 || h <= 0 { return .zero }
        if w / h > 16.0 / 9.0 { w = h * 16.0 / 9.0 } else { h = w * 9.0 / 16.0 }
        return CGRect(x: floor(b.midX - w / 2), y: floor(b.midY - h / 2), width: w, height: h)
    }
    static func horizontalDivision(_ b: CGRect, _ division: CGRect?) -> CGRect? {
        guard let d = division, !d.isNull, d.width > d.height else { return nil }
        let x = max(b.minX, d.minX), y = max(b.minY, d.minY), right = min(b.maxX, d.maxX), bottom = min(b.maxY, d.maxY)
        if right - x < b.width * 0.9 || bottom < y || y <= b.minY || bottom >= b.maxY { return nil }
        return CGRect(x: x, y: y, width: right - x, height: bottom - y)
    }
    static func inset(_ r: CGRect, _ i: PadScreen.Insets) -> CGRect {
        CGRect(x: r.minX + i.left, y: r.minY + i.top, width: r.width - i.left - i.right, height: r.height - i.top - i.bottom)
    }
    static func gameSafeInsets(_ b: CGRect, _ i: PadScreen.Insets, _ duo: Bool) -> PadScreen.Insets {
        duo && b.height > b.width ? PadScreen.Insets(top: i.top) : i
    }
    static func region(_ screen: PadScreen) -> Region {
        let b = CGRect(origin: .zero, size: screen.size)
        let insets = gameSafeInsets(b, screen.insets, screen.topSafeOnly)
        var l = Region(game: aspectFit(b), controls: b, separated: false, topSafeOnly: screen.topSafeOnly)
        if b.isEmpty { return l }
        let division = horizontalDivision(b, screen.division)
        let portrait = b.height > b.width
        if !portrait && (!screen.partiallyOpen || division == nil) { return l }
        let d = division ?? CGRect(x: b.minX, y: b.midY, width: b.width, height: 0)
        let safe = inset(b, insets)
        let upper = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: d.minY - safe.minY)
        let lower = CGRect(x: b.minX, y: d.maxY, width: b.width, height: b.maxY - d.maxY)
        if upper.height <= 0 || safe.maxY <= lower.minY { return l }
        l.game = aspectFit(upper); l.controls = lower; l.separated = true
        return l
    }

    // MARK: dm_pad_geo_at

    static func side(_ s: CGRect, right: Bool, _ dx: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: right ? s.maxX - dx : s.minX + dx, y: y) }
    static func diamondKey(_ c: CGPoint, _ d: CGFloat, _ i: Int) -> CGPoint {
        switch i { case 0: CGPoint(x: c.x + d, y: c.y); case 1: CGPoint(x: c.x, y: c.y + d); case 2: CGPoint(x: c.x, y: c.y - d); default: CGPoint(x: c.x - d, y: c.y) }
    }

    static func at(_ screen: PadScreen, _ region: Region, full: Bool, u: CGFloat) -> PadGeo {
        let bounds = CGRect(origin: .zero, size: screen.size), insets = screen.insets
        var g = PadGeo()
        let sep = region.separated
        g.u = u; g.full = full; g.region = region
        g.safe = region.controls.intersection(inset(bounds, gameSafeInsets(bounds, insets, region.topSafeOnly)))
        var ci = insets; ci.left *= 0.5; ci.right *= 0.5
        g.corner = sep ? g.safe : inset(bounds, ci)
        g.portrait = sep && bounds.height > bounds.width
        let s = g.safe, c = g.corner
        let thumbL = CGPoint(x: s.minX + s.width * 0.28, y: s.minY + s.height * 0.58)
        let thumbR = CGPoint(x: s.minX + s.width * 0.72, y: thumbL.y)
        g.faceGap = 50 * u; g.faceR = 27 * u; g.faceHitR = max(g.faceR * 1.25, sep ? 22 : 0)
        g.stickR = 77 * u; g.knobR = 30 * u
        g.dpadR = 48 * u; g.armW = 17 * u; g.armIn = 11 * u
        if g.portrait {
            g.face = thumbR
            g.stick = thumbL; if full { g.stick.x -= g.dpadR + 6 * u }
            g.dpad = CGPoint(x: thumbL.x + g.stickR + 6 * u, y: thumbL.y)
        } else {
            let edge: CGFloat = sep ? g.faceGap + g.faceHitR : 0
            g.face = side(c, right: true, max(81 * u, edge), c.maxY - max(82 * u, edge))
            g.stick = side(c, right: false, 81 * u, c.maxY - 82 * u)
            g.dpad = side(c, right: false, 231 * u, c.maxY - 64 * u)
        }
        let edge: CGFloat = sep ? 22 : 0
        for i in 0..<4 {
            let z = i == 0 || i == 2
            g.drop[i] = side(s, right: i >= 2, max((z ? 44 : 44) * u, edge), s.minY + max((z ? 40 : 108) * u, edge))
            g.dropR[i] = (z ? 26 : 24) * u
        }
        for i in 0..<2 { g.click[i] = side(s, right: i == 1, max(102 * u, edge), s.minY + max(40 * u, edge)) }
        g.clickR = 17 * u
        let top = s.minY + max(22 * u, sep ? 14 : 0), w = 50 * u, h = 28 * u
        for i in 0..<2 {
            let x = s.midX + (i == 1 ? 52 : -52) * u
            g.pill[i] = CGRect(x: x - w / 2, y: top - h / 2, width: w, height: h)
        }
        g.swap = CGPoint(x: s.midX, y: top); g.swapR = 15 * u
        for i in 0..<4 { g.faceKey[i] = diamondKey(g.face, g.faceGap, i) }
        return g
    }

    func dropTip(_ i: Int) -> CGPoint {
        let a = i >= 2 ? -Double.pi / 4 : -3 * Double.pi / 4, d = dropR[i] * 1.45
        return CGPoint(x: drop[i].x + d * cos(a), y: drop[i].y + d * sin(a))
    }

    var shapes: [Shape] {
        var out: [Shape] = []
        for i in 0..<4 { out.append(Shape(c: faceKey[i], r: faceR, within: corner, id: Self.shapeFace + i)) }
        out.append(Shape(c: stick, r: stickR, within: corner, id: Self.shapeStick))
        if full { out.append(Shape(c: dpad, r: hypot(dpadR, armW), within: corner, id: Self.shapeDpad)) }
        for i in 0..<4 {
            out.append(Shape(c: drop[i], r: dropR[i], within: safe, id: Self.shapeDrop + i))
            out.append(Shape(c: dropTip(i), r: 0, within: safe, id: Self.shapeTip + i))
        }
        if full { for i in 0..<2 { out.append(Shape(c: click[i], r: clickR, within: safe, id: Self.shapeClick + i)) } }
        for i in 0..<2 { out.append(Shape(rect: pill[i], isRect: true, within: safe, id: Self.shapePill + i)) }
        out.append(Shape(c: swap, r: swapR, within: safe, id: Self.shapeSwap))
        return out
    }
    static func inside(_ s: Shape) -> Bool {
        let e: CGFloat = 0.5, b = s.box, w = s.within
        return b.minX >= w.minX - e && b.maxX <= w.maxX + e && b.minY >= w.minY - e && b.maxY <= w.maxY + e
    }
    static func overlap(_ a: Shape, _ b: Shape) -> Bool {
        let e: CGFloat = 0.5
        if a.isRect && b.isRect { return a.rect.insetBy(dx: e, dy: e).intersects(b.rect.insetBy(dx: e, dy: e)) }
        if a.isRect || b.isRect {
            let r = a.isRect ? a : b, c = a.isRect ? b : a
            let nx = max(r.rect.minX, min(c.c.x, r.rect.maxX)), ny = max(r.rect.minY, min(c.c.y, r.rect.maxY))
            return hypot(c.c.x - nx, c.c.y - ny) < c.r - e
        }
        return hypot(a.c.x - b.c.x, a.c.y - b.c.y) < a.r + b.r - e
    }
    static func sameControl(_ a: Shape, _ b: Shape) -> Bool {
        (a.id >= shapeDrop && a.id < shapeTip && b.id == a.id + 4) || (b.id >= shapeDrop && b.id < shapeTip && a.id == b.id + 4)
    }
    var fits: Bool {
        let s = shapes
        for i in s.indices {
            if !Self.inside(s[i]) { return false }
            for j in s.indices where j > i { if !Self.sameControl(s[i], s[j]) && Self.overlap(s[i], s[j]) { return false } }
        }
        return true
    }

    // MARK: dm_pad_geo_placed

    static func baseUnit(_ screen: PadScreen, _ region: Region) -> CGFloat {
        let bounds = CGRect(origin: .zero, size: screen.size)
        if !region.separated { return min(bounds.height / 430.0, 1.3) }
        let s = region.controls.intersection(inset(bounds, gameSafeInsets(bounds, screen.insets, region.topSafeOnly)))
        return min(min(s.height / 430.0, s.width / 700.0), 1.3)
    }
    /// DM_TOUCH_SIZE's scale: small 0.8, medium 1, large 1.2.
    static func scale(_ size: String) -> CGFloat { size == "small" ? 0.8 : size == "large" ? 1.2 : 1 }

    /// The geometry before the arrangement: the size, moved toward medium until it fits, and the left stick's place.
    static func placed(_ screen: PadScreen, full: Bool, size: String, stick place: String) -> PadGeo {
        let region = region(screen)
        let u0 = baseUnit(screen, region)
        var scale = Self.scale(size)
        var g = at(screen, region, full: full, u: u0 * scale)
        while scale != 1 && !g.fits {
            scale = scale > 1 ? max(1, scale - 0.05) : min(1, scale + 0.05)
            g = at(screen, region, full: full, u: u0 * scale)
        }
        if place == "higher" || place == "inward" {
            let up = place == "higher"
            let stick = g.stick, dpad = g.dpad
            var d = (up ? 70 : 60) * g.u
            while d > 0 {
                if up { g.stick = CGPoint(x: stick.x, y: stick.y - d) }
                else { g.stick = CGPoint(x: stick.x + d, y: stick.y); g.dpad = CGPoint(x: dpad.x + d, y: dpad.y) }
                if g.fits { return g }
                d -= 2 * g.u
            }
            g.stick = stick; g.dpad = dpad
        }
        return g
    }

    // MARK: dm_pad_arrange

    static func isShape(_ id: Int, of c: TouchLayout.Control) -> Bool {
        switch c {
        case .face: id >= shapeFace && id < shapeFace + 4
        case .a: id == shapeFace
        case .b: id == shapeFace + 1
        case .x: id == shapeFace + 2
        case .y: id == shapeFace + 3
        case .stick: id == shapeStick
        case .dpad: id == shapeDpad
        case .l3: id == shapeClick
        case .r3: id == shapeClick + 1
        case .minus: id == shapePill
        case .plus: id == shapePill + 1
        case .zl, .l, .zr, .r:
            id == shapeDrop + dropIndex(c) || id == shapeTip + dropIndex(c)
        }
    }
    static func dropIndex(_ c: TouchLayout.Control) -> Int { c == .zl ? 0 : c == .l ? 1 : c == .zr ? 2 : 3 }

    mutating func move(_ c: TouchLayout.Control, _ dx: CGFloat, _ dy: CGFloat) {
        func shift(_ p: inout CGPoint) { p.x += dx; p.y += dy }
        switch c {
        case .face: shift(&face); for i in 0..<4 { shift(&faceKey[i]) }
        case .a: shift(&faceKey[0])
        case .b: shift(&faceKey[1])
        case .x: shift(&faceKey[2])
        case .y: shift(&faceKey[3])
        case .stick: shift(&stick)
        case .dpad: shift(&dpad)
        case .l3: shift(&click[0])
        case .r3: shift(&click[1])
        case .minus: shift(&pill[0].origin)
        case .plus: shift(&pill[1].origin)
        case .zl, .l, .zr, .r: shift(&drop[Self.dropIndex(c)])
        }
    }
    static func near(_ a: Shape, _ b: Shape, _ gap: CGFloat) -> Bool {
        var x = a
        if x.isRect { x.rect = x.rect.insetBy(dx: -gap, dy: -gap) } else { x.r += gap }
        return overlap(x, b)
    }
    /// The engine's rule for a moved control: inside its area, every other control at least the gap away, out of the menu button's hit circle.
    func controlFits(_ c: TouchLayout.Control) -> Bool {
        let s = shapes, gap = max(10 * u, 10)
        for i in s.indices where Self.isShape(s[i].id, of: c) {
            if !Self.inside(s[i]) { return false }
            for j in s.indices where !Self.isShape(s[j].id, of: c) {
                var o = s[j]
                if o.id == Self.shapeSwap { o.r = max(o.r + gap, max(swapR * 1.6, 22)) - gap }   // the menu button: its whole hit circle
                if Self.near(s[i], o, gap) { return false }
            }
        }
        return true
    }
    static func clamp1(_ lo: CGFloat, _ hi: CGFloat, _ rlo: CGFloat, _ rhi: CGFloat) -> CGFloat {
        if hi - lo > rhi - rlo { return (rlo + rhi) / 2 - (lo + hi) / 2 }
        return lo < rlo ? rlo - lo : hi > rhi ? rhi - hi : 0
    }
    /// The shapes' box of a control and the area it must stay in.
    func box(of c: TouchLayout.Control) -> (box: CGRect, within: CGRect)? {
        var x0 = CGFloat.greatestFiniteMagnitude, y0 = x0, x1 = -x0, y1 = -x0, within: CGRect?
        for s in shapes where Self.isShape(s.id, of: c) {
            let b = s.box; within = s.within
            x0 = min(x0, b.minX); y0 = min(y0, b.minY); x1 = max(x1, b.maxX); y1 = max(y1, b.maxY)
        }
        guard let within else { return nil }
        return (CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), within)
    }
    func clamp(_ c: TouchLayout.Control) -> CGVector {
        guard let (b, w) = box(of: c) else { return .zero }
        return CGVector(dx: Self.clamp1(b.minX, b.maxX, w.minX, w.maxX), dy: Self.clamp1(b.minY, b.maxY, w.minY, w.maxY))
    }

    mutating func arrange(_ offsets: [TouchLayout.Control: TouchLayout.Offset]) {
        let step = self.step
        let want = TouchLayout.Control.allCases.filter { $0.drawn(full: full) && !(offsets[$0]?.isZero ?? true) }
        for round in 0..<2 {
            var todo = want.filter { $0.isFaceKey == (round == 1) }
            var progress = true
            while !todo.isEmpty && progress {
                progress = false
                for c in TouchLayout.Control.allCases where todo.contains(c) {
                    var t = self
                    let o = offsets[c] ?? .zero
                    t.move(c, CGFloat(o.dx) * step, CGFloat(o.dy) * step)
                    let d = t.clamp(c)
                    t.move(c, d.dx, d.dy)
                    if !t.controlFits(c) { continue }
                    self = t; moved.insert(c); todo.removeAll { $0 == c }; progress = true
                    if c.isFaceKey { faceSplit = true }
                }
            }
            dropped.formUnion(todo)
        }
    }

    /// What the engine draws for this layout: `dm_pad_geo` with the player's options.
    static func make(_ screen: PadScreen, full: Bool, size: String = "medium", stick: String = "corner", layout: TouchLayout = TouchLayout()) -> PadGeo {
        var g = placed(screen, full: full, size: size, stick: stick)
        let kind = TouchLayout.Kind.of(full: full, split: g.region.separated)
        if !layout.isEmpty(kind) { g.arrange(layout.moved(kind)) }
        return g
    }

    // MARK: Where a control is, for the editor

    /// The point a control's offset moves: the diamond's centre, a key, the stick's or D-pad's centre, a teardrop's circle, a pill's centre.
    func anchor(_ c: TouchLayout.Control) -> CGPoint {
        switch c {
        case .face: face
        case .a: faceKey[0]
        case .b: faceKey[1]
        case .x: faceKey[2]
        case .y: faceKey[3]
        case .stick: stick
        case .dpad: dpad
        case .l3: click[0]
        case .r3: click[1]
        case .minus: CGPoint(x: pill[0].midX, y: pill[0].midY)
        case .plus: CGPoint(x: pill[1].midX, y: pill[1].midY)
        case .zl, .l, .zr, .r: drop[Self.dropIndex(c)]
        }
    }
    /// The controls drawn in this layout, the diamond as its four keys.
    var drawnControls: [TouchLayout.Control] {
        TouchLayout.Control.allCases.filter { $0 != .face && $0.drawn(full: full) }
    }
}
