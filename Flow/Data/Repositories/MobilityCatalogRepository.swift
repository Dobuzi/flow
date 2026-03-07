import Foundation

protocol MobilityCatalogRepository {
    func fetchCatalog() async throws -> MobilityDatasetCatalog
}
