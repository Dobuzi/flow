import Foundation

protocol FlowDataSource {
    func loadDatasetManifest() throws -> FlowDataset
    func loadNodes() throws -> [LocationNode]
    func loadFlows() throws -> [FlowRecord]
}
