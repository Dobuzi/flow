import Testing
@testable import Flow

struct SnapshotActivationPolicyTests {
    @Test
    func selectsLatestActivatableCandidate() async throws {
        let store = InMemoryDatasetVersionStore()
        await seed(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.01",
            datasetVersion: "2026.01",
            generatedAt: "2026-01-01T00:00:00Z",
            compatibility: .compatible,
            activationState: .eligible
        )
        await seed(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.02",
            datasetVersion: "2026.02",
            generatedAt: "2026-02-01T00:00:00Z",
            compatibility: .compatible,
            activationState: .eligible
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let decision = await policy.evaluateActivation(source: .koreaNational, requestedSnapshotID: nil)
        #expect(decision.status == .activatable)
        #expect(decision.candidate?.snapshotID == "national-2026.02")
    }

    @Test
    func doesNotPromotePartiallyCompatibleOverKnownGood() async throws {
        let store = InMemoryDatasetVersionStore()
        await seed(
            store: store,
            source: .koreaNational,
            snapshotID: "national-good",
            datasetVersion: "2026.01",
            generatedAt: "2026-01-01T00:00:00Z",
            compatibility: .compatible,
            activationState: .eligible
        )
        await seed(
            store: store,
            source: .koreaNational,
            snapshotID: "national-partial",
            datasetVersion: "2026.02",
            generatedAt: "2026-02-01T00:00:00Z",
            compatibility: .partiallyCompatible,
            activationState: .ineligible,
            activationReasons: ["required_fields_missing"]
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let state = try await policy.activate(source: .koreaNational, requestedSnapshotID: nil)
        #expect(state.activeSnapshotID == "national-good")
    }

    @Test
    func preservesLastKnownGoodOnSuccessfulActivation() async throws {
        let store = InMemoryDatasetVersionStore()
        await seed(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.01",
            datasetVersion: "2026.01",
            generatedAt: "2026-01-01T00:00:00Z",
            compatibility: .compatible,
            activationState: .eligible
        )
        await seed(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.02",
            datasetVersion: "2026.02",
            generatedAt: "2026-02-01T00:00:00Z",
            compatibility: .compatible,
            activationState: .eligible
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        _ = try await policy.activate(source: .koreaNational, requestedSnapshotID: "national-2026.01")
        let second = try await policy.activate(source: .koreaNational, requestedSnapshotID: "national-2026.02")

        #expect(second.activeSnapshotID == "national-2026.02")
        #expect(second.lastKnownGoodSnapshotID == "national-2026.01")
    }

    @Test
    func rollbackSelectsLastKnownGoodTarget() async throws {
        let store = InMemoryDatasetVersionStore()
        await seed(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.01",
            datasetVersion: "2026.01",
            generatedAt: "2026-01-01T00:00:00Z",
            compatibility: .compatible,
            activationState: .eligible
        )
        await seed(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.02",
            datasetVersion: "2026.02",
            generatedAt: "2026-02-01T00:00:00Z",
            compatibility: .compatible,
            activationState: .eligible
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        _ = try await policy.activate(source: .koreaNational, requestedSnapshotID: "national-2026.01")
        _ = try await policy.activate(source: .koreaNational, requestedSnapshotID: "national-2026.02")

        let rollbackDecision = await policy.evaluateRollback(source: .koreaNational)
        #expect(rollbackDecision.status == .rollbackAvailable)
        #expect(rollbackDecision.target?.snapshotID == "national-2026.01")

        let rolledBack = try await policy.rollback(source: .koreaNational)
        #expect(rolledBack.activeSnapshotID == "national-2026.01")
        #expect(rolledBack.lastKnownGoodSnapshotID == "national-2026.02")
    }

    @Test
    func noSafeRollbackIsExplicit() async throws {
        let store = InMemoryDatasetVersionStore()
        await seed(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.01",
            datasetVersion: "2026.01",
            generatedAt: "2026-01-01T00:00:00Z",
            compatibility: .compatible,
            activationState: .eligible
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        _ = try await policy.activate(source: .koreaNational, requestedSnapshotID: "national-2026.01")
        let decision = await policy.evaluateRollback(source: .koreaNational)
        #expect(decision.status == .noSafeRollback)
    }

    private func seed(
        store: InMemoryDatasetVersionStore,
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        generatedAt: String,
        compatibility: IngestionCompatibilityClassification,
        activationState: SnapshotActivationEligibility.State,
        activationReasons: [String] = []
    ) async {
        let contract = MaterializedSnapshotContract(
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
                isSchemaCompatible: compatibility != .incompatible,
                isCompatibilityCheckPassed: compatibility == .compatible,
                compatibilityReasons: activationReasons,
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(
                state: activationState,
                reasons: activationReasons
            )
        )

        await store.upsert(
            contract: contract,
            compatibilityClassification: compatibility,
            isIngestionCandidate: true,
            indexedAt: "2026-03-08T00:00:00Z"
        )
    }
}
