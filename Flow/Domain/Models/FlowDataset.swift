import Foundation

struct FlowDataset: Codable, Hashable {
    let datasetID: String
    let version: String
    let source: String
    let createdAt: String
    let spatialLevel: SpatialLevel
    let timeCoverage: String
    let recordsCount: Int
    let schemaVersion: String
}
