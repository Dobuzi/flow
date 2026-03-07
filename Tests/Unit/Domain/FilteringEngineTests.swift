import Foundation

struct FilteringEngineTests {
    static func runAll() throws {
        try testModeFiltering()
        try testGeographyFiltering()
    }

    private static func testModeFiltering() throws {
        let engine = FilteringEngine()
        let nodes = [makeNode(id: "A", region: "11"), makeNode(id: "B", region: "26")]
        let flows = [
            makeFlow(id: "r", mode: .road, origin: "A", destination: "B"),
            makeFlow(id: "a", mode: .air, origin: "A", destination: "B")
        ]
        let filtered = engine.filter(
            flows: flows,
            nodes: nodes,
            criteria: FlowFilterCriteria(modes: [.road], allowedRegionCodes: nil, minimumVolume: nil)
        )
        guard filtered.count == 1, filtered.first?.id == "r" else {
            throw TestFailure("Expected only road flow")
        }
    }

    private static func testGeographyFiltering() throws {
        let engine = FilteringEngine()
        let nodes = [makeNode(id: "A", region: "11"), makeNode(id: "B", region: "26"), makeNode(id: "C", region: "27")]
        let flows = [
            makeFlow(id: "ab", mode: .road, origin: "A", destination: "B"),
            makeFlow(id: "ac", mode: .road, origin: "A", destination: "C")
        ]
        let filtered = engine.filter(
            flows: flows,
            nodes: nodes,
            criteria: FlowFilterCriteria(modes: [.road], allowedRegionCodes: ["26"], minimumVolume: nil)
        )
        guard filtered.count == 1, filtered.first?.id == "ab" else {
            throw TestFailure("Expected only region-matching flow")
        }
    }

    private static func makeNode(id: String, region: String) -> LocationNode {
        LocationNode(
            id: id,
            nameKo: id,
            nameEn: id,
            lat: 37,
            lon: 127,
            regionCode: region,
            regionType: "city",
            importanceRank: nil
        )
    }

    private static func makeFlow(id: String, mode: TransportMode, origin: String, destination: String) -> FlowRecord {
        FlowRecord(
            id: id,
            originNodeID: origin,
            destinationNodeID: destination,
            transportMode: mode,
            timeBucketID: "M:2025-01",
            volume: 1,
            unitType: .vehicles,
            metadata: nil
        )
    }
}

private struct TestFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
