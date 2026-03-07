import Foundation

protocol MobilityQuerying {
    func execute(_ query: MobilityQuery) async throws -> MobilityQueryResult
}

struct DefaultMobilityQueryAdapter: MobilityQuerying {
    private let flowRepositoryBuilder: (FlowDatasetSource) -> FlowRepository
    private let locationRepositoryBuilder: (FlowDatasetSource) -> LocationRepository
    private let compatibilityChecker: DatasetCompatibilityChecking

    init(
        flowRepositoryBuilder: @escaping (FlowDatasetSource) -> FlowRepository = { source in
            MobilityRepositoryFactory.flowRepository(for: source)
        },
        locationRepositoryBuilder: @escaping (FlowDatasetSource) -> LocationRepository = { source in
            MobilityRepositoryFactory.locationRepository(for: source)
        },
        compatibilityChecker: DatasetCompatibilityChecking = DatasetCompatibilityChecker()
    ) {
        self.flowRepositoryBuilder = flowRepositoryBuilder
        self.locationRepositoryBuilder = locationRepositoryBuilder
        self.compatibilityChecker = compatibilityChecker
    }

    func execute(_ query: MobilityQuery) async throws -> MobilityQueryResult {
        let source = query.sources.sorted(by: { $0.rawValue < $1.rawValue }).first ?? .bundledSample
        let flowRepository = flowRepositoryBuilder(source)
        let locationRepository = locationRepositoryBuilder(source)

        async let dataset = flowRepository.fetchDataset()
        async let nodes = locationRepository.fetchLocationNodes()
        async let flows = flowRepository.fetchFlowRecords()

        let resolvedDataset = try await dataset
        let resolvedNodes = try await nodes
        let resolvedFlows = try await flows

        let filteredFlows = resolvedFlows.filter { query.selectedModes.contains($0.transportMode) }
        let compatibility = compatibilityChecker.evaluate(dataset: resolvedDataset, source: source)
        let notes = compatibility.isCompatible ? ["compatible"] : compatibility.reasons

        return MobilityQueryResult.singleSource(
            query: query,
            dataset: resolvedDataset,
            source: source,
            nodes: resolvedNodes,
            flows: filteredFlows,
            compatibilityNotes: notes
        )
    }
}
