import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                datasetSection
                cacheSection
                visualizationSection
            }
            .navigationTitle("Settings")
        }
        .task {
            await viewModel.load(source: store.state.selectedDatasetSource)
            applyPreferredSpatialLevel()
        }
        .onChange(of: store.state.selectedDatasetSource) { _, value in
            Task { await viewModel.load(source: value) }
        }
    }

    private var datasetSection: some View {
        Section("Dataset") {
            Picker(
                "Source",
                selection: Binding(
                    get: { store.state.selectedDatasetSource },
                    set: { source in
                        store.send(.setDatasetSource(source))
                    }
                )
            ) {
                ForEach(FlowDatasetSource.allCases, id: \.self) { source in
                    Text(source.title).tag(source)
                }
            }

            if let dataset = viewModel.dataset {
                LabeledContent("Version", value: dataset.version)
                LabeledContent("Schema", value: dataset.schemaVersion)
                LabeledContent("Records", value: dataset.recordsCount.formatted())
                LabeledContent("Coverage", value: dataset.timeCoverage)
            } else if let loadError = viewModel.loadError {
                NonBlockingErrorBanner(error: loadError)
            } else {
                ProgressView()
            }
        }
    }

    private var cacheSection: some View {
        Section("Cache") {
            if let stats = viewModel.cacheStats {
                LabeledContent("Memory", value: "\(formatBytes(stats.memoryUsageBytes)) / \(formatBytes(stats.memoryBudgetBytes))")
                LabeledContent("Memory Entries", value: stats.memoryEntries.formatted())
                LabeledContent("Disk", value: "\(formatBytes(stats.diskUsageBytes)) / \(formatBytes(stats.diskBudgetBytes))")
                LabeledContent("Disk Files", value: stats.diskFiles.formatted())
            } else {
                ProgressView()
            }

            Button("Refresh Cache Stats") {
                Task { await viewModel.refreshCacheStats() }
            }

            Button("Clear Cache", role: .destructive) {
                Task { await viewModel.clearCache() }
            }
        }
    }

    private var visualizationSection: some View {
        Section("Visualization") {
            Picker("Default Spatial Level", selection: $viewModel.preferredSpatialLevelRaw) {
                ForEach(SpatialLevel.allCases, id: \.rawValue) { level in
                    Text(level.rawValue.capitalized).tag(level.rawValue)
                }
            }
            .onChange(of: viewModel.preferredSpatialLevelRaw) { _, value in
                viewModel.savePreferredSpatialLevel(value)
                applyPreferredSpatialLevel()
            }
        }
    }

    private func applyPreferredSpatialLevel() {
        guard let level = SpatialLevel(rawValue: viewModel.preferredSpatialLevelRaw) else { return }
        store.send(.setSpatialLevel(level))
    }

    private func formatBytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}
