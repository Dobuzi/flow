import Foundation
import Combine

@MainActor
final class MapDashboardViewModel: ObservableObject {
    struct LegendUnitStatus: Equatable {
        let dominantUnit: FlowRecord.UnitType?
        let isMixed: Bool

        var warningText: String? {
            guard isMixed, let dominantUnit else { return nil }
            return "Mixed units: showing \(dominantUnit.rawValue)"
        }
    }

    struct FlowSelectionDetail: Equatable {
        let flowID: String
        let originName: String
        let destinationName: String
        let mode: TransportMode
        let volume: Double
        let unitType: FlowRecord.UnitType
        let timeBucketID: String
        let corridorName: String?
        let regionType: String?
        let confidenceScore: Double?
        let dataSourceTag: String?
    }

    @Published private(set) var dataset: FlowDataset?
    @Published private(set) var flowCount: Int = 0
    @Published private(set) var nodeCount: Int = 0
    @Published private(set) var renderableSegments: [RenderableFlowSegment] = []
    @Published private(set) var selectedFlowDetail: FlowSelectionDetail?
    @Published private(set) var legendUnitStatus = LegendUnitStatus(dominantUnit: nil, isMixed: false)
    @Published private(set) var loadError: FlowNonFatalError?

    private let flowRepositoryBuilder: (FlowDatasetSource) -> FlowRepository
    private let locationRepositoryBuilder: (FlowDatasetSource) -> LocationRepository
    private let mapRenderer: FlowMapRenderer
    private let timeSeriesEngine: TimeSeriesEngine
    private let filteringEngine: FilteringEngine
    private let spatialAggregationEngine: SpatialAggregationEngine
    private let cacheDataSource: CacheDataSource
    private let performanceMonitor: PerformanceMonitor

    private var activeSource: FlowDatasetSource?
    private var allFlows: [FlowRecord] = []
    private var allNodes: [LocationNode] = []
    private var preAggregationIndex: PreAggregationIndex?
    private var renderTask: Task<Void, Never>?

    init(
        flowRepositoryBuilder: @escaping (FlowDatasetSource) -> FlowRepository = { source in
            MobilityRepositoryFactory.flowRepository(for: source)
        },
        locationRepositoryBuilder: @escaping (FlowDatasetSource) -> LocationRepository = { source in
            MobilityRepositoryFactory.locationRepository(for: source)
        },
        mapRenderer: FlowMapRenderer = FlowMapRenderer(),
        timeSeriesEngine: TimeSeriesEngine = TimeSeriesEngine(),
        filteringEngine: FilteringEngine = FilteringEngine(),
        spatialAggregationEngine: SpatialAggregationEngine = SpatialAggregationEngine(),
        cacheDataSource: CacheDataSource = CacheDataSource.shared,
        performanceMonitor: PerformanceMonitor = PerformanceMonitor()
    ) {
        self.flowRepositoryBuilder = flowRepositoryBuilder
        self.locationRepositoryBuilder = locationRepositoryBuilder
        self.mapRenderer = mapRenderer
        self.timeSeriesEngine = timeSeriesEngine
        self.filteringEngine = filteringEngine
        self.spatialAggregationEngine = spatialAggregationEngine
        self.cacheDataSource = cacheDataSource
        self.performanceMonitor = performanceMonitor
    }

    deinit {
        renderTask?.cancel()
    }

    func load(initialState: AppState) async {
        let loadStart = CFAbsoluteTimeGetCurrent()
        let source = initialState.selectedDatasetSource
        do {
            let flowRepository = flowRepositoryBuilder(source)
            let locationRepository = locationRepositoryBuilder(source)
            async let manifest = flowRepository.fetchDataset()
            async let flows = flowRepository.fetchFlowRecords()
            async let nodes = locationRepository.fetchLocationNodes()

            let (resolvedManifest, resolvedFlows, resolvedNodes) = try await (manifest, flows, nodes)
            dataset = resolvedManifest
            flowCount = resolvedFlows.count
            nodeCount = resolvedNodes.count
            allFlows = resolvedFlows
            allNodes = resolvedNodes
            preAggregationIndex = PreAggregationIndex(flows: resolvedFlows)
            activeSource = source
            loadError = nil
            applySelection(from: initialState)
            let loadElapsed = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000.0
            performanceMonitor.record("initial_load_ms", milliseconds: loadElapsed)
            FlowLogger.info("Loaded \(source.rawValue) dataset with \(flowCount) flows and \(nodeCount) nodes")
        } catch {
            loadError = FlowLogger.nonFatalError(
                scope: .dataLoad,
                userMessage: "Failed to load flow dataset. Map may be incomplete.",
                underlying: error
            )
            renderableSegments = []
        }
    }

    func applySelection(from state: AppState) {
        guard activeSource == state.selectedDatasetSource else { return }
        guard !allFlows.isEmpty else { return }
        guard let bucketID = resolveBucketID(
            year: state.selectedYear,
            month: state.selectedMonth,
            hour: state.selectedHour
        ) else {
            renderableSegments = []
            return
        }

        let modeSet = state.selectedModes
        let spatialLevel = state.spatialLevel
        let selectedFlowID = state.selectedFlowID
        let datasetVersion = dataset?.version ?? "unknown"

        renderTask?.cancel()
        renderTask = Task { [bucketID] in
            let selectionStart = CFAbsoluteTimeGetCurrent()
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            let scopedFlows: [FlowRecord] = await resolveScopedFlows(
                bucketID: bucketID,
                modeSet: modeSet,
                spatialLevel: spatialLevel,
                datasetVersion: datasetVersion
            )

            var segments: [RenderableFlowSegment] = []
            performanceMonitor.measure("render_segment_build_ms") {
                segments = mapRenderer.buildRenderableSegments(flows: scopedFlows, nodes: allNodes)
            }

            guard !Task.isCancelled else { return }
            renderableSegments = segments
            legendUnitStatus = buildLegendUnitStatus(scopedFlows: scopedFlows)
            selectedFlowDetail = buildFlowSelectionDetail(
                selectedFlowID: selectedFlowID,
                scopedFlows: scopedFlows,
                activeBucketID: bucketID
            )
            let selectionElapsed = (CFAbsoluteTimeGetCurrent() - selectionStart) * 1000.0
            performanceMonitor.record("selection_to_render_ms", milliseconds: selectionElapsed)
            if let p95 = performanceMonitor.p95("render_segment_build_ms") {
                FlowLogger.info("render_segment_build_ms p95=\(String(format: "%.2f", p95))")
            }
        }
    }

    func performanceReport() -> [String: (avg: Double, p95: Double)] {
        performanceMonitor.report()
    }

    func recordMetric(_ key: String, milliseconds: Double) {
        performanceMonitor.record(key, milliseconds: milliseconds)
    }

    func budgetStatusReport() -> [String: Bool] {
        let report = performanceMonitor.report()
        return [
            "overlay_diff_apply_ms_p95_le_16_7": (report["overlay_diff_apply_ms"]?.p95 ?? .infinity) <= 16.7,
            "filter_apply_ms_p95_le_200": (report["filter_apply_ms"]?.p95 ?? .infinity) <= 200.0,
            "playback_tick_ms_p95_le_120": (report["playback_tick_ms"]?.p95 ?? .infinity) <= 120.0,
            "initial_load_ms_p95_le_2000": (report["initial_load_ms"]?.p95 ?? .infinity) <= 2000.0
        ]
    }

    private func resolveScopedFlows(
        bucketID: String,
        modeSet: Set<TransportMode>,
        spatialLevel: SpatialLevel,
        datasetVersion: String
    ) async -> [FlowRecord] {
        guard !modeSet.isEmpty else { return [] }

        let unitType = dominantUnitType(for: bucketID, modes: modeSet, spatialLevel: spatialLevel) ?? "mixed"
        let cacheKey = FlowCacheKey(
            datasetVersion: datasetVersion,
            spatialLevel: spatialLevel,
            timeBucketID: bucketID,
            modeSet: modeSet,
            unitType: unitType
        )

        if let cached = await cacheDataSource.getFlows(for: cacheKey) {
            return cached
        }

        let preAggregated = preAggregationIndex?.flows(
            timeBucketID: bucketID,
            modes: modeSet,
            spatialLevel: spatialLevel
        ) ?? []

        var filtered: [FlowRecord] = []
        performanceMonitor.measure("filter_apply_ms") {
            filtered = filteringEngine.filter(
                flows: preAggregated,
                nodes: allNodes,
                criteria: FlowFilterCriteria(
                    modes: modeSet,
                    allowedRegionCodes: nil,
                    minimumVolume: nil
                )
            )
        }

        let shaped = spatialAggregationEngine.aggregateForRendering(
            flows: filtered,
            nodes: allNodes,
            source: activeSource ?? .bundledSample,
            requestedSpatialLevel: spatialLevel
        )

        await cacheDataSource.setFlows(shaped, for: cacheKey)
        return shaped
    }

    private func dominantUnitType(for bucketID: String, modes: Set<TransportMode>, spatialLevel: SpatialLevel) -> String? {
        let preAggregated = preAggregationIndex?.flows(
            timeBucketID: bucketID,
            modes: modes,
            spatialLevel: spatialLevel
        ) ?? []

        let grouped = Dictionary(grouping: preAggregated, by: \.unitType)
        return grouped.max { $0.value.count < $1.value.count }?.key.rawValue
    }

    private func buildLegendUnitStatus(scopedFlows: [FlowRecord]) -> LegendUnitStatus {
        let grouped = Dictionary(grouping: scopedFlows, by: \.unitType)
        guard !grouped.isEmpty else {
            return LegendUnitStatus(dominantUnit: nil, isMixed: false)
        }
        let dominant = grouped.max { $0.value.count < $1.value.count }?.key
        return LegendUnitStatus(
            dominantUnit: dominant,
            isMixed: grouped.count > 1
        )
    }

    private func buildFlowSelectionDetail(
        selectedFlowID: String?,
        scopedFlows: [FlowRecord],
        activeBucketID: String
    ) -> FlowSelectionDetail? {
        guard let selectedFlowID else { return nil }
        guard let flow = scopedFlows.first(where: { $0.id == selectedFlowID }) else { return nil }

        let nodesByID = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })
        let originName = nodesByID[flow.originNodeID]?.nameEn ?? nodesByID[flow.originNodeID]?.nameKo ?? flow.originNodeID
        let destinationName = nodesByID[flow.destinationNodeID]?.nameEn ?? nodesByID[flow.destinationNodeID]?.nameKo ?? flow.destinationNodeID

        return FlowSelectionDetail(
            flowID: flow.id,
            originName: originName,
            destinationName: destinationName,
            mode: flow.transportMode,
            volume: flow.volume,
            unitType: flow.unitType,
            timeBucketID: activeBucketID,
            corridorName: flow.metadata?.corridorName,
            regionType: flow.metadata?.regionType,
            confidenceScore: flow.metadata?.confidenceScore,
            dataSourceTag: flow.metadata?.dataSourceTag
        )
    }

    private func resolveBucketID(year: Int, month: Int, hour: Int) -> String? {
        let hourID = try? timeSeriesEngine.hourBucketID(year: year, month: month, hour: hour)
        if let hourID, allFlows.contains(where: { $0.timeBucketID == hourID }) {
            return hourID
        }

        let monthID = try? timeSeriesEngine.monthBucketID(year: year, month: month)
        if let monthID, allFlows.contains(where: { $0.timeBucketID == monthID }) {
            return monthID
        }

        let yearID = try? timeSeriesEngine.yearBucketID(year: year)
        if let yearID, allFlows.contains(where: { $0.timeBucketID == yearID }) {
            return yearID
        }
        return monthID ?? yearID ?? hourID
    }
}
