import Foundation

struct LocalMobilityCatalogRepository: MobilityCatalogRepository {
    private let dataSource: MobilityCatalogDataSource
    private let liveMetadataEnricher: CatalogLiveMetadataEnriching?

    init(
        dataSource: MobilityCatalogDataSource = LocalMobilityCatalogDataSource(),
        liveMetadataEnricher: CatalogLiveMetadataEnriching? = nil
    ) {
        self.dataSource = dataSource
        self.liveMetadataEnricher = liveMetadataEnricher
    }

    func fetchCatalog() async throws -> MobilityDatasetCatalog {
        let catalog = try dataSource.loadCatalog()
        guard let liveMetadataEnricher else {
            return catalog
        }

        var enriched: [MobilityDatasetDescriptor] = []
        enriched.reserveCapacity(catalog.datasets.count)
        for dataset in catalog.datasets {
            enriched.append(await liveMetadataEnricher.enrich(dataset))
        }

        return MobilityDatasetCatalog(
            version: catalog.version,
            defaultSource: catalog.defaultSource,
            datasets: enriched
        )
    }
}
