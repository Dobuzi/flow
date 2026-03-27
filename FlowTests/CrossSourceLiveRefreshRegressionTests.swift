import Foundation
import Testing
@testable import Flow

private final class ResolutionRecorder {
    private var entries: [FlowDatasetSource: ActivatedSnapshotResolution] = [:]
    private let lock = NSLock()

    func record(source: FlowDatasetSource, resolution: ActivatedSnapshotResolution) {
        lock.lock()
        entries[source] = resolution
        lock.unlock()
    }

    func resolution(for source: FlowDatasetSource) -> ActivatedSnapshotResolution? {
        lock.lock()
        let value = entries[source]
        lock.unlock()
        return value
    }
}

private struct CrossSourceFlowRepository: FlowRepository {
    let source: FlowDatasetSource
    let resolution: ActivatedSnapshotResolution

    func fetchDataset() async throws -> FlowDataset {
        let version = resolution.activatedDatasetVersion ?? "stable"
        let datasetID = resolution.isUsingActivatedSnapshot
            ? (resolution.activatedSnapshotID ?? "activated-unknown")
            : "stable-\(source.rawValue)"

        return FlowDataset(
            datasetID: datasetID,
            version: version,
            source: source.rawValue,
            createdAt: "2026-03-09T00:00:00Z",
            spatialLevel: .city,
            timeCoverage: "2026-03",
            recordsCount: 1,
            schemaVersion: "1.0.0"
        )
    }

    func fetchFlowRecords() async throws -> [FlowRecord] {
        [
            FlowRecord(
                id: "f-\(source.rawValue)",
                originNodeID: "A01",
                destinationNodeID: "B01",
                transportMode: .rail,
                timeBucketID: "H:2026-03|08",
                volume: 42,
                unitType: .passengers,
                metadata: nil
            )
        ]
    }
}

private struct CrossSourceLocationRepository: LocationRepository {
    func fetchLocationNodes() async throws -> [LocationNode] {
        [
            LocationNode(
                id: "A01",
                nameKo: "강남",
                nameEn: "Gangnam",
                lat: 37.4979,
                lon: 127.0276,
                regionCode: "11",
                regionType: "district",
                importanceRank: 1
            ),
            LocationNode(
                id: "B01",
                nameKo: "종로",
                nameEn: "Jongno",
                lat: 37.5729,
                lon: 126.9793,
                regionCode: "11",
                regionType: "district",
                importanceRank: 2
            )
        ]
    }
}

@MainActor
struct CrossSourceLiveRefreshRegressionTests {
    @Test
    func seoulActivationExecutionDoesNotMutateBundledOrNationalState() async throws {
        let store = InMemoryDatasetVersionStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: store,
            historyStore: historyStore
        )

        await seedCompatibleSnapshot(
            store: store,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            version: "2026.03"
        )
        await seedCompatibleSnapshot(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.03",
            version: "2026.03"
        )

        let result = await executor.execute(
            .promote(
                PromoteSnapshotCommand(
                    source: .seoulCapitalSnapshot,
                    snapshotID: "seoul-2026.03",
                    context: .init(
                        commandID: "cmd-cross-source-promote",
                        requestedAt: "2026-03-12T00:00:00Z",
                        trigger: .operatorConfirmed
                    )
                )
            )
        )

        #expect(result.status == .succeeded)

        let seoulState = await policy.currentState(for: .seoulCapitalSnapshot)
        #expect(seoulState.activeSnapshotID == "seoul-2026.03")

        let bundledState = await policy.currentState(for: .bundledSample)
        #expect(bundledState.activeSnapshotID == nil)
        #expect(bundledState.lastKnownGoodSnapshotID == nil)

        let nationalState = await policy.currentState(for: .koreaNational)
        #expect(nationalState.activeSnapshotID == nil)
        #expect(nationalState.lastKnownGoodSnapshotID == nil)

        let seoulHistory = await historyStore.events(for: .seoulCapitalSnapshot)
        #expect(seoulHistory.count == 2)
        let bundledHistory = await historyStore.events(for: .bundledSample)
        #expect(bundledHistory.isEmpty)
        let nationalHistory = await historyStore.events(for: .koreaNational)
        #expect(nationalHistory.isEmpty)
    }

    @Test
    func projectionAndHistoryRemainSourceScopedAfterSeoulActivation() async throws {
        let store = InMemoryDatasetVersionStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: store,
            historyStore: historyStore
        )
        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: policy,
            historyStore: historyStore,
            versionStore: store,
            nowProvider: { "2026-03-12T00:00:00Z" }
        )

        await seedCompatibleSnapshot(
            store: store,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            version: "2026.03"
        )
        await seedCompatibleSnapshot(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.03",
            version: "2026.03"
        )

        _ = await executor.execute(
            .promote(
                PromoteSnapshotCommand(
                    source: .seoulCapitalSnapshot,
                    snapshotID: "seoul-2026.03",
                    context: .init(
                        commandID: "cmd-projection-seoul",
                        requestedAt: "2026-03-12T00:00:00Z",
                        trigger: .operatorConfirmed
                    )
                )
            )
        )

        let seoulProjection = await projector.project(for: .seoulCapitalSnapshot)
        #expect(seoulProjection.activeSnapshotID == "seoul-2026.03")
        #expect(seoulProjection.hasActivationHistory == true)
        #expect(seoulProjection.latestActivationEvent?.metadata.source == .seoulCapitalSnapshot)

        let nationalProjection = await projector.project(for: .koreaNational)
        #expect(nationalProjection.activeSnapshotID == nil)
        #expect(nationalProjection.latestCandidateSnapshotID == "national-2026.03")
        #expect(nationalProjection.hasActivationHistory == false)
        #expect(nationalProjection.latestActivationEvent == nil)

        let bundledProjection = await projector.project(for: .bundledSample)
        #expect(bundledProjection.activeSnapshotID == nil)
        #expect(bundledProjection.latestCandidateSnapshotID == nil)
        #expect(bundledProjection.hasActivationHistory == false)
    }

    @Test
    func mixedSourceSettingsStateKeepsOperatorHistoryAndControlsScoped() async throws {
        let store = InMemoryDatasetVersionStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let proposalAuditStore = InMemoryRolloutProposalAuditStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: policy,
            historyStore: historyStore,
            versionStore: store,
            nowProvider: { "2026-03-12T00:00:00Z" }
        )
        let catalogRepository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: store,
                activationPolicy: policy,
                refreshStateStore: refreshStateStore,
                activationStateProjector: projector
            )
        )
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: store,
            historyStore: historyStore
        )

        await seedCompatibleSnapshot(
            store: store,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            version: "2026.03"
        )
        await seedCompatibleSnapshot(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.03",
            version: "2026.03"
        )
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        await historyStore.append(
            SnapshotActivationHistoryEvent(
                eventID: "seoul-history-1",
                type: .promoteSucceeded,
                timestamp: "2026-03-12T01:00:00Z",
                metadata: SnapshotActivationEventMetadata(
                    source: .seoulCapitalSnapshot,
                    snapshotID: "seoul-2026.03",
                    datasetVersion: "2026.03",
                    commandID: "cmd-seoul-history",
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
                    message: "Seoul promoted."
                )
            )
        )

        await proposalAuditStore.append(
            RolloutProposalAuditEvent(
                id: "seoul-proposal-approved",
                proposalID: "proposal-seoul-2026.03",
                source: .seoulCapitalSnapshot,
                targetSnapshotID: "seoul-2026.03",
                targetDatasetVersion: "2026.03",
                action: .promote,
                type: .proposalApproved,
                timestamp: "2026-03-12T02:00:00Z",
                actor: "operator",
                reason: "Ready for rollout"
            )
        )

        let bundledViewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .bundledSample)) },
            catalogRepository: catalogRepository,
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            proposalAuditStore: proposalAuditStore,
            userDefaults: UserDefaults(suiteName: "CrossSourceLiveRefreshRegressionTests.settings.bundled.\(UUID().uuidString)")!
        )
        await bundledViewModel.load(source: .bundledSample)
        #expect(bundledViewModel.operatorControls == nil)

        let nationalViewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .koreaNational)) },
            catalogRepository: catalogRepository,
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            proposalAuditStore: proposalAuditStore,
            userDefaults: UserDefaults(suiteName: "CrossSourceLiveRefreshRegressionTests.settings.national.\(UUID().uuidString)")!
        )
        await nationalViewModel.load(source: .koreaNational)

        let nationalControls = try #require(nationalViewModel.operatorControls)
        #expect(nationalControls.activeSnapshotID == nil)
        #expect(nationalControls.latestCandidateSnapshotID == "national-2026.03")
        #expect(nationalControls.recentHistory.isEmpty)
        #expect(nationalControls.latestActivationEventSummary == nil)
        #expect(nationalControls.timelineHistory.isEmpty)

        let seoulViewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: catalogRepository,
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            proposalAuditStore: proposalAuditStore,
            userDefaults: UserDefaults(suiteName: "CrossSourceLiveRefreshRegressionTests.settings.seoul.\(UUID().uuidString)")!
        )
        await seoulViewModel.load(source: .seoulCapitalSnapshot)

        let seoulControls = try #require(seoulViewModel.operatorControls)
        #expect(seoulControls.activeSnapshotID == "seoul-2026.03")
        #expect(seoulControls.recentHistory.count == 2)
        #expect(seoulControls.recentHistory.first?.proposalID == "proposal-seoul-2026.03")
        #expect(seoulControls.recentHistory.first?.title == "Proposal Approved")
        #expect(seoulControls.recentHistory.last?.snapshotID == "seoul-2026.03")
        #expect(seoulControls.recentHistory.last?.title == "Promote Succeeded")
    }

    @Test
    func bundledSampleRemainsIsolatedFromLiveActivationMetadata() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let recorder = ResolutionRecorder()

        await seedCompatibleSnapshot(
            store: store,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            version: "2026.03"
        )
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let resolver = MobilityRepositoryFactory.activatedSnapshotResolver(
            versionStore: store,
            activationPolicy: policy,
            refreshStateStore: InMemoryDatasetRefreshStateStore()
        )

        let adapter = DefaultMobilityQueryAdapter(
            flowRepositoryBuilder: { source, resolution in
                recorder.record(source: source, resolution: resolution)
                return CrossSourceFlowRepository(source: source, resolution: resolution)
            },
            locationRepositoryBuilder: { _, _ in CrossSourceLocationRepository() },
            activatedSnapshotResolver: resolver
        )

        let result = try await adapter.execute(makeQuery(source: .bundledSample))

        #expect(result.sources == Set([FlowDatasetSource.bundledSample]))
        #expect(result.datasetIDs.first == "stable-\(FlowDatasetSource.bundledSample.rawValue)")
        #expect(result.compatibilityNotes.allSatisfy { !$0.hasPrefix("activation_") })

        let resolution = recorder.resolution(for: .bundledSample)
        #expect(resolution?.isLiveCapable == false)
        #expect(resolution?.isUsingActivatedSnapshot == false)
        #expect(resolution?.fallbackReason == .staticSource)
    }

    @Test
    func seoulAndKoreaStayIsolatedAcrossActivationAwareQueryConsumption() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)

        await seedCompatibleSnapshot(
            store: store,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            version: "2026.03"
        )
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let resolver = MobilityRepositoryFactory.activatedSnapshotResolver(
            versionStore: store,
            activationPolicy: policy,
            refreshStateStore: InMemoryDatasetRefreshStateStore()
        )

        let adapter = DefaultMobilityQueryAdapter(
            flowRepositoryBuilder: { source, resolution in
                CrossSourceFlowRepository(source: source, resolution: resolution)
            },
            locationRepositoryBuilder: { _, _ in CrossSourceLocationRepository() },
            activatedSnapshotResolver: resolver
        )

        let seoulResult = try await adapter.execute(makeQuery(source: .seoulCapitalSnapshot))
        #expect(seoulResult.datasetIDs.first == "seoul-2026.03")
        #expect(seoulResult.compatibilityNotes.contains { $0.hasPrefix("activation_snapshot_id:seoul-2026.03") })

        let nationalResult = try await adapter.execute(makeQuery(source: .koreaNational))
        #expect(nationalResult.datasetIDs.first == "stable-\(FlowDatasetSource.koreaNational.rawValue)")
        #expect(!nationalResult.compatibilityNotes.contains { $0.contains("seoul-2026.03") })
        #expect(nationalResult.compatibilityNotes.contains("activation_fallback:noActiveSnapshot"))
    }

    @Test
    func ineligibleSeoulCandidateDoesNotPolluteOtherSources() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)

        await seedIncompatibleSnapshot(
            store: store,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04-bad",
            version: "2026.04"
        )

        let resolver = MobilityRepositoryFactory.activatedSnapshotResolver(
            versionStore: store,
            activationPolicy: policy,
            refreshStateStore: InMemoryDatasetRefreshStateStore()
        )

        let adapter = DefaultMobilityQueryAdapter(
            flowRepositoryBuilder: { source, resolution in
                CrossSourceFlowRepository(source: source, resolution: resolution)
            },
            locationRepositoryBuilder: { _, _ in CrossSourceLocationRepository() },
            activatedSnapshotResolver: resolver
        )

        let seoulResult = try await adapter.execute(makeQuery(source: .seoulCapitalSnapshot))
        #expect(seoulResult.datasetIDs.first == "stable-\(FlowDatasetSource.seoulCapitalSnapshot.rawValue)")
        #expect(seoulResult.compatibilityNotes.contains("activation_fallback:noActiveSnapshot"))

        let sampleResult = try await adapter.execute(makeQuery(source: .bundledSample))
        #expect(sampleResult.datasetIDs.first == "stable-\(FlowDatasetSource.bundledSample.rawValue)")
        #expect(sampleResult.compatibilityNotes.allSatisfy { !$0.hasPrefix("activation_") })
    }

    @Test
    func mixedCatalogEnrichmentKeepsStaticEntryCleanAndLiveEntriesConsistent() async throws {
        let store = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)

        await seedCompatibleSnapshot(
            store: store,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            version: "2026.03"
        )
        await seedCompatibleSnapshot(
            store: store,
            source: .koreaNational,
            snapshotID: "national-2026.03",
            version: "2026.03"
        )

        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        await refreshStateStore.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-09T01:00:00Z",
                finishedAt: "2026-03-09T01:00:10Z",
                storedSnapshotID: "seoul-2026.03",
                storedDatasetVersion: "2026.03",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
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

        #expect(catalog.descriptor(for: .bundledSample)?.liveMetadata == nil)

        let seoulLive = try #require(catalog.descriptor(for: .seoulCapitalSnapshot)?.liveMetadata)
        #expect(seoulLive.activeSnapshotID == "seoul-2026.03")
        #expect(seoulLive.latestKnownSnapshotID == "seoul-2026.03")
        #expect(seoulLive.lastRefreshOutcome == .success)

        let nationalLive = try #require(catalog.descriptor(for: .koreaNational)?.liveMetadata)
        #expect(nationalLive.activeSnapshotID == nil)
        #expect(nationalLive.latestKnownSnapshotID == "national-2026.03")
    }

    @Test
    func periodicRefreshOnlyTargetsLiveCapableSourcesInMixedCatalog() async {
        let scheduler = DefaultDatasetRefreshScheduler(
            catalogRepository: LocalMobilityCatalogRepository(),
            coordinatorRegistry: [
                .seoulCapitalSnapshot: CrossSourceStubCoordinator(snapshotID: "seoul-2026.03"),
                .koreaNational: CrossSourceStubCoordinator(snapshotID: "national-2026.03")
            ],
            minimumPeriodicInterval: 0
        )

        let results = await scheduler.triggerPeriodicRefresh()

        #expect(results.count == 2)
        #expect(Set(results.map(\.source)) == Set([.seoulCapitalSnapshot, .koreaNational]))
        #expect(results.allSatisfy { $0.status == .succeeded })
        #expect(!results.contains { $0.source == .bundledSample })
    }

    @Test
    func repositoryFactoryRuntimePathsRemainDeterministicAcrossSources() async throws {
        var datasetIDs: Set<String> = []
        for source in [FlowDatasetSource.bundledSample, .seoulCapitalSnapshot, .koreaNational] {
            let flowRepo = MobilityRepositoryFactory.flowRepository(for: source)
            let locationRepo = MobilityRepositoryFactory.locationRepository(for: source)

            let dataset = try await flowRepo.fetchDataset()
            let nodes = try await locationRepo.fetchLocationNodes()

            #expect(!dataset.source.isEmpty)
            #expect(!dataset.datasetID.isEmpty)
            #expect(!nodes.isEmpty)
            datasetIDs.insert(dataset.datasetID)
        }
        #expect(datasetIDs.count == 3)
    }

    private func makeQuery(source: FlowDatasetSource) -> MobilityQuery {
        MobilityQuery(
            sources: [source],
            selectedModes: [.rail],
            spatialLevel: .city,
            timeContext: MobilityTimeContext(year: 2026, month: 3, hour: 8, granularity: .hourOfDay),
            aggregation: .default
        )
    }

    private func seedCompatibleSnapshot(
        store: InMemoryDatasetVersionStore,
        source: FlowDatasetSource,
        snapshotID: String,
        version: String
    ) async {
        await store.upsert(
            contract: makeContract(source: source, snapshotID: snapshotID, version: version, activationState: .eligible),
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: "2026-03-09T00:00:00Z"
        )
    }

    private func seedIncompatibleSnapshot(
        store: InMemoryDatasetVersionStore,
        source: FlowDatasetSource,
        snapshotID: String,
        version: String
    ) async {
        await store.upsert(
            contract: makeContract(source: source, snapshotID: snapshotID, version: version, activationState: .ineligible),
            compatibilityClassification: .incompatible,
            isIngestionCandidate: true,
            indexedAt: "2026-03-09T00:00:00Z"
        )
    }

    private func makeContract(
        source: FlowDatasetSource,
        snapshotID: String,
        version: String,
        activationState: SnapshotActivationEligibility.State
    ) -> MaterializedSnapshotContract {
        MaterializedSnapshotContract(
            snapshotID: snapshotID,
            source: source,
            schemaVersion: "1.0.0",
            datasetVersion: version,
            generatedAt: "2026-03-09T00:00:00Z",
            timeCoverage: "2026-03-01~2026-03-31",
            spatialCoverage: .city,
            recordsCount: 1,
            requiredFiles: [
                SnapshotRequiredFile(role: .manifest, relativePath: "manifest.json", checksumSHA256: "m", byteCount: 10, recordCount: nil),
                SnapshotRequiredFile(role: .nodes, relativePath: "nodes.json", checksumSHA256: "n", byteCount: 20, recordCount: 2),
                SnapshotRequiredFile(role: .flows, relativePath: "flows.jsonl", checksumSHA256: "f", byteCount: 30, recordCount: 1)
            ],
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: activationState == .eligible,
                compatibilityReasons: activationState == .eligible ? [] : ["schema_version_unsupported"],
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(
                state: activationState,
                reasons: activationState == .eligible ? [] : ["activation_ineligible"]
            )
        )
    }
}

private struct CrossSourceStubCoordinator: IngestionPipelineCoordinating {
    let snapshotID: String

    func ingest(request: IngestionPipelineRequest) async throws -> IngestionPipelineResult {
        IngestionPipelineResult(
            status: .succeeded,
            contract: MaterializedSnapshotContract(
                snapshotID: snapshotID,
                source: request.fetchRequest.source,
                schemaVersion: "1.0.0",
                datasetVersion: "2026.03",
                generatedAt: "2026-03-09T00:00:00Z",
                timeCoverage: "2026-03-01~2026-03-31",
                spatialCoverage: .city,
                recordsCount: 1,
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
            ),
            materializationWarnings: [],
            schemaValidation: DatasetSchemaValidationResult(
                schemaVersion: "1.0.0",
                supportedVersions: ["1.0.0"],
                isCompatible: true,
                reason: nil
            ),
            compatibilityGate: IngestionPipelineResult.CompatibilityGate(
                classification: .compatible,
                result: DatasetCompatibilityResult(
                    source: request.fetchRequest.source,
                    isCompatible: true,
                    reasons: [],
                    checkedFields: ["schemaVersion"],
                    missingFields: []
                )
            ),
            stepStatus: IngestionPipelineResult.StepStatus(
                adapterFetched: true,
                payloadValidated: true,
                materializerInvoked: true,
                contractValidated: true,
                schemaValidated: true,
                compatibilityEvaluated: true,
                compatibilityPassed: true
            )
        )
    }
}

private struct StubFlowRepository: FlowRepository {
    let dataset: FlowDataset

    func fetchDataset() async throws -> FlowDataset {
        dataset
    }

    func fetchFlowRecords() async throws -> [FlowRecord] {
        []
    }
}

private func makeDataset(source: FlowDatasetSource) -> FlowDataset {
    FlowDataset(
        datasetID: "dataset-\(source.rawValue)",
        version: "2025.01.snapshot1",
        source: source.rawValue,
        createdAt: "2026-03-01T00:00:00Z",
        spatialLevel: .city,
        timeCoverage: "2025-01-01~2025-01-31",
        recordsCount: source == .bundledSample ? 4 : 8,
        schemaVersion: "1.0.0"
    )
}
