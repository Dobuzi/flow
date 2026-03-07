import CoreLocation
import Testing
@testable import Flow

struct NationalRenderGuardrailPolicyTests {
    private let policy = NationalRenderGuardrailPolicy()

    @Test
    func nonNationalSourceIsNotCappedByNationalPolicy() {
        let segments = makeSegments(count: 900)
        let result = policy.apply(
            source: .bundledSample,
            spatialLevel: .national,
            segments: segments,
            selectedFlowID: nil
        )

        #expect(result.segments.count == 900)
        #expect(result.truncatedCount == 0)
    }

    @Test
    func koreaNationalIsCappedAtNationalLevelWithTopVolumePriority() {
        let segments = makeSegments(count: 500)
        let result = policy.apply(
            source: .koreaNational,
            spatialLevel: .national,
            segments: segments,
            selectedFlowID: nil
        )

        #expect(result.segments.count == 300)
        #expect(result.truncatedCount == 200)
        #expect(result.segments.first?.volume == 499)
        #expect(result.segments.last?.volume == 200)
    }

    @Test
    func selectedFlowIsPreservedWhenOutsideTopCap() {
        let segments = makeSegments(count: 500)
        let selectedFlowID = "s-10"

        let result = policy.apply(
            source: .koreaNational,
            spatialLevel: .national,
            segments: segments,
            selectedFlowID: selectedFlowID
        )

        #expect(result.segments.count == 300)
        #expect(result.segments.contains(where: { $0.id == selectedFlowID }))
    }

    private func makeSegments(count: Int) -> [RenderableFlowSegment] {
        let origin = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0)
        let destination = CLLocationCoordinate2D(latitude: 35.1, longitude: 129.0)
        return (0..<count).map { idx in
            RenderableFlowSegment(
                id: "s-\(idx)",
                origin: origin,
                destination: destination,
                mode: .road,
                volume: Double(idx),
                normalizedIntensity: 1.0,
                lineWidth: 2.0,
                opacity: 0.8
            )
        }
    }
}
