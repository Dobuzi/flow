import Foundation
import Combine

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var summary: InsightsSummary?
    @Published private(set) var loadError: FlowNonFatalError?
    @Published private(set) var isLoading: Bool = false

    private let flowRepositoryBuilder: (FlowDatasetSource) -> FlowRepository
    private let locationRepositoryBuilder: (FlowDatasetSource) -> LocationRepository
    private let useCase: ComputeInsightsUseCase

    private var activeSource: FlowDatasetSource?
    private var dataset: FlowDataset?
    private var allFlows: [FlowRecord] = []
    private var allNodes: [LocationNode] = []
    private var hasLoaded = false

    init(
        flowRepositoryBuilder: @escaping (FlowDatasetSource) -> FlowRepository = { source in
            MobilityRepositoryFactory.flowRepository(for: source)
        },
        locationRepositoryBuilder: @escaping (FlowDatasetSource) -> LocationRepository = { source in
            MobilityRepositoryFactory.locationRepository(for: source)
        },
        useCase: ComputeInsightsUseCase = ComputeInsightsUseCase()
    ) {
        self.flowRepositoryBuilder = flowRepositoryBuilder
        self.locationRepositoryBuilder = locationRepositoryBuilder
        self.useCase = useCase
    }

    func loadIfNeeded(state: AppState) async {
        let source = state.selectedDatasetSource
        if hasLoaded, activeSource == source {
            recompute(state: state)
            return
        }
        if hasLoaded, activeSource != source {
            breakLoadState()
        }
        await load(source: source, state: state)
    }

    private func breakLoadState() {
        hasLoaded = false
        dataset = nil
        allFlows = []
        allNodes = []
        summary = nil
    }

    private func load(source: FlowDatasetSource, state: AppState) async {
        isLoading = true
        do {
            let flowRepository = flowRepositoryBuilder(source)
            let locationRepository = locationRepositoryBuilder(source)
            async let manifest = flowRepository.fetchDataset()
            async let flows = flowRepository.fetchFlowRecords()
            async let nodes = locationRepository.fetchLocationNodes()
            let (resolvedManifest, resolvedFlows, resolvedNodes) = try await (manifest, flows, nodes)

            dataset = resolvedManifest
            allFlows = resolvedFlows
            allNodes = resolvedNodes
            activeSource = source
            hasLoaded = true
            loadError = nil
            recompute(state: state)
        } catch {
            loadError = FlowLogger.nonFatalError(
                scope: .insights,
                userMessage: "Failed to compute insights for the current scope.",
                underlying: error
            )
            summary = nil
        }
        isLoading = false
    }

    func recompute(state: AppState) {
        guard hasLoaded, activeSource == state.selectedDatasetSource else { return }
        summary = useCase.execute(
            datasetVersion: dataset?.version,
            flows: allFlows,
            nodes: allNodes,
            state: state
        )
    }
}
