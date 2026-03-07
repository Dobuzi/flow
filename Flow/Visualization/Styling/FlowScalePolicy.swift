import Foundation

enum FlowScalePolicy {
    static func apply(to segments: [RenderableFlowSegment]) -> [RenderableFlowSegment] {
        guard !segments.isEmpty else {
            return []
        }

        let sortedByVolume = segments.sorted { $0.volume < $1.volume }
        let p10 = percentile(sortedByVolume.map(\.volume), p: 0.10)
        let p50 = percentile(sortedByVolume.map(\.volume), p: 0.50)
        let p90 = percentile(sortedByVolume.map(\.volume), p: 0.90)

        let top150IDs = Set(
            segments
                .sorted { $0.volume > $1.volume }
                .prefix(150)
                .map(\.id)
        )

        return segments.compactMap { segment in
            let shouldRender = segment.normalizedIntensity >= 0.03 || top150IDs.contains(segment.id)
            guard shouldRender else {
                return nil
            }

            return RenderableFlowSegment(
                id: segment.id,
                origin: segment.origin,
                destination: segment.destination,
                mode: segment.mode,
                volume: segment.volume,
                normalizedIntensity: segment.normalizedIntensity,
                lineWidth: lineWidth(for: segment.volume, p10: p10, p50: p50, p90: p90),
                opacity: opacity(for: segment.normalizedIntensity)
            )
        }
    }

    private static func percentile(_ sortedValues: [Double], p: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        if sortedValues.count == 1 { return sortedValues[0] }

        let clampedP = min(max(p, 0), 1)
        let rawIndex = Double(sortedValues.count - 1) * clampedP
        let lower = Int(floor(rawIndex))
        let upper = Int(ceil(rawIndex))
        if lower == upper {
            return sortedValues[lower]
        }

        let fraction = rawIndex - Double(lower)
        return sortedValues[lower] + (sortedValues[upper] - sortedValues[lower]) * fraction
    }

    private static func lineWidth(for volume: Double, p10: Double, p50: Double, p90: Double) -> Double {
        if volume <= p10 {
            return 1.0
        }
        if volume <= p50 {
            return interpolate(value: volume, fromLow: p10, fromHigh: p50, toLow: 1.0, toHigh: 2.5)
        }
        if volume <= p90 {
            return interpolate(value: volume, fromLow: p50, fromHigh: p90, toLow: 2.5, toHigh: 5.0)
        }
        return 6.0
    }

    private static func opacity(for normalizedIntensity: Double) -> Double {
        let clamped = min(max(normalizedIntensity, 0), 1)
        return 0.2 + (0.9 - 0.2) * clamped
    }

    private static func interpolate(
        value: Double,
        fromLow: Double,
        fromHigh: Double,
        toLow: Double,
        toHigh: Double
    ) -> Double {
        guard fromHigh > fromLow else {
            return toHigh
        }
        let ratio = min(max((value - fromLow) / (fromHigh - fromLow), 0), 1)
        return toLow + (toHigh - toLow) * ratio
    }
}
