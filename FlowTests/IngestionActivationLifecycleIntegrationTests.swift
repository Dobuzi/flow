import Foundation
import Testing
@testable import Flow

private struct IntegrationSeoulRemoteFetcher: SeoulCapitalRemoteFetching {
    let response: SeoulCapitalRemoteResponse

    func fetch(request: ExternalDatasetFetchRequest) async throws -> SeoulCapitalRemoteResponse {
        response
    }
}

private struct IntegrationRejectingCompatibilityChecker: DatasetCompatibilityChecking {
    func evaluate(dataset: FlowDataset, source: FlowDatasetSource) -> DatasetCompatibilityResult {
        DatasetCompatibilityResult(
            source: source,
            isCompatible: false,
            reasons: ["schema_version_unsupported"],
            checkedFields: ["schemaVersion"],
            missingFields: []
        )
    }
}

private struct IntegrationFailingIntegrityChecker: SnapshotIntegrityChecking {
    func check(
        contract: MaterializedSnapshotContract,
        files: [SnapshotMaterializationInput.FilePayload]
    ) -> SnapshotIntegrityCheckResult {
        SnapshotIntegrityCheckResult(
            isValid: false,
            issues: [
                SnapshotIntegrityIssue(
                    code: "checksum_mismatch:flows",
                    message: "Injected integrity mismatch for integration scenario",
                    severity: .error
                )
            ]
        )
    }
}

private struct IntegrationVersionAwareFlowRepository: FlowRepository {
    let source: FlowDatasetSource
    let resolution: ActivatedSnapshotResolution

    func fetchDataset() async throws -> FlowDataset {
        let datasetID = resolution.isUsingActivatedSnapshot
            ? (resolution.activatedSnapshotID ?? "activated-unknown")
            : "stable-\(source.rawValue)"
        let version = resolution.isUsingActivatedSnapshot
            ? (resolution.activatedDatasetVersion ?? "unknown")
            : "stable"

        return FlowDataset(
            datasetID: datasetID,
            version: version,
            source: source.rawValue,
            createdAt: "2026-03-08T00:00:00Z",
            spatialLevel: .city,
            timeCoverage: "2026-03",
            recordsCount: 1,
            schemaVersion: "1.0.0"
        )
    }

    func fetchFlowRecords() async throws -> [FlowRecord] {
        [
            FlowRecord(
                id: "f-1",
                originNodeID: "A01",
                destinationNodeID: "B01",
                transportMode: .rail,
                timeBucketID: "H:2026-03|08",
                volume: 120,
                unitType: .passengers,
                metadata: nil
            )
        ]
    }
}

private struct IntegrationLocationRepository: LocationRepository {
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

private struct IntegrationCatalogRepository: MobilityCatalogRepository {
    let catalog: MobilityDatasetCatalog

    func fetchCatalog() async throws -> MobilityDatasetCatalog {
        catalog
    }
}

@MainActor
struct IngestionActivationLifecycleIntegrationTests {
    @Test
    func successfulSeoulIngestionActivationFeedsActivationAwareQueryPath() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)

        let adapter = SeoulCapitalExternalDatasetAdapter(
            remoteFetcher: IntegrationSeoulRemoteFetcher(response: makeSeoulRemoteResponse(schemaVersion: "1.0.0"))
        )

        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: adapter,
            materializer: DefaultSnapshotMaterializer(),
            datasetVersionStore: store
        )

        let ingestResult = try await coordinator.ingest(request: .init(fetchRequest: makeSeoulFetchRequest()))
        #expect(ingestResult.status == .succeeded)
        #expect(ingestResult.contract?.source == .seoulCapitalSnapshot)

        let activationDecision = await policy.evaluateActivation(source: .seoulCapitalSnapshot, requestedSnapshotID: nil)
        #expect(activationDecision.status == .activatable)

        let activationState = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: nil)
        #expect(activationState.activeSnapshotID == ingestResult.contract?.snapshotID)

        let resolver = DefaultActivatedSnapshotResolver(
            catalogRepository: MobilityRepositoryFactory.liveAwareCatalogRepository(
                versionStore: store,
                activationPolicy: policy,
                refreshStateStore: nil
            ),
            versionStore: store,
            activationPolicy: policy
        )

        let adapterForQuery = DefaultMobilityQueryAdapter(
            flowRepositoryBuilder: { source, resolution in
                IntegrationVersionAwareFlowRepository(source: source, resolution: resolution)
            },
            locationRepositoryBuilder: { _, _ in
                IntegrationLocationRepository()
            },
            activatedSnapshotResolver: resolver
        )

        let queryResult = try await adapterForQuery.execute(makeSeoulQuery())

        #expect(queryResult.sources == Set([FlowDatasetSource.seoulCapitalSnapshot]))
        #expect(queryResult.datasetIDs.first == ingestResult.contract?.snapshotID)
        #expect(queryResult.compatibilityNotes.contains { $0.hasPrefix("activation_snapshot_id:") })
        #expect(queryResult.compatibilityNotes.contains { $0.hasPrefix("activation_dataset_version:") })
        #expect(!queryResult.compatibilityNotes.contains { $0.hasPrefix("activation_fallback:") })
    }

    @Test
    func liveSourceWithoutActivationFallsBackToStablePathSafely() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)

        let catalog = MobilityDatasetCatalog(
            version: "1.0.0",
            defaultSource: .bundledSample,
            datasets: [
                MobilityDatasetDescriptor(
                    id: "seoul-capital-live",
                    datasetID: "seoul-capital-living-mobility",
                    source: .seoulCapitalSnapshot,
                    providerID: "seoul_open_data_plaza",
                    displayName: "Seoul Capital Mobility",
                    version: "2026.03",
                    schemaVersion: "1.0.0",
                    updatedAt: "2026-03-08T00:00:00Z",
                    availableModes: TransportMode.allCases,
                    supportedSpatialLevels: [.city],
                    supportedGranularities: [.hourOfDay],
                    reliability: .high,
                    spatialPrecision: .district,
                    temporalPrecision: .hour,
                    qualityScore: 0.9,
                    liveMetadata: DatasetLiveMetadata(
                        supportsLiveRefresh: true,
                        latestKnownDatasetVersion: nil,
                        latestKnownSnapshotID: nil,
                        lastRefreshAttemptAt: nil,
                        lastSuccessfulRefreshAt: nil,
                        activeSnapshotID: nil,
                        lastKnownGoodSnapshotID: nil,
                        readiness: .pendingValidation,
                        syncState: .idle
                    )
                )
            ]
        )

        let resolver = DefaultActivatedSnapshotResolver(
            catalogRepository: IntegrationCatalogRepository(catalog: catalog),
            versionStore: store,
            activationPolicy: policy
        )

        let adapterForQuery = DefaultMobilityQueryAdapter(
            flowRepositoryBuilder: { source, resolution in
                IntegrationVersionAwareFlowRepository(source: source, resolution: resolution)
            },
            locationRepositoryBuilder: { _, _ in
                IntegrationLocationRepository()
            },
            activatedSnapshotResolver: resolver
        )

        let queryResult = try await adapterForQuery.execute(makeSeoulQuery())

        #expect(queryResult.sources == Set([FlowDatasetSource.seoulCapitalSnapshot]))
        #expect(!queryResult.compatibilityNotes.contains { $0.hasPrefix("activation_snapshot_id:") })
    }

    @Test
    func compatibilityRejectedCandidateDoesNotBecomeActivationConsumable() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)

        let adapter = SeoulCapitalExternalDatasetAdapter(
            remoteFetcher: IntegrationSeoulRemoteFetcher(response: makeSeoulRemoteResponse(schemaVersion: "1.0.0"))
        )

        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: adapter,
            materializer: DefaultSnapshotMaterializer(),
            compatibilityChecker: IntegrationRejectingCompatibilityChecker(),
            datasetVersionStore: store
        )

        do {
            _ = try await coordinator.ingest(request: .init(fetchRequest: makeSeoulFetchRequest()))
            Issue.record("Expected compatibility gate failure")
        } catch let error as IngestionPipelineError {
            switch error {
            case .compatibilityFailed(let classification, _):
                #expect(classification == .incompatible)
            default:
                Issue.record("Unexpected ingestion error: \(error)")
            }
        }

        let decision = await policy.evaluateActivation(source: .seoulCapitalSnapshot, requestedSnapshotID: nil)
        #expect(decision.status == .noCandidate)

        let resolver = DefaultActivatedSnapshotResolver(
            catalogRepository: MobilityRepositoryFactory.liveAwareCatalogRepository(
                versionStore: store,
                activationPolicy: policy,
                refreshStateStore: nil
            ),
            versionStore: store,
            activationPolicy: policy
        )

        let adapterForQuery = DefaultMobilityQueryAdapter(
            flowRepositoryBuilder: { source, resolution in
                IntegrationVersionAwareFlowRepository(source: source, resolution: resolution)
            },
            locationRepositoryBuilder: { _, _ in
                IntegrationLocationRepository()
            },
            activatedSnapshotResolver: resolver
        )

        let queryResult = try await adapterForQuery.execute(makeSeoulQuery())
        #expect(queryResult.compatibilityNotes.contains("activation_fallback:noActiveSnapshot"))
        #expect(!queryResult.compatibilityNotes.contains { $0.hasPrefix("activation_snapshot_id:") })
    }

    @Test
    func integrityFailurePreventsActivationCandidateRegistration() async {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)

        let adapter = SeoulCapitalExternalDatasetAdapter(
            remoteFetcher: IntegrationSeoulRemoteFetcher(response: makeSeoulRemoteResponse(schemaVersion: "1.0.0"))
        )

        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: adapter,
            materializer: DefaultSnapshotMaterializer(),
            integrityChecker: IntegrationFailingIntegrityChecker(),
            datasetVersionStore: store
        )

        await #expect(throws: IngestionPipelineError.integrityFailed(["checksum_mismatch:flows"])) {
            _ = try await coordinator.ingest(request: .init(fetchRequest: makeSeoulFetchRequest()))
        }

        let decision = await policy.evaluateActivation(source: .seoulCapitalSnapshot, requestedSnapshotID: nil)
        #expect(decision.status == .noCandidate)
    }

    @Test
    func staticSourceIgnoresActivationMetadataAndBehaviorStaysStable() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)

        let resolver = DefaultActivatedSnapshotResolver(
            catalogRepository: MobilityRepositoryFactory.liveAwareCatalogRepository(
                versionStore: store,
                activationPolicy: policy,
                refreshStateStore: nil
            ),
            versionStore: store,
            activationPolicy: policy
        )

        let adapterForQuery = DefaultMobilityQueryAdapter(
            flowRepositoryBuilder: { source, resolution in
                IntegrationVersionAwareFlowRepository(source: source, resolution: resolution)
            },
            locationRepositoryBuilder: { _, _ in
                IntegrationLocationRepository()
            },
            activatedSnapshotResolver: resolver
        )

        let result = try await adapterForQuery.execute(
            MobilityQuery(
                sources: [.bundledSample],
                selectedModes: [.rail],
                spatialLevel: .city,
                timeContext: MobilityTimeContext(year: 2026, month: 3, hour: 8, granularity: .hourOfDay),
                aggregation: .default
            )
        )

        #expect(result.sources == Set([FlowDatasetSource.bundledSample]))
        #expect(result.compatibilityNotes.allSatisfy { !$0.hasPrefix("activation_") })
    }

    @Test
    func runtimeSnapshotBackedSourcesRemainUsableAfterLifecycleWiring() async throws {
        for source in [FlowDatasetSource.bundledSample, .seoulCapitalSnapshot, .koreaNational] {
            let dataset = try await MobilityRepositoryFactory.flowRepository(for: source).fetchDataset()
            #expect(!dataset.datasetID.isEmpty)
        }
    }

    private func makeSeoulFetchRequest() -> ExternalDatasetFetchRequest {
        ExternalDatasetFetchRequest(
            source: .seoulCapitalSnapshot,
            providerID: "seoul_open_data",
            expectedSchemaVersion: "1.0.0",
            preferredUpstreamVersion: nil,
            requestID: "int-req-1"
        )
    }

    private func makeSeoulQuery() -> MobilityQuery {
        MobilityQuery(
            sources: [.seoulCapitalSnapshot],
            selectedModes: [.rail],
            spatialLevel: .city,
            timeContext: MobilityTimeContext(year: 2026, month: 3, hour: 8, granularity: .hourOfDay),
            aggregation: .default
        )
    }

    private func makeSeoulRemoteResponse(schemaVersion: String) -> SeoulCapitalRemoteResponse {
        SeoulCapitalRemoteResponse(
            fetchedAt: "2026-03-08T00:00:00Z",
            files: [
                .manifest: Data(makeManifestJSON(schemaVersion: schemaVersion).utf8),
                .nodes: Data(makeNodesJSON().utf8),
                .flows: Data(makeFlowsJSONL().utf8)
            ],
            metadata: ["upstream": "seoul_open_data_plaza"]
        )
    }

    private func makeManifestJSON(schemaVersion: String) -> String {
        #"{"datasetId":"seoul-capital-living-mobility","version":"2026.03","source":"seoul_open_data","generatedAt":"2026-03-08T00:00:00Z","coverageStart":"2026-03-01","coverageEnd":"2026-03-31","schemaVersion":"\#(schemaVersion)"}"#
    }

    private func makeNodesJSON() -> String {
        #"[{"zoneId":"A01","zoneNameKo":"강남","zoneNameEn":"Gangnam","latitude":37.4979,"longitude":127.0276,"sidoCode":"11","regionType":"district","importanceRank":1},{"zoneId":"B01","zoneNameKo":"종로","zoneNameEn":"Jongno","latitude":37.5729,"longitude":126.9793,"sidoCode":"11","regionType":"district","importanceRank":2}]"#
    }

    private func makeFlowsJSONL() -> String {
        [
            #"{"date":"2026-03-08","hour":8,"originZoneId":"A01","destinationZoneId":"B01","transportMode":"subway","movementCount":120.0,"dataSourceTag":"seoul_open_data","confidenceScore":0.93}"#,
            #"{"date":"2026-03-08","hour":9,"originZoneId":"B01","destinationZoneId":"A01","transportMode":"bus","movementCount":95.0,"dataSourceTag":"seoul_open_data","confidenceScore":0.90}"#
        ].joined(separator: "\n")
    }
}
