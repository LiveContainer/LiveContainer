import SwiftUI

/// Visual presentation only. Launch/authentication/context menus stay in the upstream controller.
struct LCHomeIconArtwork: View {
    @ObservedObject var model: LCAppModel
    let darkIcon: Bool
    let side: CGFloat
    let showLabel: Bool
    let launch: () -> Void

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
