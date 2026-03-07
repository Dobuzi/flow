import Foundation

struct FlowRecord: Codable, Identifiable, Hashable {
    struct Metadata: Codable, Hashable {
        let corridorName: String?
        let regionType: String?
        let isPassengerFlow: Bool?
        let isFreightFlow: Bool?
        let confidenceScore: Double?
        let dataSourceTag: String?
    }

    let id: String
    let originNodeID: String
    let destinationNodeID: String
    let transportMode: TransportMode
    let timeBucketID: String
    let volume: Double
    let unitType: UnitType
    let metadata: Metadata?

    enum UnitType: String, Codable, Hashable, CaseIterable {
        case passengers
        case tons
        case vehicles
    }
}
