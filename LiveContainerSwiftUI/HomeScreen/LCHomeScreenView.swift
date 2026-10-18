import SwiftUI
import UniformTypeIdentifiers

struct LCHomeScreenView: View {
    let apps: [LCAppModel]
    let delegate: LCAppBannerDelegate
    let importing: Bool
    let installProgress: Float
    let importIPA: () -> Void
    let importURL: () -> Void
    let openLink: () -> Void
    let openSideStore: (() -> Void)?
    @EnvironmentObject private var shared: SharedModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("LCOSHomeScreenEnabled", store: LCUtils.appGroupUserDefault) private var homeEnabled = true
    @AppStorage("LCOSHomeWallpaper", store: LCUtils.appGroupUserDefault) private var wallpaper = "dusk"
    @AppStorage("LCOSHomeLayout", store: LCUtils.appGroupUserDefault) private var layoutJSON = ""
    @State private var page = 0
    @State private var query = ""
    @State private var searching = false
    @State private var draggedID: String?
    @State private var dockFull = false
    @State private var resetConfirmation = false
    @FocusState private var searchFocused: Bool

    private static let dragType = UTType(exportedAs: "org.livecontainer.desktop-app")
    private var available: [String] { apps.map(identifier) }
    private var layout: LCHomeLayout {
        guard let data = layoutJSON.data(using: .utf8),
              let value = try? JSONDecoder().decode(LCHomeLayout.self, from: data), value.version == 1 else { return LCHomeLayout() }
        return value
    }
    private func identifier(_ app: LCAppModel) -> String {
        "\(app.bundleIdentifier):\(app.appInfo.relativeBundlePath ?? app.bundleIdentifier)"
    }
    private func save(_ value: LCHomeLayout) {
        guard let data = try? JSONEncoder().encode(value), let string = String(data: data, encoding: .utf8) else { return }
        layoutJSON = string
        UISelectionFeedbackGenerator().selectionChanged()
    }

    var body: some View {
        GeometryReader { geometry in
            let regular = geometry.size.width >= 600
            let capacity = regular ? 6 : 4
            let side: CGFloat = sizeCategory.isAccessibilityCategory ? 70 : regular ? 68 : 62
            let columns = max(2, min(regular ? 6 : 4, Int((geometry.size.width - 28) / (side + 18))))
            let rows = max(1, Int((geometry.size.height - 246) / (side + 46)))
            let perPage = columns * rows
            let pins = layout.pinned(available, capacity: capacity)
            let ordered = layout.ordered(available)
            let displayed = ordered.filter { id in
                guard let app = apps.first(where: { identifier($0) == id }) else { return false }
                if !query.isEmpty {
                    return app.displayName.localizedCaseInsensitiveContains(query) || app.bundleIdentifier.localizedCaseInsensitiveContains(query)
                }
                return !pins.contains(id)
            }
            let pageCount = max(1, (displayed.count + perPage - 1) / perPage)
            ZStack {
                LCHomeWallpaper(style: wallpaper)
                VStack(spacing: 8) {
                    header
                    if searching { searchField }
                    if importing {
                        ProgressView(value: Double(installProgress)) { Text("lc.appList.installation".loc) }
                            .padding(.horizontal, 24).font(.caption)
                    }
                    if apps.isEmpty { emptyState }
                    else if displayed.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: query.isEmpty ? "dock.rectangle" : "magnifyingglass").font(.largeTitle)
                            Text(query.isEmpty ? "lcos.home.inDock".loc : "lcos.home.noResults".loc).font(.subheadline)
                        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TabView(selection: $page) {
                            ForEach(0..<pageCount, id: \.self) { index in
                                let ids = Array(displayed.dropFirst(index * perPage).prefix(perPage))
                                ScrollView(showsIndicators: false) {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columns), spacing: 16) {
                                        ForEach(ids, id: \.self) { id in
                                            homeIcon(id, side: side, docked: false, capacity: capacity)
                                        }
                                    }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                                }
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                    if pageCount > 1 {
                        HStack(spacing: 10) {
                            ForEach(0..<pageCount, id: \.self) { index in
                                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page = index } } label: {
                                    Circle().fill(Color.primary.opacity(page == index ? 0.8 : 0.23)).frame(width: 6, height: 6)
                                        .padding(.vertical, 10).padding(.horizontal, 3).contentShape(Rectangle())
                                }
                                .accessibilityLabel("lcos.home.page".localizeWithFormat(index + 1))
                                .accessibilityAddTraits(page == index ? .isSelected : [])
                                .onDrop(of: [Self.dragType], isTargeted: nil) { _ in
                                    guard let id = draggedID, let target = displayed.dropFirst(index * perPage).first else { return false }
                                    move(id, before: target, docked: false, capacity: capacity)
                                    page = index
                                    return true
                                }
                            }
                        }
                    }
                    if !searching {
                        Button { searching = true; searchFocused = true } label: {
                            Label("lcos.home.search".loc, systemImage: "magnifyingglass")
                                .font(.caption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.thinMaterial, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                    let dockSide = min(side, max(44, (min(geometry.size.width - 24, 540) - 32 - 14 * CGFloat(capacity - 1)) / CGFloat(capacity)))
                    dock(pins, side: dockSide, capacity: capacity)
                }
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: pageCount) { count in page = min(page, count - 1) }
            .onChange(of: query) { _ in page = 0 }
        }
        .alert("lcos.home.dockFull".loc, isPresented: $dockFull) { Button("lc.common.ok".loc, role: .cancel) {} }
        .confirmationDialog("lcos.home.reset".loc, isPresented: $resetConfirmation) {
            Button("lcos.home.reset".loc, role: .destructive) { save(LCHomeLayout()); page = 0 }
            Button("lc.common.cancel".loc, role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.subheadline.weight(.medium))
                Text("LiveContainer").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if shared.multiLCStatus != 2 {
                Menu {
                    Button("lc.appList.installFromIpa".loc, action: importIPA)
                    Button("lc.appList.installFromUrl".loc, action: importURL)
                } label: { chromeIcon("plus") }
                .accessibilityLabel("lc.appList.installFromIpa".loc).disabled(importing)
            }
            Menu {
                Toggle("lcos.home.enabled".loc, isOn: $homeEnabled)
                Picker("lcos.home.wallpaper".loc, selection: $wallpaper) {
                    Text("lcos.home.dusk".loc).tag("dusk")
                    Text("lcos.home.ocean".loc).tag("ocean")
                    Text("lcos.home.dawn".loc).tag("dawn")
                }
                Button("lcos.home.list".loc) { homeEnabled = false }
                Button("lc.appList.openLink".loc, action: openLink)
                if let openSideStore { Button("SideStore", action: openSideStore) }
                Divider()
                if shared.multiLCStatus != 2 {
                    Button("lc.tabView.tweaks".loc) { shared.selectedTab = .tweaks }
                }
                Button("lc.tabView.settings".loc) { shared.selectedTab = .settings }
                Button("lcos.home.reset".loc) { resetConfirmation = true }
            } label: { chromeIcon("ellipsis") }
            .accessibilityLabel("lcos.home.options".loc)
        }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 2)
    }

    private func chromeIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .medium))
            .frame(width: 40, height: 40).background(.thinMaterial, in: Circle())
            .foregroundStyle(.primary)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("lcos.home.search".loc, text: $query)
                .textInputAutocapitalization(.never).disableAutocorrection(true)
                .focused($searchFocused).submitLabel(.search)
            Button { query = ""; searching = false; searchFocused = false } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 32, height: 32)
            }.accessibilityLabel("lc.common.cancel".loc)
        }.padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.grid.2x2").font(.system(size: 40, weight: .light))
                .padding(24).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            Text("lcos.home.emptyTitle".loc).font(.title2.weight(.semibold))
            Text("lcos.home.emptyBody".loc).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
            if shared.multiLCStatus != 2 {
                Button("lc.appList.installFromIpa".loc, action: importIPA).buttonStyle(.borderedProminent).disabled(importing)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func homeIcon(_ id: String, side: CGFloat, docked: Bool, capacity: Int) -> some View {
        if let app = apps.first(where: { identifier($0) == id }) {
            LCAppBanner(appModel: app, delegate: delegate, homeScreen: true, iconSide: side,
                        showLabel: !docked, isDocked: layout.dock.contains(id), onToggleDock: { toggleDock(id, capacity: capacity) })
                .frame(height: side + (docked ? 8 : 30))
                .onDrag {
                    draggedID = id
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(forTypeIdentifier: Self.dragType.identifier, visibility: .ownProcess) { complete in
                        complete(Data(id.utf8), nil)
                        return nil
                    }
                    return provider
                }
                .onDrop(of: [Self.dragType], isTargeted: nil) { _ in
                    guard let source = draggedID else { return false }
                    move(source, before: id, docked: docked, capacity: capacity)
                    return true
                }
        }
    }

    private func dock(_ pins: [String], side: CGFloat, capacity: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if pins.isEmpty {
                utility("magnifyingglass", title: "lcos.home.search".loc, color: .blue) { searching = true; searchFocused = true }
                if shared.multiLCStatus != 2 {
                    utility("shippingbox.fill", title: "lc.tabView.tweaks".loc, color: .orange) { shared.selectedTab = .tweaks }
                }
                if let openSideStore {
                    Button(action: openSideStore) {
                        IconImageView(icon: BuiltInSideStoreAppInfo.shared.iconIsDarkIcon(colorScheme == .dark))
                            .frame(width: 54, height: 54)
                    }.buttonStyle(.plain).frame(maxWidth: .infinity).accessibilityLabel("SideStore")
                }
                utility("gearshape.fill", title: "lc.tabView.settings".loc, color: .gray) { shared.selectedTab = .settings }
            } else {
                ForEach(pins, id: \.self) { id in
                    homeIcon(id, side: side, docked: true, capacity: capacity).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: 540, minHeight: side + 30)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(colorScheme == .dark ? 0.12 : 0.45), lineWidth: 0.5))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .onDrop(of: [Self.dragType], isTargeted: nil) { _ in
            guard let id = draggedID, available.contains(id) else { return false }
            if !pins.contains(id) { toggleDock(id, capacity: capacity) }
            draggedID = nil
            return true
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Dock")
    }

    private func utility(_ symbol: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 25, weight: .medium)).foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain).frame(maxWidth: .infinity).accessibilityLabel(title)
    }

    private func toggleDock(_ id: String, capacity: Int) {
        var updated = layout
        if !updated.dock.contains(id), updated.pinned(available, capacity: capacity).count >= capacity { dockFull = true; return }
        updated.toggleDock(id, available: available, capacity: capacity)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { save(updated) }
    }

    private func move(_ source: String, before target: String, docked: Bool, capacity: Int) {
        guard available.contains(source), available.contains(target), source != target else { draggedID = nil; return }
        var updated = layout
        if docked {
            var pins = updated.pinned(available, capacity: capacity)
            if !pins.contains(source), pins.count >= capacity { dockFull = true; return }
            pins.removeAll { $0 == source }
            pins.insert(source, at: pins.firstIndex(of: target) ?? pins.count)
            updated.dock = pins
        } else {
            updated.dock.removeAll { $0 == source }
            updated.move(source, before: target, available: available)
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { save(updated) }
        draggedID = nil
    }
}

struct LCHomeWallpaper: View {
    let style: String
    @Environment(\.colorScheme) private var scheme
    private var colors: [Color] {
        let dark = scheme == .dark
        switch style {
        case "ocean": return dark ? [Color(red: 0.03, green: 0.18, blue: 0.21), Color(red: 0.03, green: 0.36, blue: 0.38), Color(red: 0.07, green: 0.12, blue: 0.23)]
            : [Color(red: 0.77, green: 0.91, blue: 0.89), Color(red: 0.61, green: 0.83, blue: 0.82), Color(red: 0.83, green: 0.92, blue: 0.97)]
        case "dawn": return dark ? [Color(red: 0.24, green: 0.12, blue: 0.24), Color(red: 0.48, green: 0.23, blue: 0.29), Color(red: 0.13, green: 0.12, blue: 0.24)]
            : [Color(red: 0.98, green: 0.88, blue: 0.83), Color(red: 0.94, green: 0.73, blue: 0.72), Color(red: 0.84, green: 0.83, blue: 0.95)]
        default: return dark ? [Color(red: 0.10, green: 0.14, blue: 0.31), Color(red: 0.23, green: 0.30, blue: 0.53), Color(red: 0.08, green: 0.13, blue: 0.24)]
            : [Color(red: 0.88, green: 0.91, blue: 0.98), Color(red: 0.69, green: 0.78, blue: 0.94), Color(red: 0.83, green: 0.90, blue: 0.96)]
        }
    }
    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.07 : 0.26), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: g.size.width * 1.7, height: g.size.height * 0.9)
                    .rotationEffect(.degrees(-28)).offset(x: g.size.width * 0.22, y: g.size.height * 0.3)
                Ellipse().stroke(.white.opacity(scheme == .dark ? 0.05 : 0.18), lineWidth: g.size.width * 0.15)
                    .frame(width: g.size.width * 1.5, height: g.size.height * 0.85)
                    .rotationEffect(.degrees(-28)).offset(x: g.size.width * 0.42, y: g.size.height * 0.42)
            }.clipped()
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}
