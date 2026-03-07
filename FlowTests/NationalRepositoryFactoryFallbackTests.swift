import Foundation
import Testing
@testable import Flow

private struct MockNationalDataSource: NationalBaselineMobilityDataSource {
    let manifestResult: Result<FlowDataset, Error>
    let nodesResult: Result<[LocationNode], Error>
    let flowsResult: Result<[FlowRecord], Error>

    init(
        manifestResult: Result<FlowDataset, Error>,
        nodesResult: Result<[LocationNode], Error> = .success([]),
        flowsResult: Result<[FlowRecord], Error> = .success([])
    ) {
        self.manifestResult = manifestResult
        self.nodesResult = nodesResult
        self.flowsResult = flowsResult
    }

    func loadDatasetManifest() throws -> FlowDataset {
        try manifestResult.get()
    }

    func loadNodes() throws -> [LocationNode] {
        try nodesResult.get()
    }

    func loadFlows() throws -> [FlowRecord] {
        try flowsResult.get()
    }
}

@MainActor
@Suite(.serialized)
struct NationalRepositoryFactoryFallbackTests {
    @Test
    func returnsControlledErrorWhenManifestFileIsMissing() async {
        let repository = NationalBaselineMobilityFlowRepository(
            dataSource: SafeNationalBaselineMobilityDataSource(
                wrapped: MockNationalDataSource(
                    manifestResult: .failure(DataSourceError.missingResource("korea_national_manifest.json"))
                )
            )
        )
        await #expect(throws: NationalBaselineRepositoryError.missingSnapshotResource("korea_national_manifest.json")) {
            _ = try await repository.fetchDataset()
        }
    }

    @Test
    func returnsControlledErrorWhenSchemaIsIncompatible() async {
        let repository = NationalBaselineMobilityFlowRepository(
            dataSource: SafeNationalBaselineMobilityDataSource(
                wrapped: MockNationalDataSource(
                    manifestResult: .failure(DataSourceError.invalidSchemaVersion("2.0.0"))
                )
            )
        )
        await #expect(throws: NationalBaselineRepositoryError.schemaIncompatible("2.0.0")) {
            _ = try await repository.fetchDataset()
        }
    }

    @Test
    func returnsControlledErrorWhenFlowSnapshotIsCorrupt() async {
        let manifest = FlowDataset(
            datasetID: "korea-national-baseline-2025",
            version: "2025.1",
            source: FlowDatasetSource.koreaNational.rawValue,
            createdAt: "2025-12-31T00:00:00Z",
            spatialLevel: .province,
            timeCoverage: "2025-01~2025-12",
            recordsCount: 0,
            schemaVersion: "1.0.0"
        )

        let repository = NationalBaselineMobilityFlowRepository(
            dataSource: SafeNationalBaselineMobilityDataSource(
                wrapped: MockNationalDataSource(
                    manifestResult: .success(manifest),
                    flowsResult: .failure(NationalBaselineDataSourceError.invalidFlowSnapshotLine(4))
                )
            )
        )
        await #expect(throws: NationalBaselineRepositoryError.invalidFlowRecord(line: 4)) {
            _ = try await repository.fetchFlowRecords()
        }
    }

    @Test
    func factoryUsesSafeNationalPathByDefault() async throws {
        let flowRepository = MobilityRepositoryFactory.flowRepository(for: .koreaNational)
        let dataset = try await flowRepository.fetchDataset()
        #expect(dataset.datasetID == "korea-national-baseline-2025")
    }

    @Test
    func sampleAndSeoulFactoryPathsRemainUsable() async throws {
        let sampleFlowRepo = MobilityRepositoryFactory.flowRepository(for: .bundledSample)
        let seoulFlowRepo = MobilityRepositoryFactory.flowRepository(for: .seoulCapitalSnapshot)
        let sampleLocationRepo = MobilityRepositoryFactory.locationRepository(for: .bundledSample)
        let seoulLocationRepo = MobilityRepositoryFactory.locationRepository(for: .seoulCapitalSnapshot)

        let sampleDataset = try await sampleFlowRepo.fetchDataset()
        let seoulDataset = try await seoulFlowRepo.fetchDataset()
        let sampleNodes = try await sampleLocationRepo.fetchLocationNodes()
        let seoulNodes = try await seoulLocationRepo.fetchLocationNodes()

        #expect(sampleDataset.datasetID == "kr-mobility-sample")
        #expect(seoulDataset.datasetID == "seoul-capital-living-mobility")
        #expect(!sampleNodes.isEmpty)
        #expect(!seoulNodes.isEmpty)
    }
}
