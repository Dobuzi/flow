import Testing
@testable import Flow

struct DatasetCompatibilityCheckerTests {
    @Test
    func marksCurrentSampleAndSeoulDatasetsCompatible() async throws {
        let checker = DatasetCompatibilityChecker()

        let sampleDataset = try await MobilityRepositoryFactory.flowRepository(for: .bundledSample).fetchDataset()
        let sampleResult = checker.evaluate(dataset: sampleDataset, source: .bundledSample)
        #expect(sampleResult.isCompatible)
        #expect(sampleResult.reasons.isEmpty)

        let seoulDataset = try await MobilityRepositoryFactory.flowRepository(for: .seoulCapitalSnapshot).fetchDataset()
        let seoulResult = checker.evaluate(dataset: seoulDataset, source: .seoulCapitalSnapshot)
        #expect(seoulResult.isCompatible)
        #expect(seoulResult.reasons.isEmpty)
    }

    @Test
    func reportsIncompatibilityWithReasonFields() {
        let checker = DatasetCompatibilityChecker()
        let dataset = FlowDataset(
            datasetID: "",
            version: "1.0.0",
            source: "",
            createdAt: "",
            spatialLevel: .city,
            timeCoverage: "2025-01",
            recordsCount: 0,
            schemaVersion: "2.0.0"
        )

        let result = checker.evaluate(dataset: dataset, source: .koreaNational)
        #expect(!result.isCompatible)
        #expect(result.reasons.contains("schema_version_unsupported"))
        #expect(result.reasons.contains("required_fields_missing"))
        #expect(result.missingFields.contains("datasetID"))
        #expect(result.missingFields.contains("source"))
        #expect(result.missingFields.contains("createdAt"))
    }

    @Test
    func appliesCustomRequiredFieldPolicy() {
        let checker = DatasetCompatibilityChecker(
            requiredFieldPolicy: RequiredFieldPolicy(requiredManifestFields: ["datasetID"])
        )

        let dataset = FlowDataset(
            datasetID: "",
            version: "",
            source: "",
            createdAt: "",
            spatialLevel: .city,
            timeCoverage: "2025-01",
            recordsCount: 0,
            schemaVersion: "1.0.0"
        )

        let result = checker.evaluate(dataset: dataset, source: .koreaNational)
        #expect(!result.isCompatible)
        #expect(result.missingFields == ["datasetID"])
        #expect(result.checkedFields == ["datasetID"])
    }
}
