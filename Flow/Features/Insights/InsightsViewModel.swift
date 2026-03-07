import Foundation
import Combine

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var summary: InsightsSummary?
    @Published private(set) var loadError: FlowNonFatalError?
    @Published private(set) var isLoading: Bool = false

    private let flowRepository: FlowRepository
    private let locationRepository: LocationRepository
    private let useCase: ComputeInsightsUseCase

    private var dataset: FlowDataset?
    private var allFlows: [FlowRecord] = []
    private var allNodes: [LocationNode] = []
    private var hasLoaded = false

    init(
        flowRepository: FlowRepository = LocalFlowRepository(),
        locationRepository: LocationRepository = LocalLocationRepository(),
        useCase: ComputeInsightsUseCase = ComputeInsightsUseCase()
    ) {
        self.flowRepository = flowRepository
        self.locationRepository = locationRepository
        self.useCase = useCase
    }

    func loadIfNeeded(state: AppState) async {
        guard !hasLoaded else {
            recompute(state: state)
            return
        }

        isLoading = true
        do {
            async let manifest = flowRepository.fetchDataset()
            async let flows = flowRepository.fetchFlowRecords()
            async let nodes = locationRepository.fetchLocationNodes()
            let (resolvedManifest, resolvedFlows, resolvedNodes) = try await (manifest, flows, nodes)

            dataset = resolvedManifest
            allFlows = resolvedFlows
            allNodes = resolvedNodes
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
        guard hasLoaded else { return }
        summary = useCase.execute(
            datasetVersion: dataset?.version,
            flows: allFlows,
            nodes: allNodes,
            state: state
        )
    }
}
