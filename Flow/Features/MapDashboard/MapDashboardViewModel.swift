import Foundation
import Combine

@MainActor
final class MapDashboardViewModel: ObservableObject {
    @Published private(set) var dataset: FlowDataset?
    @Published private(set) var flowCount: Int = 0
    @Published private(set) var nodeCount: Int = 0
    @Published private(set) var renderableSegments: [RenderableFlowSegment] = []
    @Published private(set) var loadError: String?

    private let flowRepository: FlowRepository
    private let locationRepository: LocationRepository
    private let mapRenderer: FlowMapRenderer
    private let timeSeriesEngine: TimeSeriesEngine
    private let filteringEngine: FilteringEngine
    private let cacheDataSource: CacheDataSource
    private let performanceMonitor: PerformanceMonitor

    private var allFlows: [FlowRecord] = []
    private var allNodes: [LocationNode] = []
    private var preAggregationIndex: PreAggregationIndex?
    private var renderTask: Task<Void, Never>?

    init(
        flowRepository: FlowRepository = LocalFlowRepository(),
        locationRepository: LocationRepository = LocalLocationRepository(),
        mapRenderer: FlowMapRenderer = FlowMapRenderer(),
        timeSeriesEngine: TimeSeriesEngine = TimeSeriesEngine(),
        filteringEngine: FilteringEngine = FilteringEngine(),
        cacheDataSource: CacheDataSource = CacheDataSource(),
        performanceMonitor: PerformanceMonitor = PerformanceMonitor()
    ) {
        self.flowRepository = flowRepository
        self.locationRepository = locationRepository
        self.mapRenderer = mapRenderer
        self.timeSeriesEngine = timeSeriesEngine
        self.filteringEngine = filteringEngine
        self.cacheDataSource = cacheDataSource
        self.performanceMonitor = performanceMonitor
    }

    deinit {
        renderTask?.cancel()
    }

    func load(initialState: AppState) async {
        let loadStart = CFAbsoluteTimeGetCurrent()
        do {
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
            loadError = nil
            applySelection(from: initialState)
            let loadElapsed = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000.0
            performanceMonitor.record("initial_load_ms", milliseconds: loadElapsed)
            FlowLogger.info("Loaded sample dataset with \(flowCount) flows and \(nodeCount) nodes")
        } catch {
            loadError = String(describing: error)
            renderableSegments = []
            FlowLogger.error("Failed to load sample dataset: \(error)")
        }
    }

    func applySelection(from state: AppState) {
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

        await cacheDataSource.setFlows(filtered, for: cacheKey)
        return filtered
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
