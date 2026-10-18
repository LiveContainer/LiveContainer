import SwiftUI

extension View {
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
struct LCGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 16, content: content) }
        else { content() }
    }
}
