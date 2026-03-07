import Foundation

struct LocalLocationRepository: LocationRepository {
    private let dataSource: FlowDataSource

    init(dataSource: FlowDataSource = LocalJSONDataSource()) {
        self.dataSource = dataSource
    }

    func fetchLocationNodes() async throws -> [LocationNode] {
        try dataSource.loadNodes()
    }
}
