import Foundation

/// The player's arrangement of the touch controls (#414): for each layout, how far each moved control sits from its built-in place.
/// The shell keeps it and passes it to every game as one `DM_TOUCH_LAYOUT` value, which the engine reads in `DmPadGeometry.h`
/// (`dm_pad_layout_parse`): `1`, then per layout `;`, its name and `/control:dx,dy` per moved control, for example
/// `1;2d/face:0,-2/stick:1,-1;3d/a:-1,0`. A step is a quarter of a face key's width at the player's size, y grows downward.
/// The engine stores nothing and places a control only where it fits, so a value can never break the layout.
public struct TouchLayout: Equatable, Sendable {
    /// The layouts with an arrangement of their own: 2D and 3D over the picture (a phone, an iPad held sideways), and both again
    /// below the picture (an iPad held upright, iPhone Duo upright or half open). The raw values are the engine's names.
    public enum Kind: String, CaseIterable, Sendable {
        case twoD = "2d", threeD = "3d", twoDSplit = "2s", threeDSplit = "3s"
        public var full: Bool { self == .threeD || self == .threeDSplit }
        public var split: Bool { self == .twoDSplit || self == .threeDSplit }
        public static func of(full: Bool, split: Bool) -> Kind { split ? (full ? .threeDSplit : .twoDSplit) : (full ? .threeD : .twoD) }
    }

    /// The controls that move, in the engine's order (the order it places them). `face` is the whole diamond, `a b x y` one key of
    /// it, from where the diamond is. The layout button does not move.
    public enum Control: String, CaseIterable, Sendable {
        case face, a, b, x, y, stick, dpad, zl, l, zr, r, l3, r3, minus, plus
        /// Drawn in this layout (the D-pad, L3 and R3 only in 3D).
        public func drawn(full: Bool) -> Bool { full || ![.dpad, .l3, .r3].contains(self) }
        public var isFaceKey: Bool { [.a, .b, .x, .y].contains(self) }
    }

    public struct Offset: Equatable, Hashable, Sendable {
        public var dx: Int
        public var dy: Int
        public init(dx: Int = 0, dy: Int = 0) { self.dx = dx; self.dy = dy }
        public static let zero = Offset()
        public var isZero: Bool { dx == 0 && dy == 0 }
    }

    /// The engine's limits: a step is -64 to 64, a value at most 1024 characters.
    public static let maxStep = 64
    public static let maxLength = 1024

    private var offsets: [Kind: [Control: Offset]] = [:]

    public init() {}

    public subscript(kind: Kind, control: Control) -> Offset {
        get { offsets[kind]?[control] ?? .zero }
        set {
            let clamped = Offset(dx: min(Self.maxStep, max(-Self.maxStep, newValue.dx)), dy: min(Self.maxStep, max(-Self.maxStep, newValue.dy)))
            var set = offsets[kind] ?? [:]
            set[control] = clamped.isZero ? nil : clamped
            offsets[kind] = set.isEmpty ? nil : set
        }
    }

    public var isEmpty: Bool { offsets.isEmpty }
    public func isEmpty(_ kind: Kind) -> Bool { offsets[kind] == nil }
    /// Every control of one layout back to its built-in place.
    public mutating func reset(_ kind: Kind) { offsets[kind] = nil }
    /// The moved controls of one layout.
    public func moved(_ kind: Kind) -> [Control: Offset] { offsets[kind] ?? [:] }

    /// The value for `DM_TOUCH_LAYOUT`, empty when nothing is moved (the engine's built-in layout, nothing is passed).
    public var encoded: String {
        guard !offsets.isEmpty else { return "" }
        var out = "1"
        for kind in Kind.allCases {
            guard let set = offsets[kind] else { continue }
            out += ";" + kind.rawValue
            for control in Control.allCases { if let o = set[control] { out += "/\(control.rawValue):\(o.dx),\(o.dy)" } }
        }
        return out
    }

    /// Reads a value as the engine does: an unknown layout or control is skipped, anything else that is not the form, or longer
    /// than the engine reads, gives nil (the engine ignores it whole). Empty is the built-in layout.
    public init?(encoded value: String) {
        self.init()
        guard !value.isEmpty else { return }
        let bytes = Array(value.utf8)
        guard bytes.count <= Self.maxLength, bytes[0] == UInt8(ascii: "1"), bytes.count == 1 || bytes[1] == UInt8(ascii: ";") else { return nil }
        var i = 1
        func step() -> Int? {
            var sign = 1, v = 0, digits = 0
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") { sign = -1; i += 1 }
            while i < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[i]) {
                digits += 1
                if digits > 3 { return nil }
                v = v * 10 + Int(bytes[i] - UInt8(ascii: "0")); i += 1
            }
            return digits > 0 && v <= Self.maxStep ? sign * v : nil
        }
        while i < bytes.count, bytes[i] == UInt8(ascii: ";") {
            i += 1
            let nameStart = i
            while i < bytes.count, bytes[i] != UInt8(ascii: "/"), bytes[i] != UInt8(ascii: ";") { i += 1 }
            let kind = Kind(rawValue: String(decoding: bytes[nameStart..<i], as: UTF8.self))
            while i < bytes.count, bytes[i] == UInt8(ascii: "/") {
                i += 1
                let start = i
                while i < bytes.count, (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(bytes[i]) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[i]) { i += 1 }
                guard i > start, i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return nil }
                let name = String(decoding: bytes[start..<i], as: UTF8.self)
                i += 1
                guard let dx = step(), i < bytes.count, bytes[i] == UInt8(ascii: ",") else { return nil }
                i += 1
                guard let dy = step() else { return nil }
                if let kind, let control = Control(rawValue: name) { self[kind, control] = Offset(dx: dx, dy: dy) }
            }
            if i < bytes.count, bytes[i] != UInt8(ascii: ";") { return nil }
        }
        if i < bytes.count { return nil }
    }
}
