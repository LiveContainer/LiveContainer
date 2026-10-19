import SwiftUI

extension View {
    func lcHomeScrollVeil() -> some View {
        modifier(LCHomeScrollVeil())
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

private struct LCHomeScrollVeil: ViewModifier {
    @State private var scrolled = false
    private var visible: Bool {
        if #available(iOS 18.0, *) { return scrolled }
        return true
    }
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 18.0, *) {
                content.scrollBounceBehavior(.always, axes: .vertical)
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top > 0.5
                    } action: { _, value in scrolled = value }
            } else if #available(iOS 16.4, *) {
                content.scrollBounceBehavior(.always, axes: .vertical)
            } else { content }
        }.overlay(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial).frame(height: 32)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                    .init(color: .black.opacity(0.4), location: 0.55), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .opacity(visible ? 1 : 0).animation(.easeOut(duration: 0.12), value: visible)
                .allowsHitTesting(false).accessibilityHidden(true)
        }.overlay(alignment: .bottom) {
            Rectangle().fill(.ultraThinMaterial).frame(height: 22)
                .mask(LinearGradient(colors: [.clear, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                .opacity(visible ? 1 : 0).animation(.easeOut(duration: 0.12), value: visible)
                .allowsHitTesting(false).accessibilityHidden(true)
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
