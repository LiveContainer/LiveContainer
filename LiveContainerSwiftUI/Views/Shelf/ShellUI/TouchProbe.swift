import SwiftUI
#if os(iOS)
import UIKit

/// Reports every finger that comes down anywhere in the window, and takes nothing: the gesture fails at once, so the
/// touch goes on to the views, scroll views and gestures under it as if the probe were not there.
struct TouchProbe: UIViewRepresentable {
    let touched: () -> Void

    final class Anchor: UIView {
        let probe = Probe()
        weak var host: UIWindow?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            host?.removeGestureRecognizer(probe)
            host = window
            host?.addGestureRecognizer(probe)
        }
        func detach() { host?.removeGestureRecognizer(probe); host = nil }
    }

    final class Probe: UIGestureRecognizer {
        var touched: () -> Void = {}
        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }
        convenience init() { self.init(target: nil, action: nil) }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            touched()
            state = .failed
        }
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        view.probe.touched = touched
        return view
    }
    func updateUIView(_ view: Anchor, context: Context) { view.probe.touched = touched }
    static func dismantleUIView(_ view: Anchor, coordinator: ()) { view.detach() }
}
#endif

extension View {
    /// Calls `touched` when a finger comes down anywhere in the window. Does nothing off iOS, where there is no touch.
    func onAnyTouch(_ touched: @escaping () -> Void) -> some View {
        #if os(iOS)
        background(TouchProbe(touched: touched).frame(width: 0, height: 0).accessibilityHidden(true))
        #else
        self
        #endif
    }
}
