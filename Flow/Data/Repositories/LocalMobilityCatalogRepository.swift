import Foundation

struct LocalMobilityCatalogRepository: MobilityCatalogRepository {
    private let dataSource: MobilityCatalogDataSource

    init(dataSource: MobilityCatalogDataSource = LocalMobilityCatalogDataSource()) {
        self.dataSource = dataSource
    }

    func fetchCatalog() async throws -> MobilityDatasetCatalog {
        try dataSource.loadCatalog()
    }
}
