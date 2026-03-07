import SwiftUI

struct FlowLegendView: View {
    let selectedModes: Set<TransportMode>
    let unitWarningText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(TransportMode.allCases, id: \.self) { mode in
                    HStack(spacing: 4) {
                        styleSwatch(for: mode)
                        Text(mode.rawValue.capitalized)
                    }
                    .opacity(selectedModes.contains(mode) ? 1.0 : 0.4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(mode.rawValue.capitalized), \(styleLabel(for: mode)), \(selectedModes.contains(mode) ? "enabled" : "disabled")")
                }
            }
            if let unitWarningText {
                Label(unitWarningText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(unitWarningText)
            }
        }
        .font(.caption2)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func color(for mode: TransportMode) -> Color {
        switch mode {
        case .road: return Color(red: 0.145, green: 0.388, blue: 0.922)
        case .rail: return Color(red: 0.863, green: 0.149, blue: 0.149)
        case .air: return Color(red: 0.031, green: 0.569, blue: 0.698)
        case .maritime: return Color(red: 0.059, green: 0.463, blue: 0.431)
        }
    }

    @ViewBuilder
    private func styleSwatch(for mode: TransportMode) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        switch mode {
        case .road:
            shape
                .fill(color(for: mode))
                .frame(width: 16, height: 4)
        case .rail:
            shape
                .stroke(color(for: mode), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                .frame(width: 16, height: 4)
        case .air:
            shape
                .stroke(color(for: mode), style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
                .frame(width: 16, height: 4)
        case .maritime:
            shape
                .stroke(color(for: mode), style: StrokeStyle(lineWidth: 2, dash: [10, 4]))
                .frame(width: 16, height: 4)
        }
    }

    private func styleLabel(for mode: TransportMode) -> String {
        switch mode {
        case .road: return "solid line"
        case .rail: return "short dash line"
        case .air: return "dot dash line"
        case .maritime: return "long dash line"
        }
    }
}
