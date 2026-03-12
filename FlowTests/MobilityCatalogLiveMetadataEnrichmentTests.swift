import Testing
@testable import Flow

struct MobilityCatalogLiveMetadataEnrichmentTests {
    @Test
    func enrichesLiveMetadataFromVersionStoreAndActivationState() async throws {
        let store = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()
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
        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: policy,
            historyStore: historyStore,
            versionStore: store,
            nowProvider: { "2026-03-08T01:05:00Z" }
        )

        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: store,
                activationPolicy: policy,
                refreshStateStore: refreshStateStore,
                activationStateProjector: projector
            )
        )

        let catalog = try await repository.fetchCatalog()
        let seoul = try #require(catalog.descriptor(for: .seoulCapitalSnapshot))
        let live = try #require(seoul.liveMetadata)
        let activation = try #require(live.activationMetadata)

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
        #expect(activation.activeSnapshotID == "seoul-2026.03")
        #expect(activation.lastKnownGoodSnapshotID == nil)
        #expect(activation.latestCandidateSnapshotID == "seoul-2026.03")
        #expect(activation.latestCandidateDatasetVersion == "2026.03")
        #expect(activation.latestCandidateCompatibility == .compatible)
        #expect(activation.latestCandidateEligibleForActivation == true)
        #expect(activation.rollbackAvailable == false)
        #expect(activation.latestActivationEventType == nil)
        #expect(activation.operatorActivationStatus == .active)
        #expect(activation.promoteRequiresConfirmation == false)
        #expect(activation.demoteRequiresConfirmation == false)
        #expect(activation.rollbackRequiresConfirmation == false)
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
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: policy,
            historyStore: historyStore,
            versionStore: store,
            nowProvider: { "2026-03-09T02:01:00Z" }
        )

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
                refreshStateStore: refreshStateStore,
                activationStateProjector: projector
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
        #expect(live.activationMetadata?.operatorActivationStatus == .noHistory)
    }

    @Test
    func enrichesOperatorActivationMetadataFromProjectionAndLatestEvent() async throws {
        let store = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        await seed(
            store: store,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-08T00:00:00Z",
            indexedAt: "2026-03-08T01:00:00Z"
        )
        await seed(
            store: store,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            generatedAt: "2026-04-08T00:00:00Z",
            indexedAt: "2026-04-08T01:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                datasetVersion: "2026.04",
                context: SnapshotActivationCommandContext(
                    commandID: "promote-2026-04",
                    requestedAt: "2026-04-08T01:05:00Z",
                    trigger: .operatorConfirmed
                )
            )
        )
        await historyStore.append(
            SnapshotActivationHistoryEvent(
                eventID: "event-promote-success",
                type: .promoteSucceeded,
                timestamp: "2026-04-08T01:06:00Z",
                metadata: SnapshotActivationEventMetadata(
                    source: .seoulCapitalSnapshot,
                    snapshotID: "seoul-2026.04",
                    datasetVersion: "2026.04",
                    commandID: "promote-2026-04",
                    commandAction: command.action,
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
                    message: nil
                )
            )
        )

        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: policy,
            historyStore: historyStore,
            versionStore: store,
            nowProvider: { "2026-04-08T01:07:00Z" }
        )

        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: store,
                activationPolicy: policy,
                refreshStateStore: refreshStateStore,
                activationStateProjector: projector
            )
        )

        let catalog = try await repository.fetchCatalog()
        let seoul = try #require(catalog.descriptor(for: .seoulCapitalSnapshot))
        let live = try #require(seoul.liveMetadata)
        let activation = try #require(live.activationMetadata)

        #expect(activation.activeSnapshotID == "seoul-2026.03")
        #expect(activation.lastKnownGoodSnapshotID == nil)
        #expect(activation.latestCandidateSnapshotID == "seoul-2026.04")
        #expect(activation.latestCandidateDatasetVersion == "2026.04")
        #expect(activation.latestCandidateEligibleForActivation == true)
        #expect(activation.latestCandidateCompatibility == .compatible)
        #expect(activation.latestActivationEventType == SnapshotActivationEventType.promoteSucceeded.rawValue)
        #expect(activation.latestActivationEventAt == "2026-04-08T01:06:00Z")
        #expect(activation.operatorActivationStatus == .active)
        #expect(activation.promoteRequiresConfirmation == true)
        #expect(activation.demoteRequiresConfirmation == false)
        #expect(activation.rollbackRequiresConfirmation == false)
        #expect(activation.rollbackAvailable == false)
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
