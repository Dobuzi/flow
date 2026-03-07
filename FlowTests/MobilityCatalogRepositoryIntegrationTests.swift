import Testing
@testable import Flow

struct MobilityCatalogRepositoryIntegrationTests {
    @Test
    func fetchesBundledCatalogThroughRepository() async throws {
        let repository = MobilityRepositoryFactory.catalogRepository()
        let catalog = try await repository.fetchCatalog()

        #expect(catalog.version == "1.0.0")
        #expect(catalog.defaultSource == .bundledSample)
        #expect(catalog.datasets.count == 3)
        #expect(catalog.descriptor(for: .bundledSample)?.datasetID == "sample-korea-mobility-2025-q1")
        #expect(catalog.descriptor(for: .seoulCapitalSnapshot)?.datasetID == "seoul-capital-living-mobility")
        #expect(catalog.descriptor(for: .koreaNational)?.datasetID == "korea-national-placeholder")
    }
}
