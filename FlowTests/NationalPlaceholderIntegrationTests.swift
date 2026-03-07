import Foundation
import Testing
@testable import Flow

struct NationalBaselineIntegrationTests {
    @MainActor
    @Test
    func koreaNationalSourceLoadsBundledBaselineSnapshot() async {
        var state = AppState()
        state.selectedDatasetSource = .koreaNational

        let viewModel = MapDashboardViewModel(
            flowRepositoryBuilder: { source in
                MobilityRepositoryFactory.flowRepository(for: source)
            },
            locationRepositoryBuilder: { source in
                MobilityRepositoryFactory.locationRepository(for: source)
            }
        )

        await viewModel.load(initialState: state)

        #expect(viewModel.loadError == nil)
        #expect(viewModel.dataset?.datasetID == "korea-national-baseline-2025")
        #expect(viewModel.flowCount >= 8)
        #expect(viewModel.nodeCount >= 6)
    }

    @Test
    func nationalDataSourceLoadsManifestNodesAndFlows() throws {
        let dataSource = NationalBaselineSnapshotDataSource(bundle: .main)
        let dataset = try dataSource.loadDatasetManifest()
        let nodes = try dataSource.loadNodes()
        let flows = try dataSource.loadFlows()

        #expect(dataset.datasetID == "korea-national-baseline-2025")
        #expect(dataset.source == FlowDatasetSource.koreaNational.rawValue)
        #expect(dataset.spatialLevel == .province)
        #expect(nodes.count >= 6)
        #expect(flows.count >= 8)
        #expect(flows.contains(where: { $0.transportMode == .road }))
        #expect(flows.contains(where: { $0.transportMode == .rail }))
        #expect(flows.contains(where: { $0.transportMode == .air }))
        #expect(flows.contains(where: { $0.transportMode == .maritime }))
    }
}
