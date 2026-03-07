import Foundation

struct DataLayerTests {
    static func runAll() async throws {
        try testSchemaVersionValidation()
        try testFlowValidationDropsInvalidRecords()
        try await testLocalFlowRepositoryReturnsValidatedFlows()
    }

    private static func testSchemaVersionValidation() throws {
        let valid = FlowDataset(
            datasetID: "test",
            version: "2025.01",
            source: "test",
            createdAt: "2025-01-01T00:00:00+09:00",
            spatialLevel: .national,
            timeCoverage: "2025-01",
            recordsCount: 1,
            schemaVersion: "1.0.0"
        )
        try LocalJSONDataSource.validateSchemaVersion(valid)

        let invalid = FlowDataset(
            datasetID: "test",
            version: "2025.01",
            source: "test",
            createdAt: "2025-01-01T00:00:00+09:00",
            spatialLevel: .national,
            timeCoverage: "2025-01",
            recordsCount: 1,
            schemaVersion: "2.0.0"
        )
        do {
            try LocalJSONDataSource.validateSchemaVersion(invalid)
            throw TestFailure("Expected invalid schema version to throw")
        } catch DataSourceError.invalidSchemaVersion(let version) {
            guard version == "2.0.0" else {
                throw TestFailure("Expected schema version 2.0.0, got \(version)")
            }
        }
    }

    private static func testFlowValidationDropsInvalidRecords() throws {
        let nodes = [
            makeNode(id: "A"),
            makeNode(id: "B")
        ]
        let flows = [
            makeFlow(id: "valid", origin: "A", destination: "B", volume: 10),
            makeFlow(id: "same-node", origin: "A", destination: "A", volume: 10),
            makeFlow(id: "unknown-node", origin: "A", destination: "Z", volume: 10),
            makeFlow(id: "negative", origin: "A", destination: "B", volume: -1)
        ]

        let (validated, dropped) = LocalFlowRepository.validate(flows: flows, nodes: nodes)
        guard validated.map(\.id) == ["valid"] else {
            throw TestFailure("Expected only valid flow to remain")
        }
        guard dropped == 3 else {
            throw TestFailure("Expected 3 dropped records, got \(dropped)")
        }
    }

    private static func testLocalFlowRepositoryReturnsValidatedFlows() async throws {
        let mock = MockDataSource(
            dataset: FlowDataset(
                datasetID: "test",
                version: "2025.01",
                source: "test",
                createdAt: "2025-01-01T00:00:00+09:00",
                spatialLevel: .national,
                timeCoverage: "2025-01",
                recordsCount: 2,
                schemaVersion: "1.0.0"
            ),
            nodes: [makeNode(id: "A"), makeNode(id: "B")],
            flows: [
                makeFlow(id: "keep", origin: "A", destination: "B", volume: 12),
                makeFlow(id: "drop", origin: "A", destination: "Z", volume: 8)
            ]
        )

        let repository = LocalFlowRepository(dataSource: mock)
        let flows = try await repository.fetchFlowRecords()
        guard flows.count == 1, flows.first?.id == "keep" else {
            throw TestFailure("Expected repository to return only validated records")
        }
    }

    private static func makeNode(id: String) -> LocationNode {
        LocationNode(
            id: id,
            nameKo: id,
            nameEn: id,
            lat: 37.0,
            lon: 127.0,
            regionCode: "11",
            regionType: "city",
            importanceRank: 1
        )
    }

    private static func makeFlow(id: String, origin: String, destination: String, volume: Double) -> FlowRecord {
        FlowRecord(
            id: id,
            originNodeID: origin,
            destinationNodeID: destination,
            transportMode: .road,
            timeBucketID: "M:2025-01",
            volume: volume,
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

private struct MockDataSource: FlowDataSource {
    let dataset: FlowDataset
    let nodes: [LocationNode]
    let flows: [FlowRecord]

    func loadDatasetManifest() throws -> FlowDataset { dataset }
    func loadNodes() throws -> [LocationNode] { nodes }
    func loadFlows() throws -> [FlowRecord] { flows }
}
