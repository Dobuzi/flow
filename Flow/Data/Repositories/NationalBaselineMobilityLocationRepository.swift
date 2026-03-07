import Foundation

struct NationalBaselineMobilityLocationRepository: LocationRepository {
    private let dataSource: NationalBaselineMobilityDataSource

    init(dataSource: NationalBaselineMobilityDataSource = NationalBaselinePlaceholderDataSource()) {
        self.dataSource = dataSource
    }

    func fetchLocationNodes() async throws -> [LocationNode] {
        try dataSource.loadNodes()
    }
}
