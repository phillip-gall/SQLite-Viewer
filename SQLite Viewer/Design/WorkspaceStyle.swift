import SwiftUI

/// Glass belongs to controls. Data stays on an opaque, readable canvas.
enum WorkspaceStyle {
    static let accent = Color.accentColor
    static let canvas = Color(uiColor: .systemBackground)
}

struct GlassControlBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) { content }
                .padding(8)
                .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SymbolButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .help(title)
        .accessibilityLabel(title)
    }
}
