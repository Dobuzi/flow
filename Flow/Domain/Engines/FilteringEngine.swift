import Foundation

struct FlowFilterCriteria {
    let modes: Set<TransportMode>
    let allowedRegionCodes: Set<String>?
    let minimumVolume: Double?
}

struct FilteringEngine {
    func filter(
        flows: [FlowRecord],
        nodes: [LocationNode],
        criteria: FlowFilterCriteria
    ) -> [FlowRecord] {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return flows.filter { flow in
            guard criteria.modes.contains(flow.transportMode) else {
                return false
            }

            if let minVolume = criteria.minimumVolume, flow.volume < minVolume {
                return false
            }

            if let regionCodes = criteria.allowedRegionCodes {
                guard
                    let originCode = nodesByID[flow.originNodeID]?.regionCode,
                    let destinationCode = nodesByID[flow.destinationNodeID]?.regionCode
                else {
                    return false
                }
                guard regionCodes.contains(originCode) || regionCodes.contains(destinationCode) else {
                    return false
                }
            }

            return true
        }
    }
}
