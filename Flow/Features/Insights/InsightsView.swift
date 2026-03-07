import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = InsightsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DatasetSourceBadge(source: store.state.selectedDatasetSource)
                    if viewModel.isLoading {
                        ProgressView("Loading insights...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                    } else if let summary = viewModel.summary {
                        scopeCard(summary: summary)
                        metricsGrid(summary: summary)
                        modeShareSection(summary: summary)
                        topCorridorsSection(summary: summary)
                        timeDistributionSection(summary: summary)
                    } else if let loadError = viewModel.loadError {
                        NonBlockingErrorBanner(error: loadError)
                    }
                }
                .padding()
            }
            .navigationTitle("Insights")
        }
        .task {
            await viewModel.loadIfNeeded(state: store.state)
        }
        .onChange(of: store.state.selectedYear) { _, _ in
            viewModel.recompute(state: store.state)
        }
        .onChange(of: store.state.selectedMonth) { _, _ in
            viewModel.recompute(state: store.state)
        }
        .onChange(of: store.state.selectedHour) { _, _ in
            viewModel.recompute(state: store.state)
        }
        .onChange(of: store.state.selectedModes) { _, _ in
            viewModel.recompute(state: store.state)
        }
        .onChange(of: store.state.selectedDatasetSource) { _, _ in
            Task { await viewModel.loadIfNeeded(state: store.state) }
        }
    }

    private func scopeCard(summary: InsightsSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current Scope")
                .font(.headline)
            Text("Source: \(summary.source.title)")
                .font(.subheadline)
            Text("Time: \(summary.activeTimeLabel)")
                .font(.subheadline)
            Text("Spatial: \(summary.spatialLevel.rawValue.capitalized)")
                .font(.subheadline)
            Text("Modes: \(summary.activeModes.map { $0.rawValue.capitalized }.joined(separator: ", "))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let version = summary.datasetVersion {
                Text("Dataset: \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if summary.renderGuardrailTruncatedCount > 0 {
                Text("Render guardrail active: top \(summary.renderableFlowCount.formatted()) of \(summary.scopedFlowCount.formatted()) scoped flows are shown on map.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func metricsGrid(summary: InsightsSummary) -> some View {
        let cards: [(String, String)] = [
            ("Total Flows", summary.totalFlowCount.formatted()),
            ("Total Nodes", summary.totalNodeCount.formatted()),
            ("Scoped Flows", summary.scopedFlowCount.formatted()),
            ("Renderable Flows", summary.renderableFlowCount.formatted()),
            ("Scoped Volume", formatVolume(summary.scopedVolume))
        ]

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(cards, id: \.0) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.title3.weight(.semibold))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func modeShareSection(summary: InsightsSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode Share")
                .font(.headline)

            if summary.modeShare.isEmpty {
                Text("No flows in current scope.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.modeShare) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.mode.rawValue.capitalized)
                            Spacer()
                            Text("\(Int((item.ratio * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: item.ratio)
                            .tint(modeColor(item.mode))
                        Text("\(item.count) flows • \(formatVolume(item.volume))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func topCorridorsSection(summary: InsightsSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Corridors")
                .font(.headline)
            if summary.topCorridors.isEmpty {
                Text("No corridors in current scope.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(summary.topCorridors.enumerated()), id: \.element.id) { offset, corridor in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(offset + 1).")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(corridor.label)
                                .font(.subheadline.weight(.semibold))
                            Text("\(corridor.flowCount) flows • \(formatVolume(corridor.volume))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func timeDistributionSection(summary: InsightsSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time Distribution")
                .font(.headline)
            if summary.timeDistribution.isEmpty {
                Text("No distribution data for selected modes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.timeDistribution) { item in
                    HStack {
                        Text(item.bucketID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(item.flowCount) flows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatVolume(item.volume))
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    private func modeColor(_ mode: TransportMode) -> Color {
        switch mode {
        case .road:
            return Color(red: 0.145, green: 0.388, blue: 0.922)
        case .rail:
            return Color(red: 0.863, green: 0.149, blue: 0.149)
        case .air:
            return Color(red: 0.031, green: 0.569, blue: 0.698)
        case .maritime:
            return Color(red: 0.059, green: 0.463, blue: 0.431)
        }
    }
}
