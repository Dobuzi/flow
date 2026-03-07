import Foundation

struct LocalFlowRepository: FlowRepository {
    private let dataSource: FlowDataSource

    init(dataSource: FlowDataSource = LocalJSONDataSource()) {
        self.dataSource = dataSource
    }

    func fetchDataset() async throws -> FlowDataset {
        try dataSource.loadDatasetManifest()
    }

    func fetchFlowRecords() async throws -> [FlowRecord] {
        let nodes = try dataSource.loadNodes()
        let flows = try dataSource.loadFlows()
        let (validated, droppedCount) = Self.validate(flows: flows, nodes: nodes)

        if droppedCount > 0 {
            FlowLogger.info("Dropped \(droppedCount) invalid flow records during validation")
        }
        return validated
    }

    static func validate(flows: [FlowRecord], nodes: [LocationNode]) -> ([FlowRecord], Int) {
        let validNodeIDs = Set(nodes.map(\.id))
        var droppedCount = 0
        let validated = flows.filter { flow in
            let isValid = flow.originNodeID != flow.destinationNodeID &&
                validNodeIDs.contains(flow.originNodeID) &&
                validNodeIDs.contains(flow.destinationNodeID) &&
                flow.volume >= 0

            if !isValid {
                droppedCount += 1
            }
            return isValid
        }
        return (validated, droppedCount)
    }
}
