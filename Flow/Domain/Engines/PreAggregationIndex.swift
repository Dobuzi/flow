import Foundation

struct PreAggregationKey: Hashable {
    let timeBucketID: String
    let mode: TransportMode
    let spatialLevel: SpatialLevel
    let unitType: FlowRecord.UnitType
}

struct PreAggregationIndex {
    private let buckets: [PreAggregationKey: [FlowRecord]]

    init(flows: [FlowRecord]) {
        var store: [PreAggregationKey: [FlowRecord]] = [:]
        let levels = SpatialLevel.allCases

        for flow in flows {
            for level in levels {
                let key = PreAggregationKey(
                    timeBucketID: flow.timeBucketID,
                    mode: flow.transportMode,
                    spatialLevel: level,
                    unitType: flow.unitType
                )
                store[key, default: []].append(flow)
            }
        }
        self.buckets = store
    }

    func flows(
        timeBucketID: String,
        modes: Set<TransportMode>,
        spatialLevel: SpatialLevel
    ) -> [FlowRecord] {
        guard !modes.isEmpty else { return [] }
        var result: [FlowRecord] = []
        for mode in modes {
            for unit in FlowRecord.UnitType.allCases {
                let key = PreAggregationKey(
                    timeBucketID: timeBucketID,
                    mode: mode,
                    spatialLevel: spatialLevel,
                    unitType: unit
                )
                if let chunk = buckets[key] {
                    result.append(contentsOf: chunk)
                }
            }
        }
        return result
    }
}
