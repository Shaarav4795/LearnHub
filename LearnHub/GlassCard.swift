import SwiftUI

struct OLEDBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        (colorScheme == .dark ? Color.black : Color(red: 0.95, green: 0.95, blue: 0.96))
            .ignoresSafeArea()
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let strokeOpacity: Double
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.1).opacity(0.8) : Color.white.opacity(0.85))
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .foregroundStyle(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(strokeOpacity > 0 ? (colorScheme == .dark ? 0.05 : 0.08) : 0), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.12), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, strokeOpacity: Double = 0.2) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }
}
