import Foundation
import Testing
@testable import Flow

private final class RecordingQueryAdapter: MobilityQuerying {
    private(set) var executedQueries: [MobilityQuery] = []

    func execute(_ query: MobilityQuery) async throws -> MobilityQueryResult {
        executedQueries.append(query)
        let flow = FlowRecord(
            id: "query-flow-1",
            originNodeID: "11",
            destinationNodeID: "26",
            transportMode: .road,
            timeBucketID: "H:2025-01|08",
            volume: 1200,
            unitType: .vehicles,
            metadata: FlowRecord.Metadata(
                corridorName: "Query Path Corridor",
                regionType: SpatialLevel.province.rawValue,
                isPassengerFlow: true,
                isFreightFlow: false,
                confidenceScore: 0.9,
                dataSourceTag: "query_adapter_test"
            )
        )

        return MobilityQueryResult(
            query: query,
            datasetIDs: ["query-test"],
            sources: [.koreaNational],
            nodes: [],
            flows: [flow],
            generatedAt: Date(),
            compatibilityNotes: ["compatible"]
        )
    }
}

@MainActor
struct NationalQueryPathIntegrationTests {
    @Test
    func mapDashboardUsesMobilityQueryPathForKoreaNational() async {
        await CacheDataSource.shared.clearAll()

        var state = AppState()
        state.selectedDatasetSource = .koreaNational
        state.selectedModes = [.road]
        state.selectedYear = 2025
        state.selectedMonth = 1
        state.selectedHour = 8
        state.spatialLevel = .national

        let queryAdapter = RecordingQueryAdapter()
        let viewModel = MapDashboardViewModel(
            flowRepositoryBuilder: { source in
                MobilityRepositoryFactory.flowRepository(for: source)
            },
            locationRepositoryBuilder: { source in
                MobilityRepositoryFactory.locationRepository(for: source)
            },
            mobilityQuerying: queryAdapter
        )

        await viewModel.load(initialState: state)
        try? await Task.sleep(nanoseconds: 260_000_000)

        #expect(!queryAdapter.executedQueries.isEmpty)
        #expect(queryAdapter.executedQueries.last?.sources == [.koreaNational])
        #expect(viewModel.renderableSegments.contains(where: { $0.id == "query-flow-1" }))
        #expect(viewModel.renderableSegments.allSatisfy { $0.mode == .road })
    }
}
