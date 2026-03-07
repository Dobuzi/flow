import Foundation

enum MobilityAggregationStrategy: String, Codable, Hashable {
    case rawFlows
    case totalVolume
    case topFlows
}

struct MobilityAggregation: Codable, Hashable {
    let strategy: MobilityAggregationStrategy
    let limit: Int?

    static let `default` = MobilityAggregation(strategy: .rawFlows, limit: nil)
}

struct MobilityTimeContext: Codable, Hashable {
    let year: Int
    let month: Int?
    let hour: Int?
    let granularity: TimeBucket.Granularity
}

struct MobilityQuery: Codable, Hashable {
    let sources: Set<FlowDatasetSource>
    let selectedModes: Set<TransportMode>
    let spatialLevel: SpatialLevel
    let timeContext: MobilityTimeContext
    let aggregation: MobilityAggregation

    static let `default` = MobilityQuery(
        sources: [.bundledSample],
        selectedModes: Set(TransportMode.allCases),
        spatialLevel: .national,
        timeContext: MobilityTimeContext(year: 2025, month: 1, hour: 12, granularity: .hourOfDay),
        aggregation: .default
    )
}
