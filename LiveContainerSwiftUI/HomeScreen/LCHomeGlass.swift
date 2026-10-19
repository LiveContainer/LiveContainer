import SwiftUI

extension View {
    func lcHomeScrollVeil() -> some View {
        Group {
            if #available(iOS 16.4, *) {
                self.scrollBounceBehavior(.basedOnSize, axes: .vertical)
            } else { self }
        }.overlay(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial).frame(height: 32)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false).accessibilityHidden(true)
        }.overlay(alignment: .bottom) {
            Rectangle().fill(.ultraThinMaterial).frame(height: 22)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
    @ViewBuilder func lcSoftScrollEdges() -> some View {
        if #available(iOS 26.0, *) { self.scrollEdgeEffectStyle(.soft, for: .all) }
        else { self }
    }
    @ViewBuilder func lcGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

struct LCHomeJiggle: ViewModifier {
    let active: Bool
    let id: String
    @State private var rocking = false
    private var seed: Int { id.utf8.reduce(0) { ($0 + Int($1)) % 7 } }
    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(active ? (rocking ? 1 : -1) * (seed % 2 == 0 ? 1.2 : -1.4) : 0))
            .offset(y: active && rocking ? 0.35 : 0)
            .animation(active ? .easeInOut(duration: 0.13 + Double(seed) * 0.008)
                .delay(Double(seed) * 0.015).repeatForever(autoreverses: true) : .easeOut(duration: 0.15), value: rocking)
            .onAppear { rocking = active }
            .onChange(of: active) { rocking = $0 }
    }
}
struct LCGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 16, content: content) }
        else { content() }
    }
}
