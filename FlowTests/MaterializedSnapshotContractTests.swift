import Testing
@testable import Flow

struct MaterializedSnapshotContractTests {
    @Test
    func acceptsStructurallyValidContract() {
        let contract = makeValidContract()

        let result = contract.validateStructure()
        #expect(result.isValid)
        #expect(result.reasons.isEmpty)
    }

    @Test
    func rejectsMissingRequiredSnapshotFiles() {
        var contract = makeValidContract()
        contract = MaterializedSnapshotContract(
            snapshotID: contract.snapshotID,
            source: contract.source,
            schemaVersion: contract.schemaVersion,
            datasetVersion: contract.datasetVersion,
            generatedAt: contract.generatedAt,
            timeCoverage: contract.timeCoverage,
            spatialCoverage: contract.spatialCoverage,
            recordsCount: contract.recordsCount,
            requiredFiles: contract.requiredFiles.filter { $0.role != .flows },
            compatibility: contract.compatibility,
            activationEligibility: contract.activationEligibility
        )

        let result = contract.validateStructure()
        #expect(!result.isValid)
        #expect(result.reasons.contains("required_file_missing:flows"))
    }

    @Test
    func rejectsEligibleStateWhenCompatibilityFailed() {
        let contract = MaterializedSnapshotContract(
            snapshotID: "korea_national-2025.1",
            source: .koreaNational,
            schemaVersion: "1.0.0",
            datasetVersion: "2025.1",
            generatedAt: "2025-12-31T00:00:00Z",
            timeCoverage: "2025-01~2025-12",
            spatialCoverage: .province,
            recordsCount: 10,
            requiredFiles: standardRequiredFiles(),
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: false,
                compatibilityReasons: ["required_fields_missing"],
                checkedFields: ["datasetID"]
            ),
            activationEligibility: SnapshotActivationEligibility(state: .eligible, reasons: [])
        )

        let result = contract.validateStructure()
        #expect(!result.isValid)
        #expect(result.reasons.contains("eligible_but_incompatible"))
    }

    @Test
    func buildsContractFromCurrentSnapshotBackedDatasets() async throws {
        let checker = DatasetCompatibilityChecker()
        let sources: [FlowDatasetSource] = [.bundledSample, .seoulCapitalSnapshot, .koreaNational]

        for source in sources {
            let dataset = try await MobilityRepositoryFactory.flowRepository(for: source).fetchDataset()
            let compatibility = checker.evaluate(dataset: dataset, source: source)

            let contract = MaterializedSnapshotContract.from(
                dataset: dataset,
                source: source,
                compatibilityResult: compatibility,
                requiredFiles: standardRequiredFiles()
            )

            let result = contract.validateStructure()
            #expect(result.isValid)
            #expect(contract.source == source)
            #expect(contract.activationEligibility.state == .eligible)
        }
    }

    private func makeValidContract() -> MaterializedSnapshotContract {
        MaterializedSnapshotContract(
            snapshotID: "korea_national-2025.1",
            source: .koreaNational,
            schemaVersion: "1.0.0",
            datasetVersion: "2025.1",
            generatedAt: "2025-12-31T00:00:00Z",
            timeCoverage: "2025-01~2025-12",
            spatialCoverage: .province,
            recordsCount: 100,
            requiredFiles: standardRequiredFiles(),
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: true,
                compatibilityReasons: [],
                checkedFields: ["datasetID", "schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(state: .eligible, reasons: [])
        )
    }

    private func standardRequiredFiles() -> [SnapshotRequiredFile] {
        [
            SnapshotRequiredFile(
                role: .manifest,
                relativePath: "manifest.json",
                checksumSHA256: "abc",
                byteCount: 120,
                recordCount: nil
            ),
            SnapshotRequiredFile(
                role: .nodes,
                relativePath: "nodes.json",
                checksumSHA256: "def",
                byteCount: 820,
                recordCount: 17
            ),
            SnapshotRequiredFile(
                role: .flows,
                relativePath: "flows.jsonl",
                checksumSHA256: "ghi",
                byteCount: 4096,
                recordCount: 300
            )
        ]
    }
}
