import Foundation

enum NationalBaselineDataSourceError: Error {
    case notConfigured
}

protocol NationalBaselineMobilityDataSource: FlowDataSource {}

struct NationalBaselinePlaceholderDataSource: NationalBaselineMobilityDataSource {
    func loadDatasetManifest() throws -> FlowDataset {
        throw NationalBaselineDataSourceError.notConfigured
    }

    func loadNodes() throws -> [LocationNode] {
        throw NationalBaselineDataSourceError.notConfigured
    }

    func loadFlows() throws -> [FlowRecord] {
        throw NationalBaselineDataSourceError.notConfigured
    }
}
