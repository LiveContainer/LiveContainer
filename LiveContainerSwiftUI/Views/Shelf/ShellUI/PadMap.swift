import Foundation

/// Physical controller buttons in the engine's input_map.h order. Sticks and shell navigation are unaffected.
public struct PadMap: Equatable, Sendable {
    public static let buttons = ["A", "B", "X", "Y", "LS", "RS", "L", "R", "ZL", "ZR", "Plus", "Minus", "Left", "Up", "Right", "Down"]
    public private(set) var entries: [String: String]

    public init(_ entries: [String: String] = [:]) {
        self.entries = Self.validated(entries).filter { $0.key != $0.value }
    }

    /// Game overrides keep identities, since A=A must be able to override a global A=B.
    public static func validated(_ entries: [String: String]) -> [String: String] {
        entries.filter { buttons.contains($0.key) && (buttons.contains($0.value) || $0.value == "none") }
    }

    public func output(for button: String) -> String { entries[button] ?? button }
    public var swapAB: Bool { output(for: "A") == "B" && output(for: "B") == "A" }
    public var envValue: String? {
        let pairs = Self.buttons.compactMap { key in entries[key].map { "\(key)=\($0)" } }
        return pairs.isEmpty ? nil : pairs.joined(separator: ",")
    }
    public mutating func set(_ button: String, to output: String) {
        guard Self.validated([button: output])[button] != nil else { return }
        entries[button] = output == button ? nil : output
    }
    public mutating func setSwapAB(_ on: Bool) {
        set("A", to: on ? "B" : "A")
        set("B", to: on ? "A" : "B")
    }
    public static func merged(global: PadMap, game: [String: String]) -> PadMap {
        PadMap(global.entries.merging(validated(game)) { _, game in game })
    }

    /// Nintendo names presented to the player, localized in ShellUI for both mapping pages.
    public static func label(_ button: String) -> String {
        switch button {
        case "Plus": "+"
        case "Minus": "−"
        case "LS": ShellStrings.text("Left stick press")
        case "RS": ShellStrings.text("Right stick press")
        case "Left": ShellStrings.text("D-pad left")
        case "Up": ShellStrings.text("D-pad up")
        case "Right": ShellStrings.text("D-pad right")
        case "Down": ShellStrings.text("D-pad down")
        case "none": ShellStrings.text("None")
        default: button
        }
    }
    public static var options: [SettingOption] { (buttons + ["none"]).map { SettingOption($0, label($0)) } }

    /// The Switch button at an element's place on the drawn controller, by position as the engine maps a controller: the
    /// right face button (Xbox's B) is A, the bottom one B, the top one X, the left one Y, View is − and Menu is +.
    /// Nil for the Xbox button, which no game sees.
    static func button(at element: PadElement) -> String? {
        switch element {
        case .b: "A"
        case .a: "B"
        case .y: "X"
        case .x: "Y"
        case .leftBumper: "L"
        case .rightBumper: "R"
        case .leftTrigger: "ZL"
        case .rightTrigger: "ZR"
        case .leftStick: "LS"
        case .rightStick: "RS"
        case .menu: "Plus"
        case .view: "Minus"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .home: nil
        }
    }
    /// The element a Switch button sits at on the drawing.
    static func element(of button: String) -> PadElement? { PadElement.allCases.first { self.button(at: $0) == button } }

    /// The 16 buttons in the four groups the mapping card shows, each with its heading. The D-pad reads up, down, left, right.
    static var groups: [(title: String, buttons: [String])] {
        [(ShellStrings.text("Face buttons"), ["A", "B", "X", "Y"]),
         (ShellStrings.text("Shoulders and triggers"), ["L", "R", "ZL", "ZR"]),
         (ShellStrings.text("D-pad"), ["Up", "Down", "Left", "Right"]),
         (ShellStrings.text("More buttons"), ["LS", "RS", "Plus", "Minus"])]
    }

    /// Where a button sits on the controller, next to its glyph. The names are a Switch controller's, by position, as the
    /// engine maps every controller: A is the right face button, B the bottom one.
    static func place(_ button: String) -> String {
        switch button {
        case "A": ShellStrings.text("Right button")
        case "B": ShellStrings.text("Bottom button")
        case "X": ShellStrings.text("Top button")
        case "Y": ShellStrings.text("Left button")
        case "L": ShellStrings.text("Left shoulder")
        case "R": ShellStrings.text("Right shoulder")
        case "ZL": ShellStrings.text("Left trigger")
        case "ZR": ShellStrings.text("Right trigger")
        case "Up": ShellStrings.text("Up")
        case "Down": ShellStrings.text("Down")
        case "Left": ShellStrings.text("Left")
        case "Right": ShellStrings.text("Right")
        case "LS": ShellStrings.text("Left stick press")
        case "RS": ShellStrings.text("Right stick press")
        case "Plus": ShellStrings.text("Plus")
        case "Minus": ShellStrings.text("Minus")
        default: label(button)
        }
    }
}
