import Foundation

struct SpatialAggregationEngine {
    func aggregateForRendering(
        flows: [FlowRecord],
        nodes: [LocationNode],
        source: FlowDatasetSource,
        requestedSpatialLevel: SpatialLevel
    ) -> [FlowRecord] {
        guard source == .koreaNational else {
            return flows
        }

        let targetLevel = targetLevel(for: requestedSpatialLevel)
        let reduced = aggregate(
            flows: flows,
            nodes: nodes,
            targetLevel: targetLevel
        )
        let capped = applyTopVolumeCap(flows: reduced, targetLevel: targetLevel)
        return capped.sorted {
            if $0.volume == $1.volume {
                return $0.id < $1.id
            }
            return $0.volume > $1.volume
        }
    }

    private func targetLevel(for requested: SpatialLevel) -> SpatialLevel {
        switch requested {
        case .national, .province:
            return .province
        case .city:
            return .city
        case .hub:
            return .hub
        }
    }

    private func aggregate(
        flows: [FlowRecord],
        nodes: [LocationNode],
        targetLevel: SpatialLevel
    ) -> [FlowRecord] {
        guard targetLevel != .hub else { return flows }

        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let representativeByGroup = buildRepresentativeNodes(nodes: nodes, targetLevel: targetLevel)
        var grouped: [AggregationKey: Double] = [:]

        for flow in flows {
            guard
                let originNode = nodesByID[flow.originNodeID],
                let destinationNode = nodesByID[flow.destinationNodeID]
            else {
                continue
            }

            let originGroup = groupID(for: originNode, targetLevel: targetLevel)
            let destinationGroup = groupID(for: destinationNode, targetLevel: targetLevel)

            guard
                let originRepresentative = representativeByGroup[originGroup],
                let destinationRepresentative = representativeByGroup[destinationGroup]
            else {
                continue
            }

            let key = AggregationKey(
                originNodeID: originRepresentative.id,
                destinationNodeID: destinationRepresentative.id,
                mode: flow.transportMode,
                timeBucketID: flow.timeBucketID,
                unitType: flow.unitType
            )
            grouped[key, default: 0] += flow.volume
        }

        return grouped.map { key, totalVolume in
            FlowRecord(
                id: "\(key.timeBucketID)|\(key.originNodeID)|\(key.destinationNodeID)|\(key.mode.rawValue)|\(key.unitType.rawValue)|agg:\(targetLevel.rawValue)",
                originNodeID: key.originNodeID,
                destinationNodeID: key.destinationNodeID,
                transportMode: key.mode,
                timeBucketID: key.timeBucketID,
                volume: totalVolume,
                unitType: key.unitType,
                metadata: FlowRecord.Metadata(
                    corridorName: nil,
                    regionType: targetLevel.rawValue,
                    isPassengerFlow: nil,
                    isFreightFlow: nil,
                    confidenceScore: nil,
                    dataSourceTag: "korea_national_baseline_aggregated"
                )
            )
        }
    }

    private func buildRepresentativeNodes(
        nodes: [LocationNode],
        targetLevel: SpatialLevel
    ) -> [String: LocationNode] {
        var bestByGroup: [String: LocationNode] = [:]
        for node in nodes {
            let group = groupID(for: node, targetLevel: targetLevel)
            if let existing = bestByGroup[group] {
                let existingRank = existing.importanceRank ?? Int.max
                let candidateRank = node.importanceRank ?? Int.max
                if candidateRank < existingRank || (candidateRank == existingRank && node.id < existing.id) {
                    bestByGroup[group] = node
                }
            } else {
                bestByGroup[group] = node
            }
        }
        return bestByGroup
    }

    private func groupID(for node: LocationNode, targetLevel: SpatialLevel) -> String {
        switch targetLevel {
        case .national:
            return "KR"
        case .province:
            return String(node.regionCode.prefix(2))
        case .city:
            if node.regionCode.count >= 5 {
                return String(node.regionCode.prefix(5))
            }
            return node.regionCode
        case .hub:
            return node.id
        }
    }

    private func applyTopVolumeCap(flows: [FlowRecord], targetLevel: SpatialLevel) -> [FlowRecord] {
        let cap: Int
        switch targetLevel {
        case .province:
            cap = 800
        case .city:
            cap = 1_500
        case .hub:
            cap = 2_500
        case .national:
            cap = 800
        }

        guard flows.count > cap else { return flows }
        return flows.sorted { $0.volume > $1.volume }.prefix(cap).map { $0 }
    }
}

private struct AggregationKey: Hashable {
    let originNodeID: String
    let destinationNodeID: String
    let mode: TransportMode
    let timeBucketID: String
    let unitType: FlowRecord.UnitType
}
