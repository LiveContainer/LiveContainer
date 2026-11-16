import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The S-grade block of a game's settings (11-13: community patches and cheats are the highlight of the beta, so they sit in one
/// gold block, not two plain groups): the gold glass S (Resources/s-gold.png, the same art as the launchers' export card), a champagne
/// to rose-gold title and border, and the patches and cheats as two sub-sections of switches.
/// The gold S on a library cover (v0.4.0): this game has S-grade enhancements built in. Just the S — no frame, no backing;
/// a faint drop shadow keeps it readable on light key art.
struct SGradeBadge: View {
    var size: CGFloat = 22
    var body: some View {
        let s = SGradeGroup.sGold.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        s.overlay(s).overlay(s)   // the glass S is translucent: two more layers keep it solid
            .brightness(0.22).saturation(1.35)   // brighter overall, so it reads on top of key art
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.45), radius: size * 0.12, y: size * 0.04)
            .accessibilityHidden(true)
    }
}

struct SGradeGroup: View {
    let gameID: String
    let sections: [SettingSection]
    let onChange: (String, String) -> Void
    static let goldHi = Color(red: 1, green: 0.92, blue: 0.70), gold = Color(red: 0.93, green: 0.77, blue: 0.42), rose = Color(red: 0.93, green: 0.62, blue: 0.52)
    static let ids: Set<String> = ["s2a.patches", "s2a.cheats"]
    /// 金色 S：包里是散放的 PNG（不是素材目录），按文件路径读
    static let sGold: Image = {
        guard let path = Bundle.module.path(forResource: "s-gold", ofType: "png") else { return Image(systemName: "sparkles") }
        #if canImport(UIKit)
        return UIImage(contentsOfFile: path).map { Image(uiImage: $0) } ?? Image(systemName: "sparkles")
        #else
        return NSImage(contentsOfFile: path).map { Image(nsImage: $0) } ?? Image(systemName: "sparkles")
        #endif
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 14) {
                Self.sGold.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: 46, height: 46).shadow(color: Self.gold.opacity(0.5), radius: 12).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ShellStrings.text("S-grade enhancements")).shellText(18, .bold)
                            .foregroundStyle(LinearGradient(colors: [Self.goldHi, Self.gold, Self.rose], startPoint: .leading, endPoint: .trailing))
                            .accessibilityAddTraits(.isHeader)
                        Text("BETA").shellText(9.5, .bold).tracking(1.4).padding(.horizontal, 7).padding(.vertical, 2)
                            .foregroundStyle(Self.gold).overlay(Capsule().strokeBorder(Self.gold.opacity(0.55), lineWidth: 1))
                    }
                    Text(ShellStrings.text("If a patch is incompatible and makes the game crash, it is turned off automatically the next time you launch, so you can keep playing."))
                        .shellType(ShellType.note).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title.uppercased()).shellType(ShellType.sectionCaps).foregroundStyle(Self.gold.opacity(0.85))
                    if section.id == "s2a.cheats" { cheatsList(section.rows) } else { rowList(section.rows) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(ShellPalette.surface)
                RoundedRectangle(cornerRadius: 18).fill(RadialGradient(colors: [Self.gold.opacity(0.17), .clear], center: .topLeading, startRadius: 0, endRadius: 380))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LinearGradient(colors: [Self.goldHi.opacity(0.75), Self.gold.opacity(0.12), Self.rose.opacity(0.55)],
                                                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: Self.gold.opacity(0.14), radius: 20, y: 6)
        .accessibilityIdentifier("set.sgrade")
    }

    @ViewBuilder private func rowList(_ rows: [SettingRow]) -> some View {
        ForEach(rows) { row in
            SettingControl(gameID: gameID, row: row) { onChange(row.id, $0) }.equatable()
            if row.id != rows.last?.id { Rectangle().fill(Self.gold.opacity(0.14)).frame(height: 1) }
        }
    }

    /// 金手指默认收起（11-13：一款几十条会把专区顶得很长）：一行「已开 n 条 · 共 m 条」，点开才列；列表限高、自己滚，多于 10 条带搜索（同 Mac 启动设置）
    @State private var cheatsOpen: Bool?
    /// 一打开就展开（离屏单测出展开态用）
    var startOpen = false
    @State private var query = ""
    private var open: Bool { cheatsOpen ?? startOpen }
    static let listMaxHeight: CGFloat = 320

    @ViewBuilder private func cheatsList(_ rows: [SettingRow]) -> some View {
        let on = rows.filter { $0.value == "on" }.count
        Button { withAnimation(.easeOut(duration: 0.2)) { cheatsOpen = !open } } label: {
            HStack {
                Text(String(format: ShellStrings.text("%lld on · %lld in all"), on, rows.count)).shellText(15, .medium).foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Self.gold.opacity(0.8))
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .frame(minHeight: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("set.cheats.toggleList")
        if open {
            if rows.count > 10 {
                TextField(ShellStrings.text("Search cheats"), text: $query).textFieldStyle(.plain).shellText(14)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("set.cheats.search")
            }
            let shown = query.isEmpty ? rows : rows.filter { $0.label.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query) }
            ScrollView { VStack(alignment: .leading, spacing: 12) { rowList(shown) } }
                .frame(maxHeight: Self.listMaxHeight).fixedSize(horizontal: false, vertical: shown.count <= 4)
        }
    }
}
