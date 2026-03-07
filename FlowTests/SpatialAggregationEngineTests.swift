import Testing
@testable import Flow

struct SpatialAggregationEngineTests {
    private let engine = SpatialAggregationEngine()

    @Test
    func nonNationalSourcePassesThroughWithoutAggregation() {
        let nodes = [
            makeNode(id: "11-01", regionCode: "11010", importanceRank: 1),
            makeNode(id: "26-01", regionCode: "26010", importanceRank: 1)
        ]
        let flows = [
            makeFlow(
                id: "f-1",
                originNodeID: "11-01",
                destinationNodeID: "26-01",
                mode: .road,
                bucketID: "M:2025-01",
                volume: 100
            )
        ]

        let result = engine.aggregateForRendering(
            flows: flows,
            nodes: nodes,
            source: .bundledSample,
            requestedSpatialLevel: .national
        )

        #expect(result == flows)
    }

    @Test
    func koreaNationalAggregatesToProvinceBaselineDeterministically() {
        let nodes = [
            makeNode(id: "11-01", regionCode: "11010", importanceRank: 1),
            makeNode(id: "11-02", regionCode: "11020", importanceRank: 3),
            makeNode(id: "26-01", regionCode: "26010", importanceRank: 2)
        ]

        let flows = [
            makeFlow(
                id: "f-1",
                originNodeID: "11-01",
                destinationNodeID: "26-01",
                mode: .road,
                bucketID: "M:2025-01",
                volume: 120
            ),
            makeFlow(
                id: "f-2",
                originNodeID: "11-02",
                destinationNodeID: "26-01",
                mode: .road,
                bucketID: "M:2025-01",
                volume: 80
            )
        ]

        let result = engine.aggregateForRendering(
            flows: flows,
            nodes: nodes,
            source: .koreaNational,
            requestedSpatialLevel: .national
        )

        #expect(result.count == 1)
        #expect(result[0].originNodeID == "11-01")
        #expect(result[0].destinationNodeID == "26-01")
        #expect(result[0].volume == 200)
        #expect(result[0].transportMode == .road)
        #expect(result[0].timeBucketID == "M:2025-01")
        #expect(result[0].unitType == .vehicles)
        #expect(result[0].metadata?.regionType == SpatialLevel.province.rawValue)
    }

    @Test
    func aggregationKeepsModeTimeAndUnitBoundaries() {
        let nodes = [
            makeNode(id: "11-01", regionCode: "11010", importanceRank: 1),
            makeNode(id: "11-02", regionCode: "11020", importanceRank: 2),
            makeNode(id: "26-01", regionCode: "26010", importanceRank: 1)
        ]

        let flows = [
            makeFlow(
                id: "f-road-month",
                originNodeID: "11-01",
                destinationNodeID: "26-01",
                mode: .road,
                bucketID: "M:2025-01",
                volume: 100
            ),
            makeFlow(
                id: "f-road-hour",
                originNodeID: "11-02",
                destinationNodeID: "26-01",
                mode: .road,
                bucketID: "H:2025-01|08",
                volume: 50
            ),
            makeFlow(
                id: "f-rail-month",
                originNodeID: "11-02",
                destinationNodeID: "26-01",
                mode: .rail,
                bucketID: "M:2025-01",
                volume: 70,
                unit: .passengers
            )
        ]

        let result = engine.aggregateForRendering(
            flows: flows,
            nodes: nodes,
            source: .koreaNational,
            requestedSpatialLevel: .national
        )

        #expect(result.count == 3)
        let signatures = Set(
            result.map { flow in
                "\(flow.transportMode.rawValue)|\(flow.timeBucketID)|\(flow.unitType.rawValue)|\(Int(flow.volume))"
            }
        )
        #expect(signatures.contains("road|M:2025-01|vehicles|100"))
        #expect(signatures.contains("road|H:2025-01|08|vehicles|50"))
        #expect(signatures.contains("rail|M:2025-01|passengers|70"))
    }

    private func makeNode(id: String, regionCode: String, importanceRank: Int) -> LocationNode {
        LocationNode(
            id: id,
            nameKo: id,
            nameEn: id,
            lat: 37.0,
            lon: 127.0,
            regionCode: regionCode,
            regionType: "city",
            importanceRank: importanceRank
        )
    }

    private func makeFlow(
        id: String,
        originNodeID: String,
        destinationNodeID: String,
        mode: TransportMode,
        bucketID: String,
        volume: Double,
        unit: FlowRecord.UnitType = .vehicles
    ) -> FlowRecord {
        FlowRecord(
            id: id,
            originNodeID: originNodeID,
            destinationNodeID: destinationNodeID,
            transportMode: mode,
            timeBucketID: bucketID,
            volume: volume,
            unitType: unit,
            metadata: nil
        )
    }
}
