import Foundation

struct NationalBaselineMobilityFlowRepository: FlowRepository {
    private let dataSource: NationalBaselineMobilityDataSource

    init(dataSource: NationalBaselineMobilityDataSource = NationalBaselineSnapshotDataSource()) {
        self.dataSource = dataSource
    }

    func fetchDataset() async throws -> FlowDataset {
        try dataSource.loadDatasetManifest()
    }

    func fetchFlowRecords() async throws -> [FlowRecord] {
        try dataSource.loadFlows()
    }
}
