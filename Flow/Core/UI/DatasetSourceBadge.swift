import SwiftUI

struct DatasetSourceBadge: View {
    let source: FlowDatasetSource

    var body: some View {
        Label(source.title, systemImage: "externaldrive.connected.to.line.below")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .accessibilityLabel("Active dataset source: \(source.title)")
    }
}
