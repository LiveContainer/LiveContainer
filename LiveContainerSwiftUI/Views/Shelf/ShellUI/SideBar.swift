import SwiftUI

/// iPhone Duo (#622) keeps a column on one side of the screen for the status bar and the system's vertical bars. The column lies
/// outside the safe area, so the library leaves it empty. Apple's design guide counts the app's own toolbar among the controls on
/// the side, and `toolbarVerticalEdge` (iOS 27.1) is there to place custom bars beside the system's. So where the system uses that
/// column, the shell's own bar goes into it: the game's settings (or Back while they are open) at the top of the free part, the
/// Controllers and Settings chips at the bottom.
/// Nothing here knows the device: only the edge the system names, the safe area and the occluded areas decide. In the iPhone Duo
/// Simulator (iOS 27.2) the occluded areas include the status bar and the Dynamic Island in every pose, and the status bar is at
/// the top of the column upright and hidden on the side, where the Dynamic Island is at one end of the column.
public struct SideBar: Equatable, Sendable {
    /// The edge of the system's vertical bar, nil where the system never places one (every other iPhone and iPad).
    public var edge: HorizontalEdge?
    /// Areas the status bar, a camera or the Dynamic Island covers, in the screen's coordinates (`reservedRegions(kind: .occlusion)`).
    public var occlusions: [CGRect]

    public init(edge: HorizontalEdge?, occlusions: [CGRect] = []) {
        self.edge = edge
        self.occlusions = occlusions
    }

    /// A chip in the column: this wide, and the Controllers chip a little taller for its count under the symbol.
    public static let chipWidth: CGFloat = 52
    public static let heights: [CGFloat] = [56, 44]
    /// S2Arm (#623): the player chip above them when the host has players, its symbol over the name's first letters.
    public static let playerHeight: CGFloat = 56
    /// The one chip at the top of the column: the game's settings, or Back.
    public static let topHeights: [CGFloat] = [44]
    public static let gap: CGFloat = 10
    public static let margin: CGFloat = 12
    /// Kept free at an end of the column that has no inset, where the screen's corner rounds off.
    public static let corner: CGFloat = 28
    /// The least room between the top chip and the chips at the bottom, so they read as two groups.
    public static let groupGap: CGFloat = 24

    /// Where the column's chips go, in the screen's coordinates.
    public struct Placement: Equatable, Sendable {
        /// The Controllers and Settings chips, at the bottom of the column's free part.
        public var bottom: CGRect
        /// The game's settings or Back, at the top of the free part. Nil when there is no room, or nothing reports the status bar.
        public var top: CGRect?
    }

    /// The chips' frames for chips of `bottom` and `top` heights, or nil to keep them all in the header: no vertical bar, a column
    /// too narrow for a chip, or no free part of the column tall enough. The free part is the column between the ends of the
    /// screen (above the home indicator, below any top inset) without the occluded areas. Where the system reports no occluded
    /// area in the column, the status bar's place is unknown: then only the bottom chips may go there, and only in the lower half.
    public func place(screen: CGSize, insets: EdgeInsets, bottom: [CGFloat] = SideBar.heights, top: [CGFloat] = []) -> Placement? {
        guard let edge, !bottom.isEmpty else { return nil }
        let side = edge == .trailing ? insets.trailing : insets.leading
        guard side >= Self.chipWidth else { return nil }
        let x = (edge == .trailing ? screen.width - side : 0) + (side - Self.chipWidth) / 2
        let strip = (x, x + Self.chipWidth)
        let blocked = occlusions.filter { $0.minX < strip.1 && $0.maxX > strip.0 && $0.height > 0 }
            .map { ($0.minY - Self.margin, $0.maxY + Self.margin) }
        let low = insets.top > 0 ? insets.top + Self.margin : Self.corner
        let high = screen.height - (insets.bottom > 0 ? insets.bottom + Self.margin : Self.corner)
        let free = Self.subtract(blocked, from: (low, high))
        let height = Self.stack(bottom)
        guard let lowest = free.last(where: { $0.1 - $0.0 >= height }) else { return nil }
        let frame = CGRect(x: x, y: lowest.1 - height, width: Self.chipWidth, height: height)
        // No occluded area in the column: the status bar could be anywhere in its top half.
        if blocked.isEmpty { return frame.minY >= screen.height / 2 ? Placement(bottom: frame, top: nil) : nil }
        guard !top.isEmpty else { return Placement(bottom: frame, top: nil) }
        let above = Self.subtract([(frame.minY - Self.groupGap, .infinity)], from: free)
        let topHeight = Self.stack(top)
        let first = above.first { $0.1 - $0.0 >= topHeight }
        return Placement(bottom: frame, top: first.map { CGRect(x: x, y: $0.0, width: Self.chipWidth, height: topHeight) })
    }

    /// The bottom chips' frame alone, as `place` puts them.
    public func column(screen: CGSize, insets: EdgeInsets, heights: [CGFloat] = SideBar.heights) -> CGRect? {
        place(screen: screen, insets: insets, bottom: heights)?.bottom
    }

    private static func stack(_ heights: [CGFloat]) -> CGFloat { heights.reduce(0, +) + gap * CGFloat(max(0, heights.count - 1)) }

    /// The parts of `ranges` (sorted, top first) that none of `cuts` covers.
    private static func subtract(_ cuts: [(CGFloat, CGFloat)], from ranges: [(CGFloat, CGFloat)]) -> [(CGFloat, CGFloat)] {
        var parts = ranges.filter { $0.1 > $0.0 }
        for cut in cuts {
            parts = parts.flatMap { part -> [(CGFloat, CGFloat)] in
                guard cut.0 < part.1, cut.1 > part.0 else { return [part] }
                return [(part.0, cut.0), (cut.1, part.1)].filter { $0.1 > $0.0 }
            }
        }
        return parts
    }

    private static func subtract(_ cuts: [(CGFloat, CGFloat)], from range: (CGFloat, CGFloat)) -> [(CGFloat, CGFloat)] {
        subtract(cuts, from: [range])
    }
}

extension EnvironmentValues {
    /// The side column as the shell sees it. Nil reads it from the system (iOS 27.1). The captures set it to simulate iPhone Duo.
    @Entry public var shellSideBar: SideBar? = nil
}

/// Reads the system's vertical-bar edge and the occluded areas, in the coordinates of the view it is the background of.
struct SideBarProbe: View {
    let report: (SideBar) -> Void
    var body: some View {
        #if canImport(SwiftUI, _version: 8.1)
        if #available(iOS 27.1, macOS 27.1, *) { SideBarReader(report: report) } else { Color.clear }
        #else
        Color.clear
        #endif
    }
}

#if canImport(SwiftUI, _version: 8.1)
@available(iOS 27.1, macOS 27.1, *)
private struct SideBarReader: View {
    let report: (SideBar) -> Void
    @Environment(\.toolbarVerticalEdge) private var edge
    var body: some View {
        GeometryReader { proxy in
            let bar = SideBar(edge: edge, occlusions: proxy.reservedRegions(kind: .occlusion).map(\.frame))
            Color.clear.onChange(of: bar, initial: true) { _, new in report(new) }
        }
    }
}
#endif

/// The Controllers and Settings chips stacked in the side column.
struct SideBarChips: View {
    let controllers: Int
    let openControllers: () -> Void
    let openShellSettings: () -> Void
    var body: some View {
        VStack(spacing: SideBar.gap) {
            PlayerChip(vertical: true)   // S2Arm (#623); draws nothing without players
            ControllerChip(count: controllers, vertical: true, action: openControllers)
            ShellSettingsChip(vertical: true, action: openShellSettings)
        }
    }
}

/// The chip at the top of the side column: the selected game's settings in the library, Back while they are open. It keeps the
/// accessibility label, identifier and focus target of the button it stands in for, so VoiceOver, the UI tests and a controller
/// find it as before.
struct SideBarTopChip: View {
    let symbol: String
    let label: String
    let identifier: String
    let target: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: SideBar.chipWidth - 28, height: SideBar.topHeights[0])
        }
        .buttonStyle(ChipButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .shellTarget(target, radius: 22, action: action)
    }
}

extension View {
    /// Puts a side-column chip at `frame`, given in the screen's coordinates, inside a view laid out in the safe area.
    func sideBarFrame(_ frame: CGRect, insets: EdgeInsets) -> some View {
        self.frame(width: frame.width, height: frame.height).offset(x: frame.minX - insets.leading, y: frame.minY - insets.top)
    }
}
