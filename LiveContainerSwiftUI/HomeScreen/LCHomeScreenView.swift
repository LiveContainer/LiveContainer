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
    @State private var draggedID: String?
    @State private var dragOrigin: LCHomeLayout?
    @State private var folderID: String?
    @State private var folderName = ""
    @State private var folderPage = 0
    @State private var folderProgress: CGFloat = 0
    @State private var folderTargetOpen = true
    @State private var folderAnimating = false
    @State private var folderFrames: [String: CGRect] = [:]
    @State private var folderCloseTask: Task<Void, Never>?
    @State private var folderExitTask: Task<Void, Never>?
    #if DEBUG
    @State private var previewMotionTask: Task<Void, Never>?
    #endif
    @GestureState private var folderPinch: CGFloat = 1
    @State private var hoveredID: String?
    @State private var folderCandidate: String?
    @State private var reorderTarget: String?
    @State private var hoverTask: Task<Void, Never>?
    @State private var edgeTask: Task<Void, Never>?
    @State private var resetConfirmation = false
    @FocusState private var searchFocused: Bool
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
    private func animateFolder(_ action: () -> Void) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86), action)
    }

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
                                desktopPage(Array(ids.dropFirst(index * perPage).prefix(perPage)),
                                            index: index, columns: columns, side: side, perPage: perPage).tag(index)
                            }
                        }.tabViewStyle(.page(indexDisplayMode: .never))
                        .overlay(alignment: .leading) { pageEdge(-1, count: count, perPage: perPage) }
                        .overlay(alignment: .trailing) { pageEdge(1, count: count, perPage: perPage) }
                    }
                    if count > 1 { pageDots(count, selection: $page) }
                    if !searching {
                        Button { searching = true; searchFocused = true } label: {
                            Label("lcos.home.search".loc, systemImage: "magnifyingglass").font(.caption.weight(.medium))
                                .padding(.horizontal, 16).padding(.vertical, 10).lcGlass(in: Capsule(), interactive: true)
                        }.buttonStyle(.plain).padding(.bottom, 12)
                    }
                }.frame(maxWidth: 900).frame(maxWidth: .infinity)
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.045 * folderProgress)
                    .blur(radius: reduceMotion ? 0 : 8 * folderProgress)
                    .allowsHitTesting(folderID == nil)
                    .accessibilityHidden(folderID != nil)
                if let id = folderID, let folder = layout.folders.first(where: { $0.id == id }) {
                    folderOverlay(folder, frame: geometry.frame(in: .global), side: side).zIndex(2)
                }
            }
            .onPreferenceChange(LCHomeFolderFrames.self) { if folderID == nil { folderFrames = $0 } }
            .onChange(of: count) { page = min(page, $0 - 1) }
            .onChange(of: query) { _ in page = 0 }
        }
        .confirmationDialog("lcos.home.reset".loc, isPresented: $resetConfirmation) {
            Button("lcos.home.reset".loc, role: .destructive) { save(LCHomeLayout()); page = 0; folderID = nil; folderProgress = 0 }
        }
        .onChange(of: layout.folders) { folders in
            guard let id = folderID else { return }
            guard let folder = folders.first(where: { $0.id == id }) else {
                folderCloseTask?.cancel(); animateFolder { folderID = nil; folderProgress = 0 }; return
            }
            folderPage = min(folderPage, max(0, (folder.apps.count - 1) / 9))
        }
        .onAppear {
            #if DEBUG
            // Screenshot fixtures are explicitly gated and compiled out of distribution builds.
            if UserDefaults.standard.bool(forKey: "LCOSPreviewEnabled") {
                if UserDefaults.standard.bool(forKey: "LCOSPreviewEditing") { startEditing() }
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("preview-config.plist")
                if let data = try? Data(contentsOf: url),
                   let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let json = values["LCOSHomeLayout"] as? String { layoutJSON = json }
                page = max(0, UserDefaults.standard.integer(forKey: "LCOSPreviewPage"))
                if let id = UserDefaults.standard.string(forKey: "LCOSPreviewFolder"),
                   let folder = layout.folders.first(where: { $0.id == id }) { folderID = id; folderName = folder.name }
                if UserDefaults.standard.bool(forKey: "LCOSPreviewMotion"), let folder = layout.folders.first {
                    startEditing()
                    previewMotionTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        guard !Task.isCancelled else { return }
                        openFolder(folder)
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard !Task.isCancelled else { return }
                        closeFolder()
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard !Task.isCancelled else { return }
                        reverseFolder()
                        try? await Task.sleep(nanoseconds: 1_760_000_000)
                        guard !Task.isCancelled else { return }
                        closeFolder()
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        guard !Task.isCancelled else { return }
                        openFolder(folder)
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        guard !Task.isCancelled else { return }
                        closeFolder()
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.32)) { page = 1 }
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.32)) { page = 0 }
                    }
                }
            }
            #endif
        }
        .onDisappear {
            cancelDrag(); folderCloseTask?.cancel()
            #if DEBUG
            previewMotionTask?.cancel()
            #endif
        }
    }

    private var header: some View {
        LCGlassGroup {
            HStack(spacing: 12) {
                Text("lc.appList.myApps".loc).font(.title2.weight(.bold))
                Spacer()
                if editing {
                    Button("lcos.home.done".loc) { finishEditing() }
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

    private func finishEditing() {
        cancelDrag()
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { editing = false }
        clearHover(); edgeTask?.cancel()
    }
    private func startEditing() {
        guard !editing else { return }
        animate { editing = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    private func clearHover() { hoverTask?.cancel(); hoveredID = nil; folderCandidate = nil }
    private func cancelDrag() {
        if draggedID != nil, let origin = dragOrigin { animate { save(origin.reconciled(available)) } }
        draggedID = nil; dragOrigin = nil
        reorderTarget = nil
        clearHover(); edgeTask?.cancel(); folderExitTask?.cancel()
    }
    private func commitDrag() {
        draggedID = nil; dragOrigin = nil
        reorderTarget = nil
        clearHover(); edgeTask?.cancel(); folderExitTask?.cancel()
    }
    private func blankArea(drop: @escaping () -> Void) -> some View {
        Color.clear.contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.45) { startEditing() }
            .onTapGesture { if editing { finishEditing() } }
            .onDrop(of: [Self.dragType], delegate: LCHomeEdgeDrop(enter: {}, exit: {}, finish: drop))
    }
    private func desktopPage(_ ids: [String], index: Int, columns: Int, side: CGFloat, perPage: Int) -> some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columns), spacing: 18) {
                        ForEach(ids, id: \.self) { id in tile(id, side: side, container: nil) }
                    }.padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 12)
                    blankArea { dropAtPageEnd(index, perPage: perPage, folder: nil) }
                        .frame(minHeight: 28, maxHeight: .infinity)
                }.frame(minHeight: proxy.size.height, alignment: .top)
            }.lcSoftScrollEdges().lcHomeScrollVeil()
        }
    }
    private func dropAtPageEnd(_ index: Int, perPage: Int, folder: String?) {
        guard let source = draggedID else { return }
        let items = folder.flatMap { id in layout.folders.first { $0.id == id }?.apps } ?? layout.rootItems(available)
        let destination = items.dropFirst((index + 1) * perPage).first
        var value = layout
        value.moveItem(source, before: destination, in: folder, available: available)
        animate { save(value) }; commitDrag()
    }
    private func hover(source: String, target: String, center: Bool, container: String?) {
        guard source != target else { return }
        if center, container == nil, available.contains(source) {
            if hoveredID != target {
                clearHover(); hoveredID = target
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    guard !Task.isCancelled, draggedID == source, hoveredID == target else { return }
                    animate { folderCandidate = target }
                    if let folder = layout.folders.first(where: { $0.id == target }) { openFolder(folder) }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        } else {
            clearHover()
            guard reorderTarget != target else { return }
            reorderTarget = target
            var value = layout
            value.moveItem(source, toSlotOf: target, in: container, available: available)
            if value != layout { animate { save(value) } }
        }
    }
    private func completeDrop(target: String, container: String?) {
        guard let source = draggedID else { return }
        var value = layout
        if folderCandidate == target, container == nil {
            _ = value.combine(source, with: target, name: "lcos.home.folder".loc, available: available)
        } else if reorderTarget != target { value.moveItem(source, toSlotOf: target, in: container, available: available) }
        animate { save(value) }; commitDrag()
    }

    private func tile(_ id: String, side: CGFloat, container: String?) -> some View {
        LCHomeDragSource(id: id, iconSide: side, content: tileArtwork(id, side: side), begin: {
            startEditing(); dragOrigin = layout; draggedID = id; reorderTarget = nil; clearHover()
        }, end: {
            if draggedID == id { cancelDrag() }
        })
            .frame(height: side + 30)
            .modifier(LCHomeJiggle(active: editing && !reduceMotion && draggedID != id, id: id))
            .scaleEffect(folderCandidate == id ? 1.13 : 1)
            .opacity(draggedID == id ? 0.28 : 1)
            .contentShape(Rectangle())
            .background {
                if id.hasPrefix("folder:") {
                    GeometryReader { proxy in
                        Color.clear.preference(key: LCHomeFolderFrames.self,
                            value: [id: CGRect(x: proxy.frame(in: .global).midX - side / 2,
                                               y: proxy.frame(in: .global).minY, width: side, height: side)])
                    }
                }
            }
            .onDrop(of: [Self.dragType], delegate: LCHomeDrop(
                dragged: draggedID, target: id, iconSide: side,
                hover: { source, center in hover(source: source, target: id, center: center, container: container) },
                exit: {
                    if hoveredID == id { clearHover() }
                    if reorderTarget == id { reorderTarget = nil }
                },
                finish: { completeDrop(target: id, container: container) }))
            .accessibilityAction(named: Text("lcos.home.edit".loc)) { startEditing() }
            .accessibilityAction(named: Text("lcos.home.moveOut".loc)) {
                guard container != nil else { return }
                var value = layout; value.moveItem(id, before: nil, available: available); save(value)
            }
    }
    @ViewBuilder private func tileArtwork(_ id: String, side: CGFloat) -> some View {
        if let folder = layout.folders.first(where: { $0.id == id }) {
            Button {
                openFolder(folder)
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
                    Text(folder.name).font(.caption2).lineLimit(1).foregroundStyle(.primary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }.buttonStyle(.plain)
        } else if let app = model(id) {
            LCAppBanner(appModel: app, delegate: delegate, homeScreen: true, iconSide: side, homeEditing: editing)
        }
    }

    private func folderOverlay(_ folder: LCHomeLayout.Folder, frame: CGRect, side: CGFloat) -> some View {
        let size = frame.size
        let count = max(1, (folder.apps.count + 8) / 9)
        let panelWidth = min(size.width, 440) - 48
        let panelHeight = 3 * (side + 30) + 2 * 22 + 48
        let origin = folderFrames[folder.id]?.offsetBy(dx: -frame.minX, dy: -frame.minY)
            ?? CGRect(x: size.width / 2 - side / 2, y: size.height / 2 - side / 2, width: side, height: side)
        let progress = reduceMotion ? 1 : folderProgress
        return ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
                .opacity(folderProgress).onTapGesture { reverseFolder() }
                .accessibilityLabel("lcos.home.done".loc).accessibilityAddTraits(.isButton)
                .onDrop(of: [Self.dragType], delegate: LCHomeEdgeDrop(enter: {
                    folderExitTask?.cancel()
                    folderExitTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 550_000_000)
                        guard !Task.isCancelled, let id = draggedID, folder.apps.contains(id) else { return }
                        closeFolder()
                    }
                }, exit: { folderExitTask?.cancel() }, finish: {
                    folderExitTask?.cancel()
                    guard let id = draggedID, folder.apps.contains(id) else { return }
                    var value = layout; value.moveItem(id, before: nil, available: available)
                    animate { save(value) }; closeFolder(); commitDrag()
                }))
            TextField("lcos.home.folder".loc, text: $folderName).font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center).submitLabel(.done).onSubmit { rename(folder.id) }
                .frame(width: panelWidth).position(x: size.width / 2, y: size.height / 2 - panelHeight / 2 - 46)
                .opacity(folderProgress)
            if editing {
                Button("lcos.home.done".loc) { finishEditing() }
                    .font(.body.weight(.semibold)).padding(.horizontal, 16).frame(height: 44)
                    .lcGlass(in: Capsule(), interactive: true)
                    .position(x: size.width - 68, y: 28).opacity(folderProgress)
            }
                TabView(selection: $folderPage) {
                    ForEach(0..<count, id: \.self) { index in
                        VStack(spacing: 0) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 22) {
                            ForEach(Array(folder.apps.dropFirst(index * 9).prefix(9)), id: \.self) { id in
                                tile(id, side: side, container: folder.id)
                                    .contextMenu {
                                        if !editing {
                                        Button("lcos.home.moveOut".loc) {
                                            var value = layout; value.moveItem(id, before: nil, available: available)
                                            animate { save(value) }
                                        }
                                        }
                                    }
                            }
                        }.padding(.horizontal, 24).padding(.top, 24)
                        blankArea { dropAtPageEnd(index, perPage: 9, folder: folder.id) }
                            .frame(minHeight: 24, maxHeight: .infinity)
                        }.frame(maxHeight: .infinity, alignment: .top).tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                .overlay(alignment: .leading) { pageEdge(-1, count: count, perPage: 9, folder: folder.id) }
                .overlay(alignment: .trailing) { pageEdge(1, count: count, perPage: 9, folder: folder.id) }
                .frame(width: panelWidth, height: panelHeight)
                .lcGlass(in: RoundedRectangle(cornerRadius: 38))
                .onDrop(of: [Self.dragType], delegate: LCHomeEdgeDrop(enter: {}, exit: {}, finish: {
                    dropAtPageEnd(folderPage, perPage: 9, folder: folder.id)
                }))
                .scaleEffect(x: (side / panelWidth + (1 - side / panelWidth) * progress) * folderPinch,
                             y: (side / panelHeight + (1 - side / panelHeight) * progress) * folderPinch)
                .position(x: size.width / 2 + (origin.midX - size.width / 2) * (1 - progress),
                          y: size.height / 2 + (origin.midY - size.height / 2) * (1 - progress))
                .opacity(folderProgress)
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.86), value: folderPinch)
                if count > 1 {
                    pageDots(count, selection: $folderPage)
                        .position(x: size.width / 2, y: size.height / 2 + panelHeight / 2 + 32).opacity(folderProgress)
                }
                if editing {
                    Text("lcos.home.folderDragHint".loc).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(width: panelWidth).position(x: size.width / 2, y: size.height / 2 + panelHeight / 2 + 70).opacity(folderProgress)
                }
            if folderAnimating {
                Color.clear.contentShape(Rectangle()).onTapGesture { reverseFolder() }
                    .allowsHitTesting(draggedID == nil).zIndex(20)
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear { transitionFolder(open: true) }
        .accessibilityAction(.escape) { closeFolder() }
        .simultaneousGesture(MagnificationGesture()
            .updating($folderPinch) { value, state, _ in state = reduceMotion ? 1 : min(1, max(0.7, value)) }
            .onEnded { if $0 < 0.85 { closeFolder() } })
    }
    private func rename(_ id: String) { var value = layout; value.renameFolder(id, name: folderName); save(value) }
    private func openFolder(_ folder: LCHomeLayout.Folder) {
        folderCloseTask?.cancel()
        folderName = folder.name; folderPage = 0; folderProgress = 0
        folderTargetOpen = true; folderAnimating = true
        folderID = folder.id
    }
    private func closeFolder() {
        guard let id = folderID else { return }
        rename(id); clearHover(); folderExitTask?.cancel(); folderCloseTask?.cancel()
        transitionFolder(open: false)
    }
    private func reverseFolder() {
        if folderTargetOpen { closeFolder() } else { transitionFolder(open: true) }
    }
    private func transitionFolder(open: Bool) {
        guard let id = folderID else { return }
        folderCloseTask?.cancel()
        folderTargetOpen = open; folderAnimating = true
        animateFolder { folderProgress = open ? 1 : 0 }
        folderCloseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 150_000_000 : 420_000_000)
            guard !Task.isCancelled, folderID == id else { return }
            folderAnimating = false
            if !open { folderID = nil }
        }
    }
    private func pageDots(_ count: Int, selection: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) { selection.wrappedValue = index } } label: {
                    Circle().fill(Color.primary.opacity(selection.wrappedValue == index ? 0.8 : 0.22)).frame(width: 6, height: 6).padding(8)
                }.accessibilityLabel("lcos.home.page".localizeWithFormat(index + 1))
            }
        }.buttonStyle(.plain)
    }
    private func pageEdge(_ direction: Int, count: Int, perPage: Int, folder: String? = nil) -> some View {
        Color.clear.frame(width: 24).contentShape(Rectangle())
            .allowsHitTesting(draggedID != nil)
            .onDrop(of: [Self.dragType], delegate: LCHomeEdgeDrop(enter: {
                edgeTask?.cancel()
                edgeTask = Task { @MainActor in
                    while !Task.isCancelled, draggedID != nil {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        guard !Task.isCancelled else { return }
                        let current = folder == nil ? page : folderPage
                        let next = min(max(current + direction, 0), count - 1)
                        guard next != current else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) {
                            if folder == nil { page = next } else { folderPage = next }
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
            }, exit: { edgeTask?.cancel() }, finish: {
                dropAtPageEnd(folder == nil ? page : folderPage, perPage: perPage, folder: folder)
            }))
    }
}

private struct LCHomeFolderFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
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
