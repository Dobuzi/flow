import Foundation

protocol MobilityQuerying {
    func execute(_ query: MobilityQuery) async throws -> MobilityQueryResult
}

struct DefaultMobilityQueryAdapter: MobilityQuerying {
    private let flowRepositoryBuilder: (FlowDatasetSource) -> FlowRepository
    private let locationRepositoryBuilder: (FlowDatasetSource) -> LocationRepository
    private let compatibilityChecker: DatasetCompatibilityChecking
    private let filteringEngine: FilteringEngine
    private let timeSeriesEngine: TimeSeriesEngine
    private let spatialAggregationEngine: SpatialAggregationEngine

    init(
        flowRepositoryBuilder: @escaping (FlowDatasetSource) -> FlowRepository = { source in
            MobilityRepositoryFactory.flowRepository(for: source)
        },
        locationRepositoryBuilder: @escaping (FlowDatasetSource) -> LocationRepository = { source in
            MobilityRepositoryFactory.locationRepository(for: source)
        },
        compatibilityChecker: DatasetCompatibilityChecking = DatasetCompatibilityChecker(),
        filteringEngine: FilteringEngine = FilteringEngine(),
        timeSeriesEngine: TimeSeriesEngine = TimeSeriesEngine(),
        spatialAggregationEngine: SpatialAggregationEngine = SpatialAggregationEngine()
    ) {
        self.flowRepositoryBuilder = flowRepositoryBuilder
        self.locationRepositoryBuilder = locationRepositoryBuilder
        self.compatibilityChecker = compatibilityChecker
        self.filteringEngine = filteringEngine
        self.timeSeriesEngine = timeSeriesEngine
        self.spatialAggregationEngine = spatialAggregationEngine
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

        var filteredFlows = filteringEngine.filter(
            flows: resolvedFlows,
            nodes: resolvedNodes,
            criteria: FlowFilterCriteria(
                modes: query.selectedModes,
                allowedRegionCodes: nil,
                minimumVolume: nil
            )
        )

        if let bucketID = resolveBucketID(for: query.timeContext, from: filteredFlows) {
            filteredFlows = timeSeriesEngine.flows(matching: bucketID, from: filteredFlows)
        }

        if source == .koreaNational {
            filteredFlows = spatialAggregationEngine.aggregateForRendering(
                flows: filteredFlows,
                nodes: resolvedNodes,
                source: source,
                requestedSpatialLevel: query.spatialLevel
            )
        }

        if query.aggregation.strategy == .topFlows, let limit = query.aggregation.limit, limit > 0 {
            filteredFlows = filteredFlows.sorted { $0.volume > $1.volume }.prefix(limit).map { $0 }
        }

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

    private func resolveBucketID(for context: MobilityTimeContext, from flows: [FlowRecord]) -> String? {
        guard !flows.isEmpty else { return nil }

        if let month = context.month, let hour = context.hour {
            let hourID = try? timeSeriesEngine.hourBucketID(year: context.year, month: month, hour: hour)
            if let hourID, flows.contains(where: { $0.timeBucketID == hourID }) {
                return hourID
            }
        }

        if let month = context.month {
            let monthID = try? timeSeriesEngine.monthBucketID(year: context.year, month: month)
            if let monthID, flows.contains(where: { $0.timeBucketID == monthID }) {
                return monthID
            }
        }

        let yearID = try? timeSeriesEngine.yearBucketID(year: context.year)
        if let yearID, flows.contains(where: { $0.timeBucketID == yearID }) {
            return yearID
        }

        return nil
    }
}
