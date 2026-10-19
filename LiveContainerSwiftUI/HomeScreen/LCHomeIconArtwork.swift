import SwiftUI
import UIKit

/// Visual presentation only. Launch/authentication/context menus stay in the upstream controller.
struct LCHomeIconArtwork: View {
    @ObservedObject var model: LCAppModel
    let darkIcon: Bool
    let side: CGFloat
    let showLabel: Bool
    let launch: () -> Void
    var remove: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: launch) {
            VStack(spacing: 6) {
                ZStack {
                    Image(uiImage: model.appInfo.iconIsDarkIcon(darkIcon) ?? UIImage())
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.235, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 3)
                    if model.isSigningInProgress {
                        RoundedRectangle(cornerRadius: side * 0.235).fill(.black.opacity(0.48))
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: side, height: side)
                .overlay(alignment: .topTrailing) {
                    if model.uiIsLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(5).background(.regularMaterial, in: Circle())
                            .offset(x: 4, y: -3)
                    }
                }
                if showLabel {
                    Text(model.displayName)
                        .font(.caption2).lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(LCHomeIconPressStyle())
        .disabled(model.isSigningInProgress)
        .accessibilityLabel(model.displayName)
        .accessibilityValue(model.isSigningInProgress ? "Signing" : model.uiIsLocked ? "Locked" : "")
        .accessibilityHint("lcos.home.iconHint".loc)
        .overlay(alignment: .top) {
            HStack {
            if let remove {
                HStack {
                    Button(action: remove) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.primary).frame(width: 24, height: 24)
                            .background(.regularMaterial, in: Circle())
                            .frame(width: 36, height: 36).contentShape(Circle())
                    }.buttonStyle(.plain)
                        .disabled(model.isSigningInProgress)
                        .accessibilityLabel("lc.appBanner.uninstall".loc + " " + model.displayName)
                    Spacer(minLength: 0)
                }.frame(width: side + 12).offset(x: -6, y: -12)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.65, anchor: .topLeading)))
            }
            }.animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.85), value: remove != nil)
        }
    }
}

/// Shared by the actual uninstall path and the debug visual fixture. No files are changed here.
@MainActor
enum LCHomeDustAnimator {
    struct Snapshot {
        let image: CGImage
        let frame: CGRect
        let window: UIWindow
    }
    static func capture(_ view: UIView) -> Snapshot? {
        guard let window = view.window, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        guard let image = renderer.image(actions: { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) }).cgImage else { return nil }
        return Snapshot(image: image, frame: view.convert(view.bounds, to: window), window: window)
    }
    static func dissolve(_ snapshot: Snapshot, hiding source: UIView) async {
        let overlay = UIView(frame: snapshot.frame)
        overlay.isUserInteractionEnabled = false
        overlay.accessibilityElementsHidden = true
        snapshot.window.addSubview(overlay)
        source.alpha = 0
        defer { overlay.removeFromSuperview() }
        if UIAccessibility.isReduceMotionEnabled {
            let image = UIImageView(frame: overlay.bounds)
            image.image = UIImage(cgImage: snapshot.image)
            overlay.addSubview(image)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                UIView.animate(withDuration: 0.18, animations: { overlay.alpha = 0 }) { _ in continuation.resume() }
            }
            return
        }
        let columns = 14, rows = 16
        let width = overlay.bounds.width / CGFloat(columns), height = overlay.bounds.height / CGFloat(rows)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for row in 0..<rows {
            for column in 0..<columns {
                let particle = CALayer()
                particle.frame = CGRect(x: CGFloat(column) * width, y: CGFloat(row) * height, width: width + 0.25, height: height + 0.25)
                particle.contents = snapshot.image
                particle.contentsRect = CGRect(x: CGFloat(column) / CGFloat(columns), y: CGFloat(row) / CGFloat(rows),
                                               width: 1 / CGFloat(columns), height: 1 / CGFloat(rows))
                particle.contentsScale = snapshot.window.screen.scale
                overlay.layer.addSublayer(particle)
                let seed = (row * 31 + column * 17) % 29
                let drift = CGFloat(18 + seed * 2)
                let position = CABasicAnimation(keyPath: "position")
                position.fromValue = NSValue(cgPoint: particle.position)
                position.toValue = NSValue(cgPoint: CGPoint(x: particle.position.x + drift, y: particle.position.y - CGFloat(16 + seed * 3)))
                let opacity = CABasicAnimation(keyPath: "opacity"); opacity.fromValue = 1; opacity.toValue = 0
                let scale = CABasicAnimation(keyPath: "transform.scale"); scale.fromValue = 1; scale.toValue = 0.1
                let group = CAAnimationGroup(); group.animations = [position, opacity, scale]
                group.duration = 0.48 + Double(seed % 5) * 0.025
                group.beginTime = CACurrentMediaTime() + Double(column) * 0.008
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                group.fillMode = .both; group.isRemovedOnCompletion = false
                particle.add(group, forKey: "dust")
            }
        }
        CATransaction.commit()
        try? await Task.sleep(nanoseconds: 720_000_000)
    }
}

private struct LCHomeIconPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
