import CoreLocation
import Testing
@testable import Flow

struct MapRenderingIntegrationTests {
    @Test
    func thresholdAndTop150Override() throws {
        let renderer = FlowMapRenderer()
        let nodes = [
            makeNode(id: "A", lat: 37.5665, lon: 126.9780),
            makeNode(id: "B", lat: 35.1796, lon: 129.0756)
        ]

        var flows: [FlowRecord] = []
        flows.append(makeFlow(id: "high", origin: "A", destination: "B", mode: .rail, volume: 10_000))
        for idx in 1...199 {
            flows.append(makeFlow(id: "low-\(idx)", origin: "A", destination: "B", mode: .road, volume: 1))
        }

        let segments = renderer.buildRenderableSegments(flows: flows, nodes: nodes)
        #expect(segments.count == 150)
        #expect(segments.contains(where: { $0.id == "high" }))
    }

    @Test
    func segmentCapsBySpatialLevelKeepTopVolume() {
        let renderer = FlowMapRenderer()
        let baseOrigin = CLLocationCoordinate2D(latitude: 37.0, longitude: 127.0)
        let baseDestination = CLLocationCoordinate2D(latitude: 35.0, longitude: 129.0)
        let segments = (0..<3_500).map { idx in
            RenderableFlowSegment(
                id: "s-\(idx)",
                origin: baseOrigin,
                destination: baseDestination,
                mode: .road,
                volume: Double(idx),
                normalizedIntensity: 1,
                lineWidth: 2,
                opacity: 0.8
            )
        }

        let national = renderer.cappedSegments(for: .national, segments: segments)
        let province = renderer.cappedSegments(for: .province, segments: segments)
        let city = renderer.cappedSegments(for: .city, segments: segments)

        #expect(national.count == 1_200)
        #expect(province.count == 2_000)
        #expect(city.count == 3_000)
        #expect(national.map(\.volume).min() == 2_300)
    }

    @MainActor
    @Test
    func selectionDetailClearsWhenFilteredOut() async {
        let viewModel = MapDashboardViewModel(
            flowRepository: LocalFlowRepository(),
            locationRepository: LocalLocationRepository(),
            mapRenderer: FlowMapRenderer(),
            timeSeriesEngine: TimeSeriesEngine(),
            filteringEngine: FilteringEngine(),
            cacheDataSource: CacheDataSource.shared,
            performanceMonitor: PerformanceMonitor()
        )

        var state = AppState()
        state.selectedYear = 2025
        state.selectedMonth = 1
        state.selectedHour = 12

        await viewModel.load(initialState: state)

        state.selectedFlowID = "f-001"
        state.selectedModes = Set(TransportMode.allCases)
        viewModel.applySelection(from: state)
        try? await Task.sleep(nanoseconds: 260_000_000)
        #expect(viewModel.selectedFlowDetail?.flowID == "f-001")

        state.selectedModes = [.road]
        viewModel.applySelection(from: state)
        try? await Task.sleep(nanoseconds: 260_000_000)
        #expect(viewModel.selectedFlowDetail == nil)
    }

    private func makeNode(id: String, lat: Double, lon: Double) -> LocationNode {
        LocationNode(
            id: id,
            nameKo: id,
            nameEn: id,
            lat: lat,
            lon: lon,
            regionCode: "11",
            regionType: "city",
            importanceRank: nil
        )
    }

    private func makeFlow(
        id: String,
        origin: String,
        destination: String,
        mode: TransportMode,
        volume: Double
    ) -> FlowRecord {
        FlowRecord(
            id: id,
            originNodeID: origin,
            destinationNodeID: destination,
            transportMode: mode,
            timeBucketID: "M:2025-01",
            volume: volume,
            unitType: .vehicles,
            metadata: nil
        )
    }
}
