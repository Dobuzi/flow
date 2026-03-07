import Foundation

struct KoreaNationalDatasetManifestDTO: Decodable {
    let datasetId: String
    let version: String
    let source: String
    let generatedAt: String
    let coverageStart: String
    let coverageEnd: String
    let schemaVersion: String
    let spatialLevel: SpatialLevel
}

struct KoreaNationalNodeDTO: Decodable {
    let nodeId: String
    let nameKo: String
    let nameEn: String?
    let lat: Double
    let lon: Double
    let regionCode: String
    let regionType: String
    let importanceRank: Int?
}

struct KoreaNationalFlowMetadataDTO: Decodable {
    let corridorName: String?
    let regionType: String?
    let isPassengerFlow: Bool?
    let isFreightFlow: Bool?
    let confidenceScore: Double?
    let dataSourceTag: String?
}

struct KoreaNationalFlowSnapshotDTO: Decodable {
    let id: String
    let originNodeId: String
    let destinationNodeId: String
    let transportMode: String
    let timeBucketId: String
    let volume: Double
    let unitType: FlowRecord.UnitType
    let metadata: KoreaNationalFlowMetadataDTO?
}
