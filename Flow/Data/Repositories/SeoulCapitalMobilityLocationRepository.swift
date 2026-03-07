import Foundation

struct SeoulCapitalMobilityLocationRepository: LocationRepository {
    private let dataSource: FlowDataSource

    init(dataSource: FlowDataSource = SeoulCapitalMobilityDataSource()) {
        self.dataSource = dataSource
    }

    func fetchLocationNodes() async throws -> [LocationNode] {
        try dataSource.loadNodes()
    }
}
