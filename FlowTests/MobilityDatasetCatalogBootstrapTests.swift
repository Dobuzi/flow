import Testing
import Foundation
@testable import Flow

struct MobilityDatasetCatalogBootstrapTests {
    @Test
    func loadsBundledDatasetCatalog() throws {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "dataset_catalog", withExtension: "json", subdirectory: "Resources/DatasetCatalog")
                ?? bundle.url(forResource: "dataset_catalog", withExtension: "json") else {
            Issue.record("dataset_catalog.json not found in bundle")
            return
        }

        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(MobilityDatasetCatalogDTO.self, from: data)
        let catalog = MobilityDatasetCatalogMapper.map(dto)

        #expect(catalog.version == "1.0.0")
        #expect(catalog.datasets.count == 3)
        #expect(catalog.defaultSource == .bundledSample)
        #expect(catalog.descriptor(for: .bundledSample) != nil)
        #expect(catalog.descriptor(for: .seoulCapitalSnapshot) != nil)
        #expect(catalog.descriptor(for: .koreaNational) != nil)
        #expect(catalog.descriptor(for: .bundledSample)?.liveMetadata == nil)
        #expect(catalog.descriptor(for: .seoulCapitalSnapshot)?.liveMetadata?.supportsLiveRefresh == true)
        #expect(catalog.descriptor(for: .koreaNational)?.liveMetadata?.supportsLiveRefresh == true)
    }
}
