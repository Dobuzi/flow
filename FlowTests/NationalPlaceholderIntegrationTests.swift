import Testing
@testable import Flow

struct NationalPlaceholderIntegrationTests {
    @MainActor
    @Test
    func koreaNationalSourceFailsGracefullyWithoutCrash() async {
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

        #expect(viewModel.loadError != nil)
        #expect(viewModel.dataset == nil)
        #expect(viewModel.flowCount == 0)
        #expect(viewModel.nodeCount == 0)
        #expect(viewModel.renderableSegments.isEmpty)
    }
}
