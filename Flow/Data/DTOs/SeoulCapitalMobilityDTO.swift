import Foundation

struct SeoulCapitalDatasetManifestDTO: Decodable {
    let datasetId: String
    let version: String
    let source: String
    let generatedAt: String
    let coverageStart: String
    let coverageEnd: String
    let schemaVersion: String
}

struct SeoulCapitalZoneDTO: Decodable {
    let zoneId: String
    let zoneNameKo: String
    let zoneNameEn: String?
    let latitude: Double
    let longitude: Double
    let sidoCode: String
    let regionType: String
    let importanceRank: Int?
}

struct SeoulCapitalFlowSnapshotDTO: Decodable {
    let date: String
    let hour: Int
    let originZoneId: String
    let destinationZoneId: String
    let transportMode: String
    let movementCount: Double
    let dataSourceTag: String?
    let confidenceScore: Double?
}
