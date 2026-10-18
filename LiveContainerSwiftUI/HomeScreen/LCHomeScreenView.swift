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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("LCOSHomeScreenEnabled", store: LCUtils.appGroupUserDefault) private var gridEnabled = true
    @AppStorage("LCOSHomeLayout", store: LCUtils.appGroupUserDefault) private var layoutJSON = ""
    @State private var page = 0
    @State private var query = ""
    @State private var searching = false
    @State private var editing = false
    @State private var jiggle = false
    @State private var draggedID: String?
    @State private var folderID: String?
    @State private var folderName = ""
    @State private var folderPage = 0
    @State private var hoveredID: String?
    @State private var folderCandidate: String?
    @State private var hoverTask: Task<Void, Never>?
    @State private var edgeTask: Task<Void, Never>?
    @State private var resetConfirmation = false
    @FocusState private var searchFocused: Bool
    @Namespace private var folderAnimation
    private static let dragType = UTType(exportedAs: "org.livecontainer.desktop-app")

    private var available: [String] { apps.map(identifier) }
    private var layout: LCHomeLayout {
        guard let data = layoutJSON.data(using: .utf8), let value = try? JSONDecoder().decode(LCHomeLayout.self, from: data),
              (1...2).contains(value.version) else { return LCHomeLayout() }
        return value.reconciled(available)
    }
    private func identifier(_ app: LCAppModel) -> String { "\(app.bundleIdentifier):\(app.appInfo.relativeBundlePath ?? app.bundleIdentifier)" }
    private func model(_ id: String) -> LCAppModel? { apps.first { identifier($0) == id } }
    private func save(_ value: LCHomeLayout) {
        guard let data = try? JSONEncoder().encode(value), let string = String(data: data, encoding: .utf8) else { return }
        layoutJSON = string
    }
    private func animate(_ action: () -> Void) { withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), action) }

    var body: some View {
        GeometryReader { geometry in
            let side: CGFloat = sizeCategory.isAccessibilityCategory ? 70 : 62
            let columns = max(2, min(geometry.size.width >= 600 ? 6 : 4, Int((min(geometry.size.width, 900) - 32) / (side + 18))))
            let rows = max(1, Int((geometry.size.height - (searching ? 190 : 150)) / (side + 48)))
            let perPage = columns * rows
            let ids = query.isEmpty ? layout.rootItems(available) : layout.ordered(available).filter { id in
                guard let app = model(id) else { return false }
                return app.displayName.localizedCaseInsensitiveContains(query) || app.bundleIdentifier.localizedCaseInsensitiveContains(query)
            }
            let count = max(1, (ids.count + perPage - 1) / perPage)
            ZStack {
                (scheme == .dark ? Color.black : Color.white).ignoresSafeArea()
                    .contentShape(Rectangle()).onLongPressGesture { startEditing() }
                VStack(spacing: 8) {
                    header
                    if searching { searchField }
                    if importing { ProgressView(value: Double(installProgress)).padding(.horizontal, 24) }
                    if apps.isEmpty { emptyState }
                    else if ids.isEmpty {
                        Text("lcos.home.noResults".loc).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TabView(selection: $page) {
                            ForEach(0..<count, id: \.self) { index in
                                ScrollView(showsIndicators: false) {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columns), spacing: 18) {
                                        ForEach(Array(ids.dropFirst(index * perPage).prefix(perPage)), id: \.self) { id in
                                            tile(id, side: side, container: nil)
                                        }
                                    }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                                }.lcSoftScrollEdges().tag(index)
                            }
                        }.tabViewStyle(.page(indexDisplayMode: .never))
                        .overlay(alignment: .leading) { pageEdge(-1, count: count) }
                        .overlay(alignment: .trailing) { pageEdge(1, count: count) }
                    }
                    if count > 1 { pageDots(count, selection: $page) }
                    if !searching {
                        Button { searching = true; searchFocused = true } label: {
                            Label("lcos.home.search".loc, systemImage: "magnifyingglass").font(.caption.weight(.medium))
                                .padding(.horizontal, 16).padding(.vertical, 10).lcGlass(in: Capsule(), interactive: true)
                        }.buttonStyle(.plain).padding(.bottom, 12)
                    }
                }.frame(maxWidth: 900).frame(maxWidth: .infinity)
                if let id = folderID, let folder = layout.folders.first(where: { $0.id == id }) {
                    folderOverlay(folder, width: geometry.size.width, side: side)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.88).combined(with: .opacity)).zIndex(2)
                }
            }
            .onChange(of: count) { page = min(page, $0 - 1) }
            .onChange(of: query) { _ in page = 0 }
        }
        .confirmationDialog("lcos.home.reset".loc, isPresented: $resetConfirmation) {
            Button("lcos.home.reset".loc, role: .destructive) { save(LCHomeLayout()); page = 0; folderID = nil }
        }
        .onChange(of: layout.folders) { folders in
            guard let id = folderID else { return }
            guard let folder = folders.first(where: { $0.id == id }) else { folderID = nil; return }
            folderPage = min(folderPage, max(0, (folder.apps.count - 1) / 9))
        }
        .onAppear {
            #if DEBUG
            // Screenshot fixtures are explicitly gated and compiled out of distribution builds.
            if UserDefaults.standard.bool(forKey: "LCOSPreviewEnabled") {
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("preview-config.plist")
                if let data = try? Data(contentsOf: url),
                   let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let json = values["LCOSHomeLayout"] as? String { layoutJSON = json }
                if let id = UserDefaults.standard.string(forKey: "LCOSPreviewFolder"),
                   let folder = layout.folders.first(where: { $0.id == id }) { folderID = id; folderName = folder.name }
            }
            #endif
        }
        .onDisappear { clearHover(); edgeTask?.cancel(); draggedID = nil }
    }

    private var header: some View {
        LCGlassGroup {
            HStack(spacing: 12) {
                Text("lc.appList.myApps".loc).font(.title2.weight(.bold))
                Spacer()
                if editing {
                    Button("lcos.home.done".loc) { animate { editing = false; draggedID = nil }; clearHover() }
                        .font(.body.weight(.semibold)).padding(.horizontal, 16).frame(height: 44)
                        .lcGlass(in: Capsule(), interactive: true)
                } else {
                    if shared.multiLCStatus != 2 {
                        Menu {
                            Button("lc.appList.installFromIpa".loc, action: importIPA)
                            Button("lc.appList.installFromUrl".loc, action: importURL)
                        } label: { chromeIcon("plus") }.disabled(importing)
                        .accessibilityLabel("lc.appList.installFromIpa".loc)
                    }
                    Menu {
                        Toggle("lcos.home.enabled".loc, isOn: $gridEnabled)
                        Button("lcos.home.edit".loc) { startEditing() }
                        Button("lcos.home.list".loc) { gridEnabled = false }
                        Button("lc.appList.openLink".loc, action: openLink)
                        if let openSideStore { Button("SideStore", action: openSideStore) }
                        Button("lcos.home.reset".loc) { resetConfirmation = true }
                    } label: { chromeIcon("ellipsis") }.accessibilityLabel("lcos.home.options".loc)
                }
            }.buttonStyle(.plain)
        }.padding(.horizontal, 24).padding(.top, 12)
    }
    private func chromeIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
            .lcGlass(in: Circle(), interactive: true)
    }
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("lcos.home.search".loc, text: $query).textInputAutocapitalization(.never)
                .disableAutocorrection(true).focused($searchFocused)
            Button { query = ""; searching = false; searchFocused = false } label: {
                Image(systemName: "xmark.circle.fill").frame(width: 36, height: 36)
            }.accessibilityLabel("lc.common.cancel".loc)
        }.padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 4)
            .lcGlass(in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 20)
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.grid.2x2").font(.system(size: 40, weight: .light))
            Text("lcos.home.emptyTitle".loc).font(.title2.weight(.semibold))
            Text("lcos.home.emptyBody".loc).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if shared.multiLCStatus != 2 { Button("lc.appList.installFromIpa".loc, action: importIPA).buttonStyle(.borderedProminent) }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startEditing() {
        animate { editing = true }
        if !reduceMotion { withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) { jiggle = true } }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    private func clearHover() { hoverTask?.cancel(); hoveredID = nil; folderCandidate = nil }
    private func hover(source: String, target: String, center: Bool, container: String?) {
        guard source != target else { return }
        if center, container == nil, available.contains(source) {
            if hoveredID != target {
                clearHover(); hoveredID = target
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    guard !Task.isCancelled, draggedID == source, hoveredID == target else { return }
                    animate { folderCandidate = target }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        } else {
            clearHover()
            var value = layout
            value.moveItem(source, before: target, in: container, available: available)
            if value != layout { animate { save(value) } }
        }
    }
    private func completeDrop(target: String, container: String?) {
        guard let source = draggedID else { return }
        var value = layout
        if folderCandidate == target, container == nil {
            _ = value.combine(source, with: target, name: "lcos.home.folder".loc, available: available)
        } else { value.moveItem(source, before: target, in: container, available: available) }
        animate { save(value) }; draggedID = nil; clearHover(); edgeTask?.cancel()
    }

    private func tile(_ id: String, side: CGFloat, container: String?) -> some View {
        LCHomeDragSource(id: id, content: tileArtwork(id, side: side), begin: {
            startEditing(); draggedID = id; clearHover()
        }, end: {
            if draggedID == id { draggedID = nil }; clearHover(); edgeTask?.cancel()
        })
            .frame(height: side + 30)
            .rotationEffect(.degrees(editing && !reduceMotion ? (jiggle ? 1.3 : -1.3) : 0))
            .scaleEffect(folderCandidate == id ? 1.13 : 1)
            .opacity(draggedID == id ? 0.28 : 1)
            .contentShape(Rectangle())
            .onDrop(of: [Self.dragType], delegate: LCHomeDrop(
                dragged: draggedID, target: id, iconSide: side,
                hover: { source, center in hover(source: source, target: id, center: center, container: container) },
                exit: { if hoveredID == id { clearHover() } },
                finish: { completeDrop(target: id, container: container) }))
            .overlay(alignment: .topLeading) {
                if editing, container != nil {
                    Button {
                        var value = layout; value.moveItem(id, before: nil, available: available)
                        animate { save(value) }
                    } label: {
                        Image(systemName: "minus").font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26)
                            .lcGlass(in: Circle(), interactive: true)
                    }.buttonStyle(.plain).offset(x: -2, y: -8).accessibilityLabel("lcos.home.moveOut".loc)
                }
            }
            .accessibilityAction(named: Text("lcos.home.edit".loc)) { startEditing() }
            .accessibilityAction(named: Text("lcos.home.moveOut".loc)) {
                guard container != nil else { return }
                var value = layout; value.moveItem(id, before: nil, available: available); save(value)
            }
    }
    @ViewBuilder private func tileArtwork(_ id: String, side: CGFloat) -> some View {
        if let folder = layout.folders.first(where: { $0.id == id }) {
            Button {
                folderName = folder.name; folderPage = 0
                animate { folderID = id }
            } label: {
                VStack(spacing: 6) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                        ForEach(Array(folder.apps.prefix(9)), id: \.self) { member in
                            if let app = model(member) {
                                Image(uiImage: app.appInfo.iconIsDarkIcon(scheme == .dark) ?? UIImage()).resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }.padding(7).frame(width: side, height: side, alignment: .top)
                        .lcGlass(in: RoundedRectangle(cornerRadius: side * 0.235))
                        .matchedGeometryEffect(id: id, in: folderAnimation, isSource: folderID != id)
                    Text(folder.name).font(.caption2).lineLimit(1).foregroundStyle(.primary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }.buttonStyle(.plain)
        } else if let app = model(id) {
            LCAppBanner(appModel: app, delegate: delegate, homeScreen: true, iconSide: side, homeEditing: editing)
        }
    }

    private func folderOverlay(_ folder: LCHomeLayout.Folder, width: CGFloat, side: CGFloat) -> some View {
        let count = max(1, (folder.apps.count + 8) / 9)
        return ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea().onTapGesture { closeFolder() }
                .onDrop(of: [Self.dragType], isTargeted: nil) { _ in
                    guard let id = draggedID, folder.apps.contains(id) else { return false }
                    var value = layout; value.moveItem(id, before: nil, available: available)
                    animate { save(value); folderID = nil }; draggedID = nil; return true
                }
            VStack(spacing: 24) {
                HStack {
                    TextField("lcos.home.folder".loc, text: $folderName).font(.largeTitle.weight(.semibold))
                        .multilineTextAlignment(.center).submitLabel(.done).onSubmit { rename(folder.id) }
                    Button { closeFolder() } label: { chromeIcon("xmark") }.accessibilityLabel("lcos.home.done".loc)
                }.padding(.horizontal, 24)
                TabView(selection: $folderPage) {
                    ForEach(0..<count, id: \.self) { index in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 22) {
                            ForEach(Array(folder.apps.dropFirst(index * 9).prefix(9)), id: \.self) { id in
                                tile(id, side: side, container: folder.id)
                                    .contextMenu {
                                        Button("lcos.home.moveOut".loc) {
                                            var value = layout; value.moveItem(id, before: nil, available: available)
                                            animate { save(value) }
                                        }
                                    }
                            }
                        }.padding(24).frame(maxHeight: .infinity, alignment: .top).tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 3 * (side + 52) + 20)
                .lcGlass(in: RoundedRectangle(cornerRadius: 38))
                .matchedGeometryEffect(id: folder.id, in: folderAnimation, isSource: true)
                .padding(.horizontal, 24)
                if count > 1 { pageDots(count, selection: $folderPage) }
                if editing {
                    Text("lcos.home.folderDragHint".loc).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                }
            }.frame(maxWidth: min(width, 440))
        }.gesture(MagnificationGesture().onEnded { if $0 < 0.85 { closeFolder() } })
    }
    private func rename(_ id: String) { var value = layout; value.renameFolder(id, name: folderName); save(value) }
    private func closeFolder() { if let id = folderID { rename(id) }; animate { folderID = nil }; clearHover() }
    private func pageDots(_ count: Int, selection: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Button { animate { selection.wrappedValue = index } } label: {
                    Circle().fill(Color.primary.opacity(selection.wrappedValue == index ? 0.8 : 0.22)).frame(width: 6, height: 6).padding(8)
                }.accessibilityLabel("lcos.home.page".localizeWithFormat(index + 1))
            }
        }.buttonStyle(.plain)
    }
    private func pageEdge(_ direction: Int, count: Int) -> some View {
        Color.clear.frame(width: 24).contentShape(Rectangle())
            .allowsHitTesting(draggedID != nil)
            .onDrop(of: [Self.dragType], delegate: LCHomeEdgeDrop(enter: {
                edgeTask?.cancel()
                edgeTask = Task { @MainActor in
                    while !Task.isCancelled, draggedID != nil {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        guard !Task.isCancelled else { return }
                        animate { page = min(max(page + direction, 0), count - 1) }
                    }
                }
            }, exit: { edgeTask?.cancel() }, finish: {
                guard let id = draggedID else { return }
                let roots = layout.rootItems(available)
                var value = layout; value.moveItem(id, before: direction < 0 ? roots.first : nil, available: available)
                animate { save(value) }; draggedID = nil; edgeTask?.cancel()
            }))
    }
}

private struct LCHomeDrop: DropDelegate {
    let dragged: String?
    let target: String
    let iconSide: CGFloat
    let hover: (String, Bool) -> Void
    let exit: () -> Void
    let finish: () -> Void
    func validateDrop(info: DropInfo) -> Bool { dragged != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let dragged, dragged != target {
            hover(dragged, info.location.y > 8 && info.location.y < iconSide - 8 && info.location.x > 20 && info.location.x < iconSide - 4)
        }
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { exit() }
    func performDrop(info: DropInfo) -> Bool { guard dragged != nil else { return false }; finish(); return true }
}
private struct LCHomeEdgeDrop: DropDelegate {
    let enter: () -> Void
    let exit: () -> Void
    let finish: () -> Void
    func dropEntered(info: DropInfo) { enter() }
    func dropExited(info: DropInfo) { exit() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { finish(); return true }
}
