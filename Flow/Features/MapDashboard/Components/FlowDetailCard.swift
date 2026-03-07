import SwiftUI

struct FlowDetailCard: View {
    let detail: MapDashboardViewModel.FlowSelectionDetail
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flow Detail")
                        .font(.headline)
                    Text("\(detail.originName) → \(detail.destinationName)")
                        .font(.subheadline.weight(.semibold))
                    Text(detail.flowID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear", action: onClear)
                    .buttonStyle(.bordered)
            }

            HStack {
                Text(detail.mode.rawValue.capitalized)
                Spacer()
                Text(volumeText)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)

            HStack {
                Text("Bucket")
                Spacer()
                Text(detail.timeBucketID)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let corridorName = detail.corridorName {
                metadataRow(label: "Corridor", value: corridorName)
            }
            if let regionType = detail.regionType {
                metadataRow(label: "Region", value: regionType)
            }
            if let confidence = detail.confidenceScore {
                metadataRow(label: "Confidence", value: String(format: "%.2f", confidence))
            }
            if let source = detail.dataSourceTag {
                metadataRow(label: "Source", value: source)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var volumeText: String {
        let value: String
        if detail.volume >= 1_000_000 {
            value = String(format: "%.1fM", detail.volume / 1_000_000)
        } else if detail.volume >= 1_000 {
            value = String(format: "%.1fK", detail.volume / 1_000)
        } else {
            value = String(format: "%.0f", detail.volume)
        }
        return "\(value) \(detail.unitType.rawValue)"
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2)
        }
    }
}
