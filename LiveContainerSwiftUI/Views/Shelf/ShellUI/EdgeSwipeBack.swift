import SwiftUI

#if canImport(UIKit)
import UIKit

/// The system's left-edge swipe for the screens that slide in over the library (game settings, Controllers). Those are
/// overlays, not a navigation stack, so UIKit's own back swipe does not exist for them. This is the same recognizer
/// UIKit uses for it, a `UIScreenEdgePanGestureRecognizer` on the left edge, so it starts only at the screen edge and
/// never competes with a slider or a carousel on the page. It reports the finger's travel while it drags and where it
/// lets go.
struct EdgeSwipeBack: UIViewRepresentable {
    var enabled: Bool
    var changed: (CGFloat) -> Void
    /// The travel to the right and the horizontal velocity when the finger lifts.
    var ended: (CGFloat, CGFloat) -> Void
    var cancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.recognizer.isEnabled = enabled
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.recognizer.view?.removeGestureRecognizer(coordinator.recognizer)
    }

    /// Hangs the recognizer on the window, so the edge touch reaches it wherever the page is drawn.
    final class AnchorView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let coordinator else { return }
            coordinator.recognizer.view?.removeGestureRecognizer(coordinator.recognizer)
            window?.addGestureRecognizer(coordinator.recognizer)
        }
    }

    @MainActor final class Coordinator: NSObject {
        var parent: EdgeSwipeBack
        let recognizer: UIScreenEdgePanGestureRecognizer

        init(_ parent: EdgeSwipeBack) {
            self.parent = parent
            recognizer = UIScreenEdgePanGestureRecognizer()
            recognizer.edges = .left
            super.init()
            recognizer.addTarget(self, action: #selector(pan(_:)))
            recognizer.isEnabled = parent.enabled
        }

        @objc private func pan(_ gesture: UIScreenEdgePanGestureRecognizer) {
            let travel = max(0, gesture.translation(in: gesture.view).x)
            switch gesture.state {
            case .began, .changed: parent.changed(travel)
            case .ended: parent.ended(travel, gesture.velocity(in: gesture.view).x)
            case .cancelled, .failed: parent.cancelled()
            default: break
            }
        }
    }
}
#else
/// There is no edge swipe off UIKit.
struct EdgeSwipeBack: View {
    var enabled: Bool
    var changed: (CGFloat) -> Void
    var ended: (CGFloat, CGFloat) -> Void
    var cancelled: () -> Void
    var body: some View { Color.clear.frame(width: 0, height: 0) }
}
#endif
