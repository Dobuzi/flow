import Foundation
import Testing
@testable import Flow

struct SnapshotActivationStateStoreTests {
    @Test
    func activationStatePersistsAcrossPolicyReinitialization() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seed(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            indexedAt: "2026-03-14T01:00:00Z"
        )
        await seed(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            indexedAt: "2026-04-14T01:00:00Z"
        )

        let fileURL = makeFileURL(testName: "persist")
        let store = PersistentSnapshotActivationStateStore(fileURL: fileURL)
        let policy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: store,
            nowProvider: { "2026-03-14T02:00:00Z" }
        )

        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.04")

        let reloadedPolicy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: PersistentSnapshotActivationStateStore(fileURL: fileURL),
            nowProvider: { "2026-03-14T03:00:00Z" }
        )
        let state = await reloadedPolicy.currentState(for: .seoulCapitalSnapshot)

        #expect(state.activeSnapshotID == "seoul-2026.04")
        #expect(state.lastKnownGoodSnapshotID == "seoul-2026.03")
    }

    @Test
    func sourceScopedActivationStateRemainsCorrectAfterReload() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seed(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            indexedAt: "2026-03-14T01:00:00Z"
        )
        await seed(
            store: versionStore,
            source: .koreaNational,
            snapshotID: "national-2026.05",
            datasetVersion: "2026.05",
            indexedAt: "2026-05-14T01:00:00Z"
        )

        let fileURL = makeFileURL(testName: "source-scoped")
        let policy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: PersistentSnapshotActivationStateStore(fileURL: fileURL),
            nowProvider: { "2026-03-14T02:00:00Z" }
        )

        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        _ = try await policy.activate(source: .koreaNational, requestedSnapshotID: "national-2026.05")

        let reloadedPolicy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: PersistentSnapshotActivationStateStore(fileURL: fileURL),
            nowProvider: { "2026-03-14T03:00:00Z" }
        )

        let seoul = await reloadedPolicy.currentState(for: .seoulCapitalSnapshot)
        let national = await reloadedPolicy.currentState(for: .koreaNational)
        let bundled = await reloadedPolicy.currentState(for: .bundledSample)

        #expect(seoul.activeSnapshotID == "seoul-2026.03")
        #expect(national.activeSnapshotID == "national-2026.05")
        #expect(bundled.activeSnapshotID == nil)
        #expect(bundled.lastKnownGoodSnapshotID == nil)
    }

    @Test
    func malformedPersistedActivationStateFallsBackSafely() async throws {
        let fileURL = makeFileURL(testName: "corrupt")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        let store = PersistentSnapshotActivationStateStore(fileURL: fileURL)
        let state = await store.state(for: .seoulCapitalSnapshot)

        #expect(state == nil)

        let backupFiles = try FileManager.default.contentsOfDirectory(
            at: fileURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        #expect(backupFiles.contains { $0.lastPathComponent.contains(".corrupted.") })
    }

    @Test
    func projectedActivationStateAndRollbackReadinessRemainCompatibleAfterPersistentReload() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seed(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            indexedAt: "2026-03-14T01:00:00Z"
        )
        await seed(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            indexedAt: "2026-04-14T01:00:00Z"
        )

        let fileURL = makeFileURL(testName: "projection")
        let initialPolicy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: PersistentSnapshotActivationStateStore(fileURL: fileURL),
            nowProvider: { "2026-03-14T02:00:00Z" }
        )
        _ = try await initialPolicy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        _ = try await initialPolicy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.04")

        let reloadedPolicy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: PersistentSnapshotActivationStateStore(fileURL: fileURL),
            nowProvider: { "2026-03-14T03:00:00Z" }
        )
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: reloadedPolicy,
            historyStore: historyStore,
            versionStore: versionStore,
            nowProvider: { "2026-03-14T03:05:00Z" }
        )

        let projected = await projector.project(for: .seoulCapitalSnapshot)
        let rollback = await reloadedPolicy.evaluateRollback(source: .seoulCapitalSnapshot)

        #expect(projected.activeSnapshotID == "seoul-2026.04")
        #expect(projected.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(projected.rollbackAvailable)
        #expect(projected.status == .activeRollbackReady)
        #expect(rollback.status == .rollbackAvailable)
        #expect(rollback.target?.snapshotID == "seoul-2026.03")
    }

    @Test
    func catalogMetadataRemainsCompatibleAfterPersistentPolicyReload() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seed(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            indexedAt: "2026-03-14T01:00:00Z"
        )
        await seed(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            indexedAt: "2026-04-14T01:00:00Z"
        )

        let fileURL = makeFileURL(testName: "catalog")
        let initialPolicy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: PersistentSnapshotActivationStateStore(fileURL: fileURL),
            nowProvider: { "2026-03-14T02:00:00Z" }
        )
        _ = try await initialPolicy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        _ = try await initialPolicy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.04")

        let reloadedPolicy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: PersistentSnapshotActivationStateStore(fileURL: fileURL),
            nowProvider: { "2026-03-14T03:00:00Z" }
        )
        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: versionStore,
                activationPolicy: reloadedPolicy,
                refreshStateStore: InMemoryDatasetRefreshStateStore(),
                activationStateProjector: DefaultSnapshotActivationStateProjector(
                    activationPolicy: reloadedPolicy,
                    historyStore: InMemorySnapshotActivationHistoryStore(),
                    versionStore: versionStore
                )
            )
        )

        let catalog = try await repository.fetchCatalog()
        let seoul = try #require(catalog.descriptor(for: .seoulCapitalSnapshot))
        let live = try #require(seoul.liveMetadata)
        let activation = try #require(live.activationMetadata)

        #expect(live.activeSnapshotID == "seoul-2026.04")
        #expect(live.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(activation.activeSnapshotID == "seoul-2026.04")
        #expect(activation.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(activation.rollbackAvailable == true)
    }

    private func makeFileURL(testName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTests", isDirectory: true)
            .appendingPathComponent("PersistentSnapshotActivationStateStore", isDirectory: true)
            .appendingPathComponent(testName, isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json", isDirectory: false)
    }

    private func seed(
        store: InMemoryDatasetVersionStore,
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        indexedAt: String
    ) async {
        let contract = MaterializedSnapshotContract(
            snapshotID: snapshotID,
            source: source,
            schemaVersion: "1.0.0",
            datasetVersion: datasetVersion,
            generatedAt: indexedAt,
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
