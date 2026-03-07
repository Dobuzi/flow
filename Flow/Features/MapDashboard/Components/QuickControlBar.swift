import SwiftUI

struct QuickControlBar: View {
    let spatialLevel: SpatialLevel
    let flowCount: Int
    let nodeCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Label("\(spatialLevel.rawValue.capitalized)", systemImage: "scope")
            Label("Flows: \(flowCount)", systemImage: "arrow.triangle.swap")
            Label("Nodes: \(nodeCount)", systemImage: "mappin.and.ellipse")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}
