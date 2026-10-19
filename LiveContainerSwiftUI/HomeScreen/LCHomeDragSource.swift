import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// UIKit owns the lift/drop/cancellation lifecycle, so a cancelled drag cannot leave a dimmed icon.
struct LCHomeDragSource<Content: View>: UIViewControllerRepresentable {
    let id: String
    let iconSide: CGFloat
    let content: Content
    let begin: () -> Void
    let end: () -> Void
    func makeUIViewController(context: Context) -> LCHomeDragController {
        LCHomeDragController(id: id, iconSide: iconSide, content: AnyView(content), begin: begin, end: end)
    }
    func updateUIViewController(_ controller: LCHomeDragController, context: Context) {
        controller.host.rootView = AnyView(content)
        controller.id = id; controller.iconSide = iconSide; controller.begin = begin; controller.end = end
    }
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: LCHomeDragController, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}
final class LCHomeDragController: UIViewController, UIDragInteractionDelegate {
    let host: UIHostingController<AnyView>
    var id: String
    var iconSide: CGFloat
    var begin: () -> Void
    var end: () -> Void
    // Paging or closing a folder can remove the source view before UIKit ends the drag.
    // Keep its delegate alive for that session so the same lifted icon can enter another folder.
    private var activeSessionOwner: LCHomeDragController?
    private weak var dragWindow: UIWindow?
    private var liftLocation = CGPoint.zero
    private var activated = false
    init(id: String, iconSide: CGFloat, content: AnyView, begin: @escaping () -> Void, end: @escaping () -> Void) {
        self.id = id; self.iconSide = iconSide; self.begin = begin; self.end = end
        host = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    #if DEBUG
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard UserDefaults.standard.bool(forKey: "LCOSPreviewEnabled"),
              UserDefaults.standard.bool(forKey: "LCOSPreviewDust"),
              id.hasPrefix("org.example.homepreview.10:") else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.view.window != nil, let snapshot = LCHomeDustAnimator.capture(self.view) else { return }
            await LCHomeDustAnimator.dissolve(snapshot, hiding: self.view)
            self.view.alpha = 1 // Fixture only: no real app or data is removed.
        }
    }
    #endif
    override func loadView() {
        view = UIView(); view.backgroundColor = .clear
        addChild(host); host.view.backgroundColor = .clear; host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        host.didMove(toParent: self)
        let interaction = UIDragInteraction(delegate: self); interaction.isEnabled = true; view.addInteraction(interaction)
    }
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        activeSessionOwner = self
        dragWindow = view.window
        liftLocation = session.location(in: view)
        if let window = dragWindow { liftLocation = view.convert(liftLocation, to: window) }
        activated = false
        let provider = NSItemProvider()
        let data = Data(id.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: "org.livecontainer.desktop-app", visibility: .ownProcess) { completion in
            completion(data, nil); return nil
        }
        let item = UIDragItem(itemProvider: provider); item.localObject = id; return [item]
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionDidEnd session: UIDragSession) {
        defer { activeSessionOwner = nil }
        if activated { end() }
        activated = false
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionDidMove session: UIDragSession) {
        guard !activated, let window = dragWindow else { return }
        let point = session.location(in: window)
        let dx = point.x - liftLocation.x, dy = point.y - liftLocation.y
        guard dx * dx + dy * dy > 64 else { return }
        activated = true
        begin()
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: UIDragSession) -> Bool { true }
    func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }
    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
        iconPreview()
    }
    func dragInteraction(_ interaction: UIDragInteraction, previewForCancelling item: UIDragItem, withDefault defaultPreview: UITargetedDragPreview) -> UITargetedDragPreview? {
        // The old folder/page may no longer be in a window. UIKit's fallback remains valid.
        host.view.window == nil ? defaultPreview : iconPreview()
    }
    private func iconPreview() -> UITargetedDragPreview {
        let parameters = UIDragPreviewParameters(); parameters.backgroundColor = .clear
        let icon = CGRect(x: (host.view.bounds.width - iconSide) / 2, y: 0, width: iconSide, height: iconSide)
        parameters.visiblePath = UIBezierPath(roundedRect: icon, cornerRadius: iconSide * 0.235)
        return UITargetedDragPreview(view: host.view, parameters: parameters)
    }
}
