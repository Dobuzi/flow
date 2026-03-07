import Foundation

protocol MobilityCatalogDataSource {
    func loadCatalog() throws -> MobilityDatasetCatalog
}
