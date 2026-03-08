import Testing
@testable import Flow

struct DatasetVersionStoreTests {
    @Test
    func storesAndIndexesBySource() async {
        let store = InMemoryDatasetVersionStore()

        await store.upsert(
            contract: makeContract(source: .bundledSample, snapshotID: "sample-2025.01", datasetVersion: "2025.01", generatedAt: "2025-01-01T00:00:00Z"),
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: "2026-03-08T00:00:00Z"
        )
        await store.upsert(
            contract: makeContract(source: .koreaNational, snapshotID: "national-2026.01", datasetVersion: "2026.01", generatedAt: "2026-01-01T00:00:00Z"),
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: "2026-03-08T00:01:00Z"
        )

        let sampleVersions = await store.versions(for: .bundledSample)
        let nationalVersions = await store.versions(for: .koreaNational)
        #expect(sampleVersions.count == 1)
        #expect(nationalVersions.count == 1)
        #expect(nationalVersions.first?.snapshotID == "national-2026.01")
    }

    @Test
    func latestLookupUsesDeterministicOrdering() async {
        let store = InMemoryDatasetVersionStore()

        await store.upsert(
            contract: makeContract(source: .koreaNational, snapshotID: "national-2026.01", datasetVersion: "2026.01", generatedAt: "2026-01-01T00:00:00Z"),
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: "2026-03-08T00:01:00Z"
        )
        await store.upsert(
            contract: makeContract(source: .koreaNational, snapshotID: "national-2026.02", datasetVersion: "2026.02", generatedAt: "2026-02-01T00:00:00Z"),
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: "2026-03-08T00:02:00Z"
        )

        let latest = await store.latest(for: .koreaNational)
        #expect(latest?.snapshotID == "national-2026.02")
    }

    @Test
    func supportsLookupBySnapshotIDAndDatasetVersion() async {
        let store = InMemoryDatasetVersionStore()
        let contract = makeContract(
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2025.10",
            datasetVersion: "2025.10",
            generatedAt: "2025-10-01T00:00:00Z"
        )

        await store.upsert(
            contract: contract,
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: "2026-03-08T00:00:00Z"
        )

        let bySnapshotID = await store.snapshot(snapshotID: "seoul-2025.10")
        let byDatasetVersion = await store.snapshot(source: .seoulCapitalSnapshot, datasetVersion: "2025.10")
        #expect(bySnapshotID?.snapshotID == "seoul-2025.10")
        #expect(byDatasetVersion?.datasetVersion == "2025.10")
    }

    @Test
    func preservesActivationEligibilityAndCompatibilityClassification() async {
        let store = InMemoryDatasetVersionStore()
        let ineligible = makeContract(
            source: .koreaNational,
            snapshotID: "national-bad",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-01T00:00:00Z",
            activationState: .ineligible,
            activationReasons: ["required_fields_missing"]
        )

        await store.upsert(
            contract: ineligible,
            compatibilityClassification: .partiallyCompatible,
            isIngestionCandidate: true,
            indexedAt: "2026-03-08T00:00:00Z"
        )

        let entry = await store.snapshot(snapshotID: "national-bad")
        #expect(entry?.activationEligibility.state == .ineligible)
        #expect(entry?.compatibilityClassification == .partiallyCompatible)
    }

    private func makeContract(
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        generatedAt: String,
        activationState: SnapshotActivationEligibility.State = .eligible,
        activationReasons: [String] = []
    ) -> MaterializedSnapshotContract {
        MaterializedSnapshotContract(
            snapshotID: snapshotID,
            source: source,
            schemaVersion: "1.0.0",
            datasetVersion: datasetVersion,
            generatedAt: generatedAt,
            timeCoverage: "2026-01~2026-12",
            spatialCoverage: .province,
            recordsCount: 100,
            requiredFiles: [
                SnapshotRequiredFile(role: .manifest, relativePath: "manifest.json", checksumSHA256: "m", byteCount: 10, recordCount: nil),
                SnapshotRequiredFile(role: .nodes, relativePath: "nodes.json", checksumSHA256: "n", byteCount: 20, recordCount: 2),
                SnapshotRequiredFile(role: .flows, relativePath: "flows.jsonl", checksumSHA256: "f", byteCount: 30, recordCount: 1)
            ],
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: activationState == .eligible,
                compatibilityReasons: activationReasons,
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(
                state: activationState,
                reasons: activationReasons
            )
        )
    }
}
