import Foundation

struct NationalRenderGuardrailResult {
    let segments: [RenderableFlowSegment]
    let truncatedCount: Int
}

struct NationalFlowRenderGuardrailResult {
    let flows: [FlowRecord]
    let truncatedCount: Int
}

struct NationalRenderGuardrailPolicy {
    func apply(
        source: FlowDatasetSource,
        spatialLevel: SpatialLevel,
        segments: [RenderableFlowSegment],
        selectedFlowID: String?
    ) -> NationalRenderGuardrailResult {
        guard source == .koreaNational else {
            return NationalRenderGuardrailResult(segments: segments, truncatedCount: 0)
        }

        let cap = capCount(for: spatialLevel)
        guard segments.count > cap else {
            return NationalRenderGuardrailResult(segments: segments, truncatedCount: 0)
        }

        let sorted = segments.sorted {
            if $0.volume == $1.volume {
                return $0.id < $1.id
            }
            return $0.volume > $1.volume
        }

        var kept = Array(sorted.prefix(cap))
        if
            let selectedFlowID,
            !kept.contains(where: { $0.id == selectedFlowID }),
            let selectedSegment = segments.first(where: { $0.id == selectedFlowID })
        {
            kept.removeLast()
            kept.append(selectedSegment)
            kept.sort {
                if $0.volume == $1.volume {
                    return $0.id < $1.id
                }
                return $0.volume > $1.volume
            }
        }

        return NationalRenderGuardrailResult(
            segments: kept,
            truncatedCount: max(segments.count - kept.count, 0)
        )
    }

    func applyToFlows(
        source: FlowDatasetSource,
        spatialLevel: SpatialLevel,
        flows: [FlowRecord],
        selectedFlowID: String?
    ) -> NationalFlowRenderGuardrailResult {
        guard source == .koreaNational else {
            return NationalFlowRenderGuardrailResult(flows: flows, truncatedCount: 0)
        }

        let cap = capCount(for: spatialLevel)
        guard flows.count > cap else {
            return NationalFlowRenderGuardrailResult(flows: flows, truncatedCount: 0)
        }

        let sorted = flows.sorted {
            if $0.volume == $1.volume {
                return $0.id < $1.id
            }
            return $0.volume > $1.volume
        }

        var kept = Array(sorted.prefix(cap))
        if
            let selectedFlowID,
            !kept.contains(where: { $0.id == selectedFlowID }),
            let selectedFlow = flows.first(where: { $0.id == selectedFlowID })
        {
            kept.removeLast()
            kept.append(selectedFlow)
            kept.sort {
                if $0.volume == $1.volume {
                    return $0.id < $1.id
                }
                return $0.volume > $1.volume
            }
        }

        return NationalFlowRenderGuardrailResult(
            flows: kept,
            truncatedCount: max(flows.count - kept.count, 0)
        )
    }

    private func capCount(for spatialLevel: SpatialLevel) -> Int {
        switch spatialLevel {
        case .national:
            return 300
        case .province:
            return 600
        case .city:
            return 1_200
        case .hub:
            return 2_000
        }
    }
}
