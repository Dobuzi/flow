import Foundation
import Testing
@testable import Flow

struct ComputeInsightsUseCaseTests {
    private let useCase = ComputeInsightsUseCase()

    @Test
    func koreaNationalSummaryIncludesRenderGuardrailMetadata() {
        let nodes = makeProvinceNodes(count: 17)
        let flows = makeNationalFlows(nodes: nodes, modes: [.road, .rail], bucketID: "H:2025-01|12")

        var state = AppState()
        state.selectedDatasetSource = .koreaNational
        state.spatialLevel = .national
        state.selectedYear = 2025
        state.selectedMonth = 1
        state.selectedHour = 12
        state.selectedModes = [.road, .rail]

        let summary = useCase.execute(
            datasetVersion: "2025.03",
            source: .koreaNational,
            flows: flows,
            nodes: nodes,
            state: state
        )

        #expect(summary.totalFlowCount == 578)
        #expect(summary.scopedFlowCount == 578)
        #expect(summary.renderableFlowCount == 300)
        #expect(summary.renderGuardrailTruncatedCount == 278)
        #expect(summary.modeShare.map(\.count) == [289, 289])
        #expect(summary.topCorridors.isEmpty == false)
    }

    @Test
    func nonNationalSummaryDoesNotApplyRenderGuardrail() {
        let nodes = [
            LocationNode(id: "n1", nameKo: "서울", nameEn: "Seoul", lat: 37.56, lon: 126.97, regionCode: "11010", regionType: "city", importanceRank: 1),
            LocationNode(id: "n2", nameKo: "부산", nameEn: "Busan", lat: 35.18, lon: 129.07, regionCode: "26010", regionType: "city", importanceRank: 1)
        ]
        let flows = [
            FlowRecord(id: "f1", originNodeID: "n1", destinationNodeID: "n2", transportMode: .road, timeBucketID: "H:2025-01|12", volume: 100, unitType: .vehicles, metadata: nil),
            FlowRecord(id: "f2", originNodeID: "n2", destinationNodeID: "n1", transportMode: .rail, timeBucketID: "H:2025-01|12", volume: 80, unitType: .passengers, metadata: nil),
            FlowRecord(id: "f3", originNodeID: "n1", destinationNodeID: "n1", transportMode: .road, timeBucketID: "H:2025-01|12", volume: 40, unitType: .vehicles, metadata: nil)
        ]

        var state = AppState()
        state.selectedDatasetSource = .bundledSample
        state.selectedModes = [.road, .rail]
        state.selectedYear = 2025
        state.selectedMonth = 1
        state.selectedHour = 12
        state.spatialLevel = .national

        let summary = useCase.execute(
            datasetVersion: "sample-v1",
            source: .bundledSample,
            flows: flows,
            nodes: nodes,
            state: state
        )

        #expect(summary.scopedFlowCount == 3)
        #expect(summary.renderableFlowCount == 3)
        #expect(summary.renderGuardrailTruncatedCount == 0)
    }

    private func makeProvinceNodes(count: Int) -> [LocationNode] {
        (0..<count).map { idx in
            let code = String(format: "%02d010", idx + 1)
            return LocationNode(
                id: "p-\(idx)",
                nameKo: "지역\(idx + 1)",
                nameEn: "Region \(idx + 1)",
                lat: 33.0 + Double(idx) * 0.2,
                lon: 125.0 + Double(idx) * 0.2,
                regionCode: code,
                regionType: "province",
                importanceRank: 1
            )
        }
    }

    private func makeNationalFlows(
        nodes: [LocationNode],
        modes: [TransportMode],
        bucketID: String
    ) -> [FlowRecord] {
        var flows: [FlowRecord] = []
        var ordinal = 1.0

        for origin in nodes {
            for destination in nodes {
                for mode in modes {
                    flows.append(
                        FlowRecord(
                            id: "f-\(flows.count + 1)",
                            originNodeID: origin.id,
                            destinationNodeID: destination.id,
                            transportMode: mode,
                            timeBucketID: bucketID,
                            volume: ordinal,
                            unitType: .vehicles,
                            metadata: nil
                        )
                    )
                    ordinal += 1.0
                }
            }
        }
        return flows
    }
}
