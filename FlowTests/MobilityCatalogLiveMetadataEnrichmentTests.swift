import Testing
@testable import Flow

struct MobilityCatalogLiveMetadataEnrichmentTests {
    @Test
    func enrichesLiveMetadataFromVersionStoreAndActivationState() async throws {
        let store = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        await seed(
            store: store,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-08T00:00:00Z",
            indexedAt: "2026-03-08T01:00:00Z"
        )

        await refreshStateStore.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-08T01:00:00Z",
                finishedAt: "2026-03-08T01:01:00Z",
                storedSnapshotID: "seoul-2026.03",
                storedDatasetVersion: "2026.03",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: store,
                activationPolicy: policy,
                refreshStateStore: refreshStateStore
            )
        )

        let catalog = try await repository.fetchCatalog()
        let seoul = try #require(catalog.descriptor(for: .seoulCapitalSnapshot))
        let live = try #require(seoul.liveMetadata)

        #expect(live.supportsLiveRefresh)
        #expect(live.latestKnownDatasetVersion == "2026.03")
        #expect(live.latestKnownSnapshotID == "seoul-2026.03")
        #expect(live.lastRefreshAttemptAt == "2026-03-08T01:00:00Z")
        #expect(live.lastSuccessfulRefreshAt == "2026-03-08T01:01:00Z")
        #expect(live.lastRefreshOutcome == .success)
        #expect(live.lastRefreshTrigger == .manual)
        #expect(live.latestCandidateSnapshotID == "seoul-2026.03")
        #expect(live.latestCandidateCompatibility == .compatible)
        #expect(live.latestCandidateEligibleForActivation == true)
        #expect(live.activeSnapshotID == "seoul-2026.03")
        #expect(live.readiness == .ready)
        #expect(live.syncState == .ready)
    }

    @Test
    func keepsStaticSourceWithoutBogusLiveMetadata() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: store,
                activationPolicy: policy
            )
        )

        let catalog = try await repository.fetchCatalog()
        #expect(catalog.descriptor(for: .bundledSample)?.liveMetadata == nil)
    }

    @Test
    func enrichesFailureRefreshStateWithoutBreakingReadinessSemantics() async throws {
        let store = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)

        await refreshStateStore.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .periodic,
                status: .failed,
                startedAt: "2026-03-09T02:00:00Z",
                finishedAt: "2026-03-09T02:00:30Z",
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .ingestionFailed(.adapterFailure(.networkUnavailable))
            )
        )

        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: store,
                activationPolicy: policy,
                refreshStateStore: refreshStateStore
            )
        )

        let catalog = try await repository.fetchCatalog()
        let seoul = try #require(catalog.descriptor(for: .seoulCapitalSnapshot))
        let live = try #require(seoul.liveMetadata)

        #expect(live.lastRefreshOutcome == .failed)
        #expect(live.lastRefreshTrigger == .periodic)
        #expect(live.lastRefreshFailedAt == "2026-03-09T02:00:30Z")
        #expect(live.lastRefreshFailureReason == "ingestion_failed_adapter_failure")
        #expect(live.readiness == .pendingValidation)
        #expect(live.syncState == .idle)
    }

    private func seed(
        store: InMemoryDatasetVersionStore,
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        generatedAt: String,
        indexedAt: String
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
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: true,
                compatibilityReasons: [],
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(state: .eligible, reasons: [])
        )

        await store.upsert(
            contract: contract,
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: indexedAt
        )
    }
}
