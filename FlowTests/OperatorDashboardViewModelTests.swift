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

        #expect(national.liveSummary?.activeSnapshotID == nil)
        #expect(national.liveSummary?.lastRefreshOutcome == .failed)
        #expect(national.liveSummary?.lastRefreshAt == "2026-03-15T03:01:00Z")
        #expect(national.liveSummary?.latestCandidateSnapshotID == nil)
        #expect(national.liveSummary?.metrics.refresh.failedCount == 1)
        #expect(national.liveSummary?.metrics.activation.blockedCount == 1)
        #expect(national.healthSummary.state == .degraded)
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
        #expect(dashboard.sources.map(\.source) == [.bundledSample, .seoulCapitalSnapshot, .koreaNational])
        #expect(dashboard.liveSources.map(\.source) == [.seoulCapitalSnapshot, .koreaNational])
        #expect(dashboard.staticSources.map(\.source) == [.bundledSample])
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
}
