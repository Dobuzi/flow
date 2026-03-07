import Foundation

struct SeoulCapitalMobilityFlowRepository: FlowRepository {
    private let dataSource: FlowDataSource

    init(dataSource: FlowDataSource = SeoulCapitalMobilityDataSource()) {
        self.dataSource = dataSource
    }

    func fetchDataset() async throws -> FlowDataset {
        try dataSource.loadDatasetManifest()
    }

    func fetchFlowRecords() async throws -> [FlowRecord] {
        let nodes = try dataSource.loadNodes()
        let flows = try dataSource.loadFlows()
        let (validated, droppedCount) = LocalFlowRepository.validate(flows: flows, nodes: nodes)
        if droppedCount > 0 {
            FlowLogger.info("Dropped \(droppedCount) invalid Seoul-capital flow records during validation")
        }
        return validated
    }
}
