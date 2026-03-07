import Foundation

protocol FlowRepository {
    func fetchDataset() async throws -> FlowDataset
    func fetchFlowRecords() async throws -> [FlowRecord]
}
