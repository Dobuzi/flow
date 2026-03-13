import Foundation
import Testing
@testable import Flow

private struct StubFlowRepository: FlowRepository {
    let datasetResult: Result<FlowDataset, Error>
    let flowsResult: Result<[FlowRecord], Error>

    func fetchDataset() async throws -> FlowDataset {
        try datasetResult.get()
    }

    func fetchFlowRecords() async throws -> [FlowRecord] {
        try flowsResult.get()
    }
}

private struct StubLocationRepository: LocationRepository {
    let nodesResult: Result<[LocationNode], Error>

    func fetchLocationNodes() async throws -> [LocationNode] {
        try nodesResult.get()
    }
}

private final class StubMobilityQueryAdapter: MobilityQuerying {
    var result: Result<MobilityQueryResult, Error>

    init(result: Result<MobilityQueryResult, Error>) {
        self.result = result
    }

    func execute(_ query: MobilityQuery) async throws -> MobilityQueryResult {
        try result.get()
    }
}

@MainActor
@Suite(.serialized)
struct MapDashboardSourceStatusTests {
    @Test
    func switchingSourcesUpdatesReadyStatus() async {
        await CacheDataSource.shared.clearAll()
        let nodes = makeNodes(count: 6)
        let flows = makeFlows(nodes: nodes, count: 12, bucketID: "H:2025-01|12")
        let queryAdapter = StubMobilityQueryAdapter(
            result: .success(
                MobilityQueryResult(
                    query: .default,
                    datasetIDs: ["national"],
                    sources: [.koreaNational],
                    nodes: nodes,
                    flows: flows,
                    generatedAt: Date(),
                    compatibilityNotes: ["compatible"]
                )
            )
        )

        let viewModel = makeViewModel(
            nodes: nodes,
            bundledFlows: flows,
            seoulFlows: flows,
            nationalFlows: flows,
            queryAdapter: queryAdapter
        )

        var state = AppState()
        state.selectedDatasetSource = .bundledSample
        await viewModel.load(initialState: state)
        #expect(viewModel.sourceStatus?.state == .ready)
        #expect(viewModel.sourceStatus?.source == .bundledSample)

        state.selectedDatasetSource = .seoulCapitalSnapshot
        await viewModel.load(initialState: state)
        #expect(viewModel.sourceStatus?.state == .ready)
        #expect(viewModel.sourceStatus?.source == .seoulCapitalSnapshot)

        state.selectedDatasetSource = .koreaNational
        await viewModel.load(initialState: state)
        await waitForStatus(in: viewModel) { status in
            status?.source == .koreaNational && status?.state == .ready
        }
        #expect(viewModel.sourceStatus?.source == .koreaNational)
        #expect(viewModel.sourceStatus?.state == .ready)
    }

    @Test
    func nationalRenderGuardrailStateIsSurfacedAsLimited() async {
        await CacheDataSource.shared.clearAll()
        let nodes = makeNodes(count: 30)
        let nationalFlows = makeFlows(nodes: nodes, count: 500, bucketID: "H:2025-01|12")

        let queryAdapter = StubMobilityQueryAdapter(
            result: .success(
                MobilityQueryResult(
                    query: .default,
                    datasetIDs: ["national"],
                    sources: [.koreaNational],
                    nodes: nodes,
                    flows: nationalFlows,
                    generatedAt: Date(),
                    compatibilityNotes: ["compatible"]
                )
            )
        )

        let viewModel = makeViewModel(
            nodes: nodes,
            bundledFlows: [],
            seoulFlows: [],
            nationalFlows: nationalFlows,
            queryAdapter: queryAdapter
        )

        var state = AppState()
        state.selectedDatasetSource = .koreaNational
        await viewModel.load(initialState: state)
        await waitForStatus(in: viewModel) { status in
            status?.source == .koreaNational && status?.state == .limited
        }

        #expect(viewModel.sourceStatus?.source == .koreaNational)
        #expect(viewModel.sourceStatus?.state == .limited)
        #expect(viewModel.sourceStatus?.message.contains("top") == true)
    }

    @Test
    func nationalUnavailableStatusIsSurfacedOnLoadFailure() async {
        await CacheDataSource.shared.clearAll()
        let nodes = makeNodes(count: 4)
        let flows = makeFlows(nodes: nodes, count: 6, bucketID: "H:2025-01|12")
        let error = NationalBaselineRepositoryError.schemaIncompatible("2.0.0")
        let queryAdapter = StubMobilityQueryAdapter(result: .failure(error))

        let viewModel = makeViewModel(
            nodes: nodes,
            bundledFlows: flows,
            seoulFlows: flows,
            nationalFlows: flows,
            queryAdapter: queryAdapter,
            nationalDatasetResult: .failure(error)
        )

        var state = AppState()
        state.selectedDatasetSource = .koreaNational
        await viewModel.load(initialState: state)

        #expect(viewModel.sourceStatus?.source == .koreaNational)
        #expect(viewModel.sourceStatus?.state == .unavailable)
        #expect(viewModel.loadError != nil)
    }

    @Test
    func nationalQueryFallbackStatusIsSurfacedAsLimited() async {
        await CacheDataSource.shared.clearAll()
        let nodes = makeNodes(count: 8)
        let flows = makeFlows(nodes: nodes, count: 18, bucketID: "H:2025-01|12")
        let queryAdapter = StubMobilityQueryAdapter(
            result: .failure(NationalBaselineRepositoryError.invalidFlowRecord(line: 1))
        )

        let viewModel = makeViewModel(
            nodes: nodes,
            bundledFlows: [],
            seoulFlows: [],
            nationalFlows: flows,
            queryAdapter: queryAdapter
        )

        var state = AppState()
        state.selectedDatasetSource = .koreaNational
        await viewModel.load(initialState: state)
        await waitForStatus(in: viewModel) { status in
            status?.source == .koreaNational && status?.state == .limited
        }

        #expect(viewModel.sourceStatus?.source == .koreaNational)
        #expect(viewModel.sourceStatus?.state == .limited)
        #expect(viewModel.sourceStatus?.message.contains("fallback") == true)
    }

    private func makeViewModel(
        nodes: [LocationNode],
        bundledFlows: [FlowRecord],
        seoulFlows: [FlowRecord],
        nationalFlows: [FlowRecord],
        queryAdapter: StubMobilityQueryAdapter,
        nationalDatasetResult: Result<FlowDataset, Error>? = nil
    ) -> MapDashboardViewModel {
        MapDashboardViewModel(
            flowRepositoryBuilder: { source in
                let dataset = makeDataset(source: source)
                switch source {
                case .bundledSample:
                    return StubFlowRepository(datasetResult: .success(dataset), flowsResult: .success(bundledFlows))
                case .seoulCapitalSnapshot:
                    return StubFlowRepository(datasetResult: .success(dataset), flowsResult: .success(seoulFlows))
                case .koreaNational:
                    return StubFlowRepository(
                        datasetResult: nationalDatasetResult ?? .success(dataset),
                        flowsResult: .success(nationalFlows)
                    )
                }
            },
            locationRepositoryBuilder: { _ in
                StubLocationRepository(nodesResult: .success(nodes))
            },
            mobilityQuerying: queryAdapter
        )
    }

    private func makeDataset(source: FlowDatasetSource) -> FlowDataset {
        FlowDataset(
            datasetID: "\(source.rawValue)-id",
            version: "2025.1",
            source: source.rawValue,
            createdAt: "2025-01-01T00:00:00Z",
            spatialLevel: .province,
            timeCoverage: "2025-01",
            recordsCount: 0,
            schemaVersion: "1.0.0"
        )
    }

    private func makeNodes(count: Int) -> [LocationNode] {
        (0..<count).map { idx in
            LocationNode(
                id: "n-\(idx)",
                nameKo: "노드\(idx)",
                nameEn: "Node \(idx)",
                lat: 35.0 + Double(idx) * 0.05,
                lon: 126.0 + Double(idx) * 0.05,
                regionCode: String(format: "%02d010", (idx % 17) + 1),
                regionType: "province",
                importanceRank: idx + 1
            )
        }
    }

    private func makeFlows(nodes: [LocationNode], count: Int, bucketID: String) -> [FlowRecord] {
        guard !nodes.isEmpty else { return [] }
        return (0..<count).map { idx in
            let origin = nodes[idx % nodes.count]
            let destination = nodes[(idx + 1) % nodes.count]
            return FlowRecord(
                id: "f-\(idx)",
                originNodeID: origin.id,
                destinationNodeID: destination.id,
                transportMode: .road,
                timeBucketID: bucketID,
                volume: Double(idx + 1),
                unitType: .vehicles,
                metadata: nil
            )
        }
    }

    private func waitForStatus(
        in viewModel: MapDashboardViewModel,
        timeoutNanoseconds: UInt64 = 1_500_000_000,
        predicate: (DatasetSourceStatus?) -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !predicate(viewModel.sourceStatus) && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }
}
