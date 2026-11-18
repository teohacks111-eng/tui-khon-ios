#if canImport(SwiftUI)
import SwiftUI

/// Native Liquid Glass on iOS 26, with a material fallback for iOS 18–25.
struct LiquidGlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
        }
    }
}

struct LiquidGlassButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action, label: { label })
                .buttonStyle(.glass)
        } else {
            Button(action: action, label: { label })
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}
#endif
