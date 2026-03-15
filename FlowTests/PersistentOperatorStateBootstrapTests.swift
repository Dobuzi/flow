import Foundation
import Testing
@testable import Flow

struct PersistentOperatorStateBootstrapTests {
    @Test
    func bootstrapRestoresAllPersistentOperatorStateWhenFilesAreValid() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            indexedAt: "2026-03-15T01:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            indexedAt: "2026-03-15T02:00:00Z"
        )

        let files = makeBootstrapFileURLs(testName: #function)
        let refreshStore = PersistentDatasetRefreshStateStore(fileURL: files.refresh)
        await refreshStore.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-15T02:00:00Z",
                finishedAt: "2026-03-15T02:01:00Z",
                storedSnapshotID: "seoul-2026.04",
                storedDatasetVersion: "2026.04",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )

        let activationStateStore = PersistentSnapshotActivationStateStore(fileURL: files.activationState)
        let activationPolicy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: activationStateStore,
            nowProvider: { "2026-03-15T02:05:00Z" }
        )
        _ = try await activationPolicy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        _ = try await activationPolicy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.04")

        let historyStore = PersistentSnapshotActivationHistoryStore(fileURL: files.history)
        await historyStore.append(
            SnapshotActivationHistoryEvent(
                eventID: "evt-promote-succeeded",
                type: .promoteSucceeded,
                timestamp: "2026-03-15T02:06:00Z",
                metadata: SnapshotActivationEventMetadata(
                    source: .seoulCapitalSnapshot,
                    snapshotID: "seoul-2026.04",
                    datasetVersion: "2026.04",
                    commandID: "cmd-promote",
                    commandAction: .promote,
                    trigger: .operatorConfirmed,
                    requestedBy: nil,
                    note: nil,
                    validation: nil,
                    guardDecision: nil,
                    execution: nil
                ),
                result: SnapshotActivationEventResult(
                    status: .succeeded,
                    reasonCode: nil,
                    message: "Promoted successfully"
                )
            )
        )

        let bootstrap = PersistentOperatorStateBootstrap(
            versionStore: versionStore,
            activationStateFileURL: files.activationState,
            refreshStateFileURL: files.refresh,
            activationHistoryFileURL: files.history
        ).bootstrap()

        #expect(bootstrap.status.activationState == .current)
        #expect(bootstrap.status.refreshState == .current)
        #expect(bootstrap.status.activationHistory == .current)
        #expect(bootstrap.status.isDegraded == false)

        let restoredState = await bootstrap.activationPolicy.currentState(for: .seoulCapitalSnapshot)
        let restoredRefresh = await bootstrap.refreshStateStore.state(for: .seoulCapitalSnapshot)
        let restoredHistory = await bootstrap.activationHistoryStore.latestEvent(for: .seoulCapitalSnapshot)
        let projected = await bootstrap.activationStateProjector.project(for: .seoulCapitalSnapshot)

        #expect(restoredState.activeSnapshotID == "seoul-2026.04")
        #expect(restoredState.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(restoredRefresh?.latestCandidateSnapshotID == "seoul-2026.04")
        #expect(restoredHistory?.eventID == "evt-promote-succeeded")
        #expect(projected.activeSnapshotID == "seoul-2026.04")
        #expect(projected.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(projected.latestActivationEvent?.eventID == "evt-promote-succeeded")
        #expect(projected.rollbackAvailable == true)
    }

    @Test
    func bootstrapRemainsStableWhenRefreshStateFileIsMissing() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            indexedAt: "2026-03-15T03:00:00Z"
        )

        let files = makeBootstrapFileURLs(testName: #function)
        let activationStateStore = PersistentSnapshotActivationStateStore(fileURL: files.activationState)
        let policy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: activationStateStore,
            nowProvider: { "2026-03-15T03:05:00Z" }
        )
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let historyStore = PersistentSnapshotActivationHistoryStore(fileURL: files.history)
        await historyStore.append(
            makeRequestedEvent(
                eventID: "evt-requested",
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.03",
                timestamp: "2026-03-15T03:06:00Z"
            )
        )

        let bootstrap = PersistentOperatorStateBootstrap(
            versionStore: versionStore,
            activationStateFileURL: files.activationState,
            refreshStateFileURL: files.refresh,
            activationHistoryFileURL: files.history
        ).bootstrap()

        #expect(bootstrap.status.activationState == .current)
        #expect(bootstrap.status.refreshState == .empty)
        #expect(bootstrap.status.activationHistory == .current)

        let restoredRefresh = await bootstrap.refreshStateStore.state(for: .seoulCapitalSnapshot)
        let restoredState = await bootstrap.activationPolicy.currentState(for: .seoulCapitalSnapshot)
        let projected = await bootstrap.activationStateProjector.project(for: .seoulCapitalSnapshot)

        #expect(restoredRefresh == nil)
        #expect(restoredState.activeSnapshotID == "seoul-2026.03")
        #expect(projected.activeSnapshotID == "seoul-2026.03")
        #expect(projected.hasActivationHistory == true)
    }

    @Test
    func bootstrapRecoversWhenActivationHistoryIsCorruptButOtherStoresRemainValid() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .koreaNational,
            snapshotID: "national-2026.05",
            datasetVersion: "2026.05",
            indexedAt: "2026-03-15T04:00:00Z"
        )

        let files = makeBootstrapFileURLs(testName: #function)
        let refreshStore = PersistentDatasetRefreshStateStore(fileURL: files.refresh)
        await refreshStore.record(
            DatasetRefreshResult(
                source: .koreaNational,
                trigger: .periodic,
                status: .succeeded,
                startedAt: "2026-03-15T04:00:00Z",
                finishedAt: "2026-03-15T04:01:00Z",
                storedSnapshotID: "national-2026.05",
                storedDatasetVersion: "2026.05",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )

        let activationStateStore = PersistentSnapshotActivationStateStore(fileURL: files.activationState)
        let policy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: activationStateStore,
            nowProvider: { "2026-03-15T04:05:00Z" }
        )
        _ = try await policy.activate(source: .koreaNational, requestedSnapshotID: "national-2026.05")

        try FileManager.default.createDirectory(
            at: files.history.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("broken-history".utf8).write(to: files.history)

        let bootstrap = PersistentOperatorStateBootstrap(
            versionStore: versionStore,
            activationStateFileURL: files.activationState,
            refreshStateFileURL: files.refresh,
            activationHistoryFileURL: files.history
        ).bootstrap()

        #expect(bootstrap.status.activationState == .current)
        #expect(bootstrap.status.refreshState == .current)
        #expect(bootstrap.status.activationHistory == .resetCorrupted)
        #expect(bootstrap.status.isDegraded == true)

        let restoredState = await bootstrap.activationPolicy.currentState(for: .koreaNational)
        let restoredRefresh = await bootstrap.refreshStateStore.state(for: .koreaNational)
        let restoredHistory = await bootstrap.activationHistoryStore.events(for: .koreaNational)
        let projected = await bootstrap.activationStateProjector.project(for: .koreaNational)

        #expect(restoredState.activeSnapshotID == "national-2026.05")
        #expect(restoredRefresh?.latestCandidateSnapshotID == "national-2026.05")
        #expect(restoredHistory.isEmpty)
        #expect(projected.activeSnapshotID == "national-2026.05")
        #expect(projected.hasActivationHistory == false)
    }

    @Test
    func bootstrapPreservesSourceScopedOperatorStateAcrossSources() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            indexedAt: "2026-03-15T05:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .koreaNational,
            snapshotID: "national-2026.06",
            datasetVersion: "2026.06",
            indexedAt: "2026-03-15T05:10:00Z"
        )

        let files = makeBootstrapFileURLs(testName: #function)
        let refreshStore = PersistentDatasetRefreshStateStore(fileURL: files.refresh)
        await refreshStore.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-15T05:00:00Z",
                finishedAt: "2026-03-15T05:01:00Z",
                storedSnapshotID: "seoul-2026.03",
                storedDatasetVersion: "2026.03",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )
        await refreshStore.record(
            DatasetRefreshResult(
                source: .koreaNational,
                trigger: .periodic,
                status: .succeeded,
                startedAt: "2026-03-15T05:10:00Z",
                finishedAt: "2026-03-15T05:11:00Z",
                storedSnapshotID: "national-2026.06",
                storedDatasetVersion: "2026.06",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )

        let activationStateStore = PersistentSnapshotActivationStateStore(fileURL: files.activationState)
        let policy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: activationStateStore,
            nowProvider: { "2026-03-15T05:15:00Z" }
        )
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        _ = try await policy.activate(source: .koreaNational, requestedSnapshotID: "national-2026.06")

        let bootstrap = PersistentOperatorStateBootstrap(
            versionStore: versionStore,
            activationStateFileURL: files.activationState,
            refreshStateFileURL: files.refresh,
            activationHistoryFileURL: files.history
        ).bootstrap()

        let seoulState = await bootstrap.activationPolicy.currentState(for: .seoulCapitalSnapshot)
        let nationalState = await bootstrap.activationPolicy.currentState(for: .koreaNational)
        let bundledState = await bootstrap.activationPolicy.currentState(for: .bundledSample)
        let seoulRefresh = await bootstrap.refreshStateStore.state(for: .seoulCapitalSnapshot)
        let nationalRefresh = await bootstrap.refreshStateStore.state(for: .koreaNational)

        #expect(seoulState.activeSnapshotID == "seoul-2026.03")
        #expect(nationalState.activeSnapshotID == "national-2026.06")
        #expect(bundledState.activeSnapshotID == nil)
        #expect(seoulRefresh?.latestCandidateSnapshotID == "seoul-2026.03")
        #expect(nationalRefresh?.latestCandidateSnapshotID == "national-2026.06")
    }

    private func makeBootstrapFileURLs(testName: String) -> (activationState: URL, refresh: URL, history: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTests", isDirectory: true)
            .appendingPathComponent("PersistentOperatorStateBootstrap", isDirectory: true)
            .appendingPathComponent(testName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return (
            activationState: root.appendingPathComponent("activation_state.json", isDirectory: false),
            refresh: root.appendingPathComponent("refresh_state.json", isDirectory: false),
            history: root.appendingPathComponent("activation_history.json", isDirectory: false)
        )
    }

    private func seedVersion(
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

    private func makeRequestedEvent(
        eventID: String,
        source: FlowDatasetSource,
        snapshotID: String,
        timestamp: String
    ) -> SnapshotActivationHistoryEvent {
        SnapshotActivationHistoryEvent(
            eventID: eventID,
            type: .promoteRequested,
            timestamp: timestamp,
            metadata: SnapshotActivationEventMetadata(
                source: source,
                snapshotID: snapshotID,
                datasetVersion: nil,
                commandID: "cmd-\(eventID)",
                commandAction: .promote,
                trigger: .operatorManual,
                requestedBy: nil,
                note: nil,
                validation: nil,
                guardDecision: nil,
                execution: nil
            ),
            result: SnapshotActivationEventResult(
                status: .requested,
                reasonCode: nil,
                message: nil
            )
        )
    }
}
