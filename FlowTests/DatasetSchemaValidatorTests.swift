import Testing
@testable import Flow

struct DatasetSchemaValidatorTests {
    @Test
    func acceptsCurrentSchemaVersion() {
        let validator = DatasetSchemaValidator()
        let dataset = FlowDataset(
            datasetID: "sample",
            version: "1.0.0",
            source: "test",
            createdAt: "2026-03-07T00:00:00Z",
            spatialLevel: .city,
            timeCoverage: "2025-01",
            recordsCount: 1,
            schemaVersion: "1.0.0"
        )

        let result = validator.validate(dataset: dataset)
        #expect(result.isCompatible)
        #expect(result.reason == nil)
    }

    @Test
    func rejectsUnsupportedSchemaVersion() {
        let validator = DatasetSchemaValidator()
        let dataset = FlowDataset(
            datasetID: "sample",
            version: "1.0.0",
            source: "test",
            createdAt: "2026-03-07T00:00:00Z",
            spatialLevel: .city,
            timeCoverage: "2025-01",
            recordsCount: 1,
            schemaVersion: "2.0.0"
        )

        let result = validator.validate(dataset: dataset)
        #expect(!result.isCompatible)
        #expect(result.reason == "Unsupported schema version")
    }
}
