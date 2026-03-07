import Testing
import Foundation
@testable import Flow

struct SeoulCapitalDataSourceIntegrationTests {
    @Test
    func loadsSeoulCapitalSnapshotFromBundle() throws {
        let dataSource = SeoulCapitalMobilityDataSource(bundle: .main)
        let dataset = try dataSource.loadDatasetManifest()
        let nodes = try dataSource.loadNodes()
        let flows = try dataSource.loadFlows()

        #expect(dataset.datasetID == "seoul-capital-living-mobility")
        #expect(dataset.schemaVersion == "1.0.0")
        #expect(nodes.count >= 5)
        #expect(flows.count >= 8)
        #expect(flows.contains(where: { $0.transportMode == .air }))
        #expect(flows.contains(where: { $0.transportMode == .rail }))
        #expect(flows.contains(where: { $0.transportMode == .road }))
    }

    @MainActor
    @Test
    func mapViewModelLoadsSelectedDatasetSource() async {
        let viewModel = MapDashboardViewModel(
            flowRepositoryBuilder: { source in
                MobilityRepositoryFactory.flowRepository(for: source)
            },
            locationRepositoryBuilder: { source in
                MobilityRepositoryFactory.locationRepository(for: source)
            },
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

        state.selectedDatasetSource = .bundledSample
        await viewModel.load(initialState: state)
        let sampleFlowCount = viewModel.flowCount
        #expect(sampleFlowCount == 4)

        state.selectedDatasetSource = .seoulCapitalSnapshot
        await viewModel.load(initialState: state)
        #expect(viewModel.flowCount >= 8)
        #expect(viewModel.dataset?.datasetID == "seoul-capital-living-mobility")
    }
}
