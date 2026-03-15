import Foundation
import Testing
@testable import Flow

struct DatasetRefreshStateStoreTests {
    @Test
    func persistsRefreshStateAcrossStoreReinitialization() async throws {
        let fileURL = makeFileURL(testName: "persist")
        let store = PersistentDatasetRefreshStateStore(fileURL: fileURL)

        await store.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-14T01:00:00Z",
                finishedAt: "2026-03-14T01:01:00Z",
                storedSnapshotID: "seoul-2026.04",
                storedDatasetVersion: "2026.04",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )

        let reloaded = PersistentDatasetRefreshStateStore(fileURL: fileURL)
        #expect(reloaded.restorationDisposition == .current)
        let state = await reloaded.state(for: .seoulCapitalSnapshot)

        #expect(state?.lastRefreshAttemptAt == "2026-03-14T01:00:00Z")
        #expect(state?.lastRefreshSucceededAt == "2026-03-14T01:01:00Z")
        #expect(state?.lastRefreshTrigger == .manual)
        #expect(state?.lastRefreshOutcome == .success)
        #expect(state?.latestCandidateSnapshotID == "seoul-2026.04")
        #expect(state?.latestCandidateCompatibility == .compatible)
        #expect(state?.latestCandidateEligibleForActivation == true)
        #expect(state?.lastRefreshFailureReason == nil)
    }

    @Test
    func preservesSourceScopedRefreshStateAfterReload() async throws {
        let fileURL = makeFileURL(testName: "source-scoped")
        let store = PersistentDatasetRefreshStateStore(fileURL: fileURL)

        await store.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .periodic,
                status: .failed,
                startedAt: "2026-03-14T02:00:00Z",
                finishedAt: "2026-03-14T02:00:30Z",
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .ingestionFailed(.adapterFailure(.networkUnavailable))
            )
        )
        await store.record(
            DatasetRefreshResult(
                source: .koreaNational,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-14T03:00:00Z",
                finishedAt: "2026-03-14T03:01:00Z",
                storedSnapshotID: "national-2026.04",
                storedDatasetVersion: "2026.04",
                compatibilityClassification: .partiallyCompatible,
                eligibleForActivation: false,
                didStoreCandidate: true,
                error: nil
            )
        )

        let reloaded = PersistentDatasetRefreshStateStore(fileURL: fileURL)
        #expect(reloaded.restorationDisposition == .current)
        let seoul = await reloaded.state(for: .seoulCapitalSnapshot)
        let national = await reloaded.state(for: .koreaNational)
        let bundled = await reloaded.state(for: .bundledSample)

        #expect(seoul?.lastRefreshOutcome == .failed)
        #expect(seoul?.lastRefreshTrigger == .periodic)
        #expect(seoul?.lastRefreshFailedAt == "2026-03-14T02:00:30Z")
        #expect(seoul?.lastRefreshFailureReason == "ingestion_failed_adapter_failure")

        #expect(national?.lastRefreshOutcome == .success)
        #expect(national?.latestCandidateSnapshotID == "national-2026.04")
        #expect(national?.latestCandidateCompatibility == .partiallyCompatible)
        #expect(national?.latestCandidateEligibleForActivation == false)

        #expect(bundled == nil)
    }

    @Test
    func malformedPersistedStateFallsBackSafely() async throws {
        let fileURL = makeFileURL(testName: "corrupt")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        let reloaded = PersistentDatasetRefreshStateStore(fileURL: fileURL)
        #expect(reloaded.restorationDisposition == .resetCorrupted)
        let state = await reloaded.state(for: .seoulCapitalSnapshot)

        #expect(state == nil)

        let backupFiles = try FileManager.default.contentsOfDirectory(
            at: fileURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        #expect(backupFiles.contains { $0.lastPathComponent.contains(".corrupted.") })
    }

    @Test
    func metadataEnrichmentRemainsCompatibleAfterPersistentReload() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        let fileURL = makeFileURL(testName: "enrichment")
        let persistentStore = PersistentDatasetRefreshStateStore(fileURL: fileURL)

        await seed(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            generatedAt: "2026-03-14T04:00:00Z",
            indexedAt: "2026-03-14T04:01:00Z"
        )

        await persistentStore.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-14T04:00:00Z",
                finishedAt: "2026-03-14T04:01:00Z",
                storedSnapshotID: "seoul-2026.04",
                storedDatasetVersion: "2026.04",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )

        let reloadedStore = PersistentDatasetRefreshStateStore(fileURL: fileURL)
        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: versionStore,
                activationPolicy: policy,
                refreshStateStore: reloadedStore,
                activationStateProjector: DefaultSnapshotActivationStateProjector(
                    activationPolicy: policy,
                    historyStore: InMemorySnapshotActivationHistoryStore(),
                    versionStore: versionStore
                )
            )
        )

        let catalog = try await repository.fetchCatalog()
        let seoul = try #require(catalog.descriptor(for: .seoulCapitalSnapshot))
        let live = try #require(seoul.liveMetadata)

        #expect(live.lastRefreshAttemptAt == "2026-03-14T04:00:00Z")
        #expect(live.lastSuccessfulRefreshAt == "2026-03-14T04:01:00Z")
        #expect(live.lastRefreshTrigger == .manual)
        #expect(live.lastRefreshOutcome == .success)
        #expect(live.latestCandidateSnapshotID == "seoul-2026.04")
        #expect(live.latestCandidateCompatibility == .compatible)
        #expect(live.latestCandidateEligibleForActivation == true)
    }

    private func makeFileURL(testName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTests", isDirectory: true)
            .appendingPathComponent("PersistentDatasetRefreshStateStore", isDirectory: true)
            .appendingPathComponent(testName, isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json", isDirectory: false)
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
