import Foundation
import Testing
@testable import Flow

struct OperatorDashboardViewModelTests {
    @Test
    @MainActor
    func buildsLiveCapableSourceSummariesFromEnrichedCatalog() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            indexedAt: "2026-03-15T01:00:00Z"
        )

        await refreshStateStore.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-15T01:00:00Z",
                finishedAt: "2026-03-15T01:01:00Z",
                storedSnapshotID: "seoul-2026.04",
                storedDatasetVersion: "2026.04",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.04")
        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: policy,
            historyStore: historyStore,
            versionStore: versionStore,
            nowProvider: { "2026-03-15T01:02:00Z" }
        )
        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: versionStore,
                activationPolicy: policy,
                refreshStateStore: refreshStateStore,
                activationStateProjector: projector
            )
        )
        let bootstrapStatus = PersistentOperatorStateBootstrapStatus(
            activationState: .current,
            refreshState: .current,
            activationHistory: .current
        )

        let viewModel = OperatorDashboardViewModel(
            catalogRepository: repository,
            bootstrapStatus: bootstrapStatus,
            activationHistoryStore: historyStore,
            refreshStateStore: refreshStateStore
        )
        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)
        let seoul = try #require(dashboard.sources.first(where: { $0.source == .seoulCapitalSnapshot }))
        let live = try #require(seoul.liveSummary)

        #expect(seoul.isLiveCapable)
        #expect(live.activeSnapshotID == "seoul-2026.04")
        #expect(live.lastKnownGoodSnapshotID == nil)
        #expect(live.latestCandidateSnapshotID == "seoul-2026.04")
        #expect(live.latestCandidateCompatibility == .compatible)
        #expect(live.latestCandidateEligibleForActivation == true)
        #expect(live.lastRefreshOutcome == .success)
        #expect(live.lastRefreshAt == "2026-03-15T01:01:00Z")
        #expect(live.rollbackAvailable == false)
        #expect(live.operatorActivationStatus == .active)
        #expect(live.metrics.activation.succeededCount == 0)
        #expect(live.metrics.refresh.attemptCount == 1)
        #expect(live.metrics.refresh.succeededCount == 1)
        #expect(live.metrics.refresh.latestRefreshLatencySeconds == 60)
        #expect(seoul.healthSummary.state == .healthy)
        #expect(seoul.healthSummary.operationalStatus == .active)
        #expect(seoul.approvalSummary?.approvalState == .approved)
        #expect(seoul.approvalSummary?.directExecutionCompatible == true)
        #expect(seoul.rolloutReadinessSummary?.state == .immediateReady)
        #expect(seoul.rolloutPreflight?.recommendation == .immediate)
        #expect(seoul.rolloutPreflight?.blockingReasons.isEmpty == true)
        #expect(dashboard.bootstrapStatus == bootstrapStatus)
    }

    @Test
    @MainActor
    func keepsStaticSourceSafeWithoutBogusOperatorState() async throws {
        let viewModel = OperatorDashboardViewModel(
            catalogRepository: LocalMobilityCatalogRepository(),
            bootstrapStatus: nil
        )

        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)
        let bundled = try #require(dashboard.sources.first(where: { $0.source == .bundledSample }))

        #expect(bundled.isLiveCapable == false)
        #expect(bundled.liveSummary == nil)
        #expect(bundled.healthSummary.state == .static)
        #expect(bundled.healthSummary.operationalStatus == .staticBaseline)
        #expect(bundled.approvalSummary == nil)
        #expect(bundled.rolloutReadinessSummary?.state == .staticBaseline)
        #expect(bundled.rolloutPreflight?.recommendation == .notApplicable)
    }

    @Test
    @MainActor
    func preservesSourceScopedActivationAndRefreshStatePerSource() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            indexedAt: "2026-03-15T02:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .koreaNational,
            snapshotID: "national-2026.05",
            datasetVersion: "2026.05",
            indexedAt: "2026-03-15T03:00:00Z"
        )

        await refreshStateStore.record(
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
        await refreshStateStore.record(
            DatasetRefreshResult(
                source: .koreaNational,
                trigger: .periodic,
                status: .failed,
                startedAt: "2026-03-15T03:00:00Z",
                finishedAt: "2026-03-15T03:01:00Z",
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .ingestionFailed(.adapterFailure(.networkUnavailable))
            )
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.04")

        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: versionStore,
                activationPolicy: policy,
                refreshStateStore: refreshStateStore,
                activationStateProjector: DefaultSnapshotActivationStateProjector(
                    activationPolicy: policy,
                    historyStore: historyStore,
                    versionStore: versionStore,
                    nowProvider: { "2026-03-15T03:02:00Z" }
                )
            )
        )

        await historyStore.append(
            SnapshotActivationHistoryEvent(
                eventID: "national-blocked",
                type: .promoteBlocked,
                timestamp: "2026-03-15T03:01:30Z",
                metadata: .init(
                    source: .koreaNational,
                    snapshotID: "national-2026.05",
                    datasetVersion: "2026.05",
                    commandID: "national-blocked",
                    commandAction: .promote,
                    trigger: .operatorManual,
                    requestedBy: "tester",
                    note: nil,
                    validation: nil,
                    guardDecision: nil,
                    execution: nil
                ),
                result: .init(
                    status: .blocked,
                    reasonCode: "candidate_incompatible",
                    message: nil
                )
            )
        )

        let viewModel = OperatorDashboardViewModel(
            catalogRepository: repository,
            activationHistoryStore: historyStore,
            refreshStateStore: refreshStateStore
        )
        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)
        let seoul = try #require(dashboard.sources.first(where: { $0.source == .seoulCapitalSnapshot }))
        let national = try #require(dashboard.sources.first(where: { $0.source == .koreaNational }))

        #expect(seoul.liveSummary?.activeSnapshotID == "seoul-2026.04")
        #expect(seoul.liveSummary?.lastRefreshOutcome == .success)
        #expect(seoul.liveSummary?.latestCandidateSnapshotID == "seoul-2026.04")
        #expect(seoul.liveSummary?.metrics.refresh.succeededCount == 1)
        #expect(seoul.liveSummary?.metrics.activation.blockedCount == 0)
        #expect(seoul.healthSummary.state == .healthy)
        #expect(seoul.approvalSummary?.approvalState == .approved)
        #expect(seoul.rolloutReadinessSummary?.state == .immediateReady)
        #expect(seoul.rolloutPreflight?.recommendation == .immediate)

        #expect(national.liveSummary?.activeSnapshotID == nil)
        #expect(national.liveSummary?.lastRefreshOutcome == .failed)
        #expect(national.liveSummary?.lastRefreshAt == "2026-03-15T03:01:00Z")
        #expect(national.liveSummary?.latestCandidateSnapshotID == nil)
        #expect(national.liveSummary?.metrics.refresh.failedCount == 1)
        #expect(national.liveSummary?.metrics.activation.blockedCount == 1)
        #expect(national.healthSummary.state == .degraded)
        #expect(national.approvalSummary?.approvalState == .awaitingApproval)
        #expect(national.rolloutReadinessSummary?.state == .notReady)
        #expect(national.rolloutPreflight?.recommendation == .blocked)
        #expect(national.rolloutPreflight?.warningReasons.contains("Pending validation") == true)
    }

    @Test
    @MainActor
    func surfacesBootstrapHealthAndPreservesDeterministicOrdering() async throws {
        let bootstrapStatus = PersistentOperatorStateBootstrapStatus(
            activationState: .current,
            refreshState: .resetCorrupted,
            activationHistory: .current
        )
        let viewModel = OperatorDashboardViewModel(
            catalogRepository: LocalMobilityCatalogRepository(),
            bootstrapStatus: bootstrapStatus
        )

        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)

        #expect(dashboard.bootstrapStatus == bootstrapStatus)
        #expect(dashboard.bootstrapStatus?.isDegraded == true)
        #expect(dashboard.liveSources.allSatisfy { $0.healthSummary.state == .recoveryNeeded })
        #expect(dashboard.liveSources.allSatisfy { $0.approvalSummary?.approvalState == .awaitingApproval })
        #expect(dashboard.liveSources.allSatisfy { $0.rolloutReadinessSummary?.state == .blocked })
        #expect(dashboard.liveSources.allSatisfy { $0.rolloutPreflight?.recommendation == .blocked })
        #expect(dashboard.sources.map(\.source) == [.bundledSample, .seoulCapitalSnapshot, .koreaNational])
        #expect(dashboard.liveSources.map(\.source) == [.seoulCapitalSnapshot, .koreaNational])
        #expect(dashboard.staticSources.map(\.source) == [.bundledSample])
    }

    @Test
    @MainActor
    func buildsTruthfulDashboardSummariesAfterPersistentBootstrapReload() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            indexedAt: "2026-03-16T01:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .koreaNational,
            snapshotID: "national-2026.05",
            datasetVersion: "2026.05",
            indexedAt: "2026-03-16T01:10:00Z"
        )

        let files = makeBootstrapFileURLs(testName: #function)
        let refreshStore = PersistentDatasetRefreshStateStore(fileURL: files.refresh)
        await refreshStore.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-16T01:00:00Z",
                finishedAt: "2026-03-16T01:01:00Z",
                storedSnapshotID: "seoul-2026.04",
                storedDatasetVersion: "2026.04",
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
                status: .failed,
                startedAt: "2026-03-16T01:10:00Z",
                finishedAt: "2026-03-16T01:11:00Z",
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .ingestionFailed(.adapterFailure(.networkUnavailable))
            )
        )

        let activationStateStore = PersistentSnapshotActivationStateStore(fileURL: files.activationState)
        let policy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: activationStateStore,
            nowProvider: { "2026-03-16T01:12:00Z" }
        )
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.04")

        let historyStore = PersistentSnapshotActivationHistoryStore(fileURL: files.history)
        await historyStore.append(
            SnapshotActivationHistoryEvent(
                eventID: "national-persisted-blocked",
                type: .promoteBlocked,
                timestamp: "2026-03-16T01:11:30Z",
                metadata: .init(
                    source: .koreaNational,
                    snapshotID: "national-2026.05",
                    datasetVersion: "2026.05",
                    commandID: "national-persisted-blocked",
                    commandAction: .promote,
                    trigger: .operatorManual,
                    requestedBy: nil,
                    note: nil,
                    validation: nil,
                    guardDecision: nil,
                    execution: nil
                ),
                result: .init(
                    status: .blocked,
                    reasonCode: "candidate_incompatible",
                    message: nil
                )
            )
        )

        let bootstrap = PersistentOperatorStateBootstrap(
            versionStore: versionStore,
            activationStateFileURL: files.activationState,
            refreshStateFileURL: files.refresh,
            activationHistoryFileURL: files.history
        ).bootstrap()

        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: versionStore,
                activationPolicy: bootstrap.activationPolicy,
                refreshStateStore: bootstrap.refreshStateStore,
                activationStateProjector: bootstrap.activationStateProjector
            )
        )

        let viewModel = OperatorDashboardViewModel(
            catalogRepository: repository,
            bootstrapStatus: bootstrap.status,
            activationHistoryStore: bootstrap.activationHistoryStore,
            refreshStateStore: bootstrap.refreshStateStore
        )
        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)
        let seoul = try #require(dashboard.sources.first(where: { $0.source == .seoulCapitalSnapshot }))
        let national = try #require(dashboard.sources.first(where: { $0.source == .koreaNational }))

        #expect(dashboard.bootstrapStatus == bootstrap.status)
        #expect(seoul.liveSummary?.activeSnapshotID == "seoul-2026.04")
        #expect(seoul.liveSummary?.latestCandidateSnapshotID == "seoul-2026.04")
        #expect(seoul.liveSummary?.lastRefreshOutcome == .success)
        #expect(seoul.rolloutPreflight?.recommendation == .immediate)

        #expect(national.liveSummary?.activeSnapshotID == nil)
        #expect(national.liveSummary?.latestCandidateSnapshotID == nil)
        #expect(national.liveSummary?.lastRefreshOutcome == .failed)
        #expect(national.approvalSummary?.approvalState == .awaitingApproval)
        #expect(national.rolloutPreflight?.recommendation == .blocked)
    }

    @Test
    @MainActor
    func keepsDashboardMetricsHealthApprovalAndPreflightCoherentPerSource() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.05",
            datasetVersion: "2026.05",
            indexedAt: "2026-03-16T02:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .koreaNational,
            snapshotID: "national-2026.06",
            datasetVersion: "2026.06",
            indexedAt: "2026-03-16T02:10:00Z"
        )

        await refreshStateStore.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-16T02:00:00Z",
                finishedAt: "2026-03-16T02:02:00Z",
                storedSnapshotID: "seoul-2026.05",
                storedDatasetVersion: "2026.05",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )
        await refreshStateStore.record(
            DatasetRefreshResult(
                source: .koreaNational,
                trigger: .periodic,
                status: .failed,
                startedAt: "2026-03-16T02:10:00Z",
                finishedAt: "2026-03-16T02:11:00Z",
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .ingestionFailed(.adapterFailure(.networkUnavailable))
            )
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.05")

        await historyStore.append(
            SnapshotActivationHistoryEvent(
                eventID: "seoul-promote-requested",
                type: .promoteRequested,
                timestamp: "2026-03-16T02:02:30Z",
                metadata: .init(
                    source: .seoulCapitalSnapshot,
                    snapshotID: "seoul-2026.05",
                    datasetVersion: "2026.05",
                    commandID: "seoul-promote-requested",
                    commandAction: .promote,
                    trigger: .operatorManual,
                    requestedBy: nil,
                    note: nil,
                    validation: nil,
                    guardDecision: nil,
                    execution: nil
                ),
                result: .init(
                    status: .requested,
                    reasonCode: nil,
                    message: nil
                )
            )
        )
        await historyStore.append(
            SnapshotActivationHistoryEvent(
                eventID: "seoul-promote-succeeded",
                type: .promoteSucceeded,
                timestamp: "2026-03-16T02:03:00Z",
                metadata: .init(
                    source: .seoulCapitalSnapshot,
                    snapshotID: "seoul-2026.05",
                    datasetVersion: "2026.05",
                    commandID: "seoul-promote-succeeded",
                    commandAction: .promote,
                    trigger: .operatorConfirmed,
                    requestedBy: nil,
                    note: nil,
                    validation: nil,
                    guardDecision: nil,
                    execution: nil
                ),
                result: .init(
                    status: .succeeded,
                    reasonCode: nil,
                    message: nil
                )
            )
        )
        await historyStore.append(
            SnapshotActivationHistoryEvent(
                eventID: "national-promote-blocked",
                type: .promoteBlocked,
                timestamp: "2026-03-16T02:11:30Z",
                metadata: .init(
                    source: .koreaNational,
                    snapshotID: "national-2026.06",
                    datasetVersion: "2026.06",
                    commandID: "national-promote-blocked",
                    commandAction: .promote,
                    trigger: .operatorManual,
                    requestedBy: nil,
                    note: nil,
                    validation: nil,
                    guardDecision: nil,
                    execution: nil
                ),
                result: .init(
                    status: .blocked,
                    reasonCode: "candidate_incompatible",
                    message: nil
                )
            )
        )

        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: versionStore,
                activationPolicy: policy,
                refreshStateStore: refreshStateStore,
                activationStateProjector: DefaultSnapshotActivationStateProjector(
                    activationPolicy: policy,
                    historyStore: historyStore,
                    versionStore: versionStore,
                    nowProvider: { "2026-03-16T02:12:00Z" }
                )
            )
        )

        let viewModel = OperatorDashboardViewModel(
            catalogRepository: repository,
            activationHistoryStore: historyStore,
            refreshStateStore: refreshStateStore
        )
        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)
        let seoul = try #require(dashboard.sources.first(where: { $0.source == .seoulCapitalSnapshot }))
        let national = try #require(dashboard.sources.first(where: { $0.source == .koreaNational }))
        let bundled = try #require(dashboard.sources.first(where: { $0.source == .bundledSample }))

        #expect(dashboard.sources.map(\.source) == [.bundledSample, .seoulCapitalSnapshot, .koreaNational])

        #expect(seoul.liveSummary?.metrics.activation.requestedCount == 1)
        #expect(seoul.liveSummary?.metrics.activation.succeededCount == 1)
        #expect(seoul.liveSummary?.metrics.refresh.succeededCount == 1)
        #expect(seoul.healthSummary.state == .healthy)
        #expect(seoul.approvalSummary?.approvalState == .approved)
        #expect(seoul.approvalSummary?.directExecutionCompatible == true)
        #expect(seoul.rolloutReadinessSummary?.state == .immediateReady)
        #expect(seoul.rolloutPreflight?.recommendation == .immediate)
        #expect(seoul.rolloutPreflight?.blockingReasons.isEmpty == true)

        #expect(national.liveSummary?.metrics.activation.requestedCount == 0)
        #expect(national.liveSummary?.metrics.activation.blockedCount == 1)
        #expect(national.liveSummary?.metrics.refresh.failedCount == 1)
        #expect(national.healthSummary.state == .degraded)
        #expect(national.approvalSummary?.approvalState == .awaitingApproval)
        #expect(national.approvalSummary?.directExecutionCompatible == false)
        #expect(national.rolloutReadinessSummary?.state == .notReady)
        #expect(national.rolloutPreflight?.recommendation == .blocked)
        #expect(national.rolloutPreflight?.warningReasons.contains("Pending validation") == true)

        #expect(bundled.liveSummary == nil)
        #expect(bundled.healthSummary.state == .static)
        #expect(bundled.approvalSummary == nil)
        #expect(bundled.rolloutPreflight?.recommendation == .notApplicable)
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

    private func makeBootstrapFileURLs(testName: String) -> (activationState: URL, refresh: URL, history: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTests", isDirectory: true)
            .appendingPathComponent("OperatorDashboardViewModel", isDirectory: true)
            .appendingPathComponent(testName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return (
            activationState: root.appendingPathComponent("activation_state.json", isDirectory: false),
            refresh: root.appendingPathComponent("refresh_state.json", isDirectory: false),
            history: root.appendingPathComponent("activation_history.json", isDirectory: false)
        )
    }
}
