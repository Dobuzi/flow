import Testing
@testable import Flow

struct SnapshotActivationStateProjectorTests {
    @Test
    func projectionWorksWithEmptyHistory() async {
        let versionStore = InMemoryDatasetVersionStore()
        let activationPolicy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: activationPolicy,
            historyStore: historyStore,
            versionStore: versionStore,
            nowProvider: { "2026-03-12T00:00:00Z" }
        )

        let projected = await projector.project(for: .seoulCapitalSnapshot)

        #expect(projected.status == .noHistory)
        #expect(projected.hasActivationHistory == false)
        #expect(projected.activeSnapshotID == nil)
        #expect(projected.latestActivationEvent == nil)
        #expect(projected.latestPromoteOutcome == .none)
    }

    @Test
    func projectionReflectsActiveAndLastKnownGoodPolicyState() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.02",
            datasetVersion: "2026.02",
            generatedAt: "2026-03-02T00:00:00Z"
        )

        let activationPolicy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await activationPolicy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.02")
        _ = try await activationPolicy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: activationPolicy,
            historyStore: historyStore,
            versionStore: versionStore
        )

        let projected = await projector.project(for: .seoulCapitalSnapshot)

        #expect(projected.activeSnapshotID == "seoul-2026.03")
        #expect(projected.lastKnownGoodSnapshotID == "seoul-2026.02")
        #expect(projected.rollbackAvailable == true)
        #expect(projected.status == .activeRollbackReady)
    }

    @Test
    func projectionIncorporatesLatestHistoryEventAndPromoteOutcome() async {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            generatedAt: "2026-03-04T00:00:00Z"
        )

        let activationPolicy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        let historyStore = InMemorySnapshotActivationHistoryStore()

        let blockedCommand = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.05",
                context: .init(
                    commandID: "cmd-promote-blocked",
                    requestedAt: "2026-03-12T01:00:00Z",
                    trigger: .operatorManual
                )
            )
        )
        let blockedDecision = SnapshotActivationGuardInput(
            command: blockedCommand,
            isLiveCapable: true,
            activationDecision: SnapshotActivationDecision(
                source: .seoulCapitalSnapshot,
                requestedSnapshotID: "seoul-2026.05",
                status: .snapshotNotFound,
                candidate: nil,
                reasons: ["snapshot_not_found"]
            )
        ).baselineDecision()

        await historyStore.append(
            SnapshotActivationHistoryEvent.fromGuardDecision(
                blockedDecision,
                eventID: "evt-blocked",
                timestamp: "2026-03-12T01:00:01Z"
            )
        )

        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: activationPolicy,
            historyStore: historyStore,
            versionStore: versionStore,
            nowProvider: { "2026-03-12T01:00:02Z" }
        )

        let projected = await projector.project(for: .seoulCapitalSnapshot)

        #expect(projected.latestActivationEvent?.eventID == "evt-blocked")
        #expect(projected.latestPromoteOutcome == .blocked)
        #expect(projected.status == .attentionRequired)
        #expect(projected.hasActivationHistory == true)
    }

    @Test
    func projectionIncludesLatestCandidateMetadataSafely() async {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .koreaNational,
            snapshotID: "national-2026.04",
            datasetVersion: "2026.04",
            generatedAt: "2026-03-04T00:00:00Z",
            compatibility: .partiallyCompatible,
            activationState: .ineligible,
            activationReasons: ["required_fields_missing"]
        )

        let activationPolicy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: activationPolicy,
            historyStore: historyStore,
            versionStore: versionStore
        )

        let projected = await projector.project(for: .koreaNational)

        #expect(projected.latestCandidateSnapshotID == "national-2026.04")
        #expect(projected.latestCandidateDatasetVersion == "2026.04")
        #expect(projected.latestCandidateCompatibility == .partiallyCompatible)
        #expect(projected.latestCandidateEligibleForActivation == false)
        #expect(projected.status == .noHistory)
    }

    @Test
    func rollbackAvailabilityProjectionIsCorrectWhenNoLastKnownGood() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )

        let activationPolicy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await activationPolicy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: activationPolicy,
            historyStore: historyStore,
            versionStore: versionStore
        )

        let projected = await projector.project(for: .seoulCapitalSnapshot)

        #expect(projected.activeSnapshotID == "seoul-2026.03")
        #expect(projected.lastKnownGoodSnapshotID == nil)
        #expect(projected.rollbackAvailable == false)
        #expect(projected.status == .active)
    }

    private func seedVersion(
        store: InMemoryDatasetVersionStore,
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        generatedAt: String,
        compatibility: IngestionCompatibilityClassification = .compatible,
        activationState: SnapshotActivationEligibility.State = .eligible,
        activationReasons: [String] = []
    ) async {
        let contract = MaterializedSnapshotContract(
            snapshotID: snapshotID,
            source: source,
            schemaVersion: "1.0.0",
            datasetVersion: datasetVersion,
            generatedAt: generatedAt,
            timeCoverage: "2026-03-01~2026-03-31",
            spatialCoverage: .city,
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
            indexedAt: generatedAt
        )
    }
}
