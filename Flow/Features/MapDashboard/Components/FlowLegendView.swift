import SwiftUI

struct FlowLegendView: View {
    let selectedModes: Set<TransportMode>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TransportMode.allCases, id: \.self) { mode in
                HStack(spacing: 4) {
                    Circle()
                        .fill(color(for: mode))
                        .frame(width: 8, height: 8)
                    Text(mode.rawValue.capitalized)
                }
                .opacity(selectedModes.contains(mode) ? 1.0 : 0.4)
            }
        }
        .font(.caption2)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private func color(for mode: TransportMode) -> Color {
        switch mode {
        case .road: return Color(red: 0.145, green: 0.388, blue: 0.922)
        case .rail: return Color(red: 0.863, green: 0.149, blue: 0.149)
        case .air: return Color(red: 0.031, green: 0.569, blue: 0.698)
        case .maritime: return Color(red: 0.059, green: 0.463, blue: 0.431)
        }
    }
}
