import SwiftUI

/// Measurements shared by the panels, so the three screens stay aligned.
enum PanelMetrics {
    static let radius: CGFloat = 24
    /// Widest a panel of text gets.
    static let maxWidth: CGFloat = 620
    static let rowInset: CGFloat = 18
    static let rowPadding: CGFloat = 10
    static let edgePadding: CGFloat = 6
}

/// A Liquid Glass panel as tall as its content. When the content doesn't fit, it scrolls inside the panel
/// and fades at the panel's edges.
struct GlassPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    /// Measured heights: one scroll view serves both cases. (Trying two layouts with `ViewThatFits`
    /// made SwiftUI lay out the whole window on every animation frame.)
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content()
                .padding(.vertical, PanelMetrics.edgePadding)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: contentHeight > 0 ? contentHeight : nil)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .mask {
            if contentHeight > viewportHeight + 1 {
                Self.edgeFade
            } else {
                Rectangle()
            }
        }
        .glassEffect(in: .rect(cornerRadius: PanelMetrics.radius))
    }

    private static var edgeFade: LinearGradient {
        LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.07),
                    .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// Rows separated by hairlines that start under the text, past a leading column (icon or avatar).
struct PanelRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let leadingColumn: CGFloat
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { PanelDivider(leadingColumn: leadingColumn) }
                row(item)
                    .padding(.horizontal, PanelMetrics.rowInset)
                    .padding(.vertical, PanelMetrics.rowPadding)
            }
        }
    }
}

struct PanelDivider: View {
    let leadingColumn: CGFloat

    var body: some View {
        Divider().padding(.leading, PanelMetrics.rowInset + leadingColumn)
    }
}
