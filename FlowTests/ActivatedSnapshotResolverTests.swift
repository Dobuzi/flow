import Testing
@testable import Flow

private struct StubCatalogRepositoryForResolver: MobilityCatalogRepository {
    let catalog: MobilityDatasetCatalog

    func fetchCatalog() async throws -> MobilityDatasetCatalog {
        catalog
    }
}

private struct StubActivationPolicyForResolver: SnapshotActivationPolicying {
    let state: SnapshotActivationState

    func currentState(for source: FlowDatasetSource) async -> SnapshotActivationState {
        state
    }

    func evaluateActivation(source: FlowDatasetSource, requestedSnapshotID: String?) async -> SnapshotActivationDecision {
        SnapshotActivationDecision(
            source: source,
            requestedSnapshotID: requestedSnapshotID,
            status: .noCandidate,
            candidate: nil,
            reasons: []
        )
    }

    func activate(source: FlowDatasetSource, requestedSnapshotID: String?) async throws -> SnapshotActivationState {
        state
    }

    func evaluateRollback(source: FlowDatasetSource) async -> SnapshotRollbackDecision {
        SnapshotRollbackDecision(source: source, status: .noSafeRollback, target: nil, reasons: [])
    }

    func rollback(source: FlowDatasetSource) async throws -> SnapshotActivationState {
        state
    }
}

struct ActivatedSnapshotResolverTests {
    @Test
    func fallsBackWhenLiveSourceHasNoActiveSnapshot() async {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let resolver = DefaultActivatedSnapshotResolver(
            catalogRepository: StubCatalogRepositoryForResolver(catalog: makeCatalog()),
            versionStore: store,
            activationPolicy: policy
        )

        let resolution = await resolver.resolve(for: .seoulCapitalSnapshot)
        #expect(resolution.isLiveCapable)
        #expect(!resolution.isUsingActivatedSnapshot)
        #expect(resolution.fallbackReason == .noActiveSnapshot)
    }

    @Test
    func resolvesActivatedSnapshotForLiveSource() async {
        let store = InMemoryDatasetVersionStore()
        let contract = makeContract(
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03"
        )
        await store.upsert(
            contract: contract,
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: "2026-03-08T01:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        _ = try? await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let resolver = DefaultActivatedSnapshotResolver(
            catalogRepository: StubCatalogRepositoryForResolver(catalog: makeCatalog()),
            versionStore: store,
            activationPolicy: policy
        )

        let resolution = await resolver.resolve(for: .seoulCapitalSnapshot)
        #expect(resolution.isUsingActivatedSnapshot)
        #expect(resolution.activatedSnapshotID == "seoul-2026.03")
        #expect(resolution.activatedDatasetVersion == "2026.03")
        #expect(resolution.compatibilityClassification == .compatible)
    }

    @Test
    func ignoresIneligibleActiveSnapshotAndFallsBackSafely() async {
        let store = InMemoryDatasetVersionStore()
        let contract = makeContract(
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-bad",
            datasetVersion: "2026.04",
            activationState: .ineligible
        )
        await store.upsert(
            contract: contract,
            compatibilityClassification: .incompatible,
            isIngestionCandidate: false,
            indexedAt: "2026-03-08T02:00:00Z"
        )

        let policy = StubActivationPolicyForResolver(
            state: SnapshotActivationState(
                source: .seoulCapitalSnapshot,
                activeSnapshotID: "seoul-bad",
                lastKnownGoodSnapshotID: nil,
                updatedAt: "2026-03-08T03:00:00Z"
            )
        )

        let resolver = DefaultActivatedSnapshotResolver(
            catalogRepository: StubCatalogRepositoryForResolver(catalog: makeCatalog()),
            versionStore: store,
            activationPolicy: policy
        )

        let resolution = await resolver.resolve(for: .seoulCapitalSnapshot)
        #expect(!resolution.isUsingActivatedSnapshot)
        #expect(resolution.fallbackReason == .activeSnapshotIneligible)
    }

    @Test
    func staticSourcesIgnoreActivationMetadata() async {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let resolver = DefaultActivatedSnapshotResolver(
            catalogRepository: StubCatalogRepositoryForResolver(catalog: makeCatalog()),
            versionStore: store,
            activationPolicy: policy
        )

        let resolution = await resolver.resolve(for: .bundledSample)
        #expect(!resolution.isLiveCapable)
        #expect(!resolution.isUsingActivatedSnapshot)
        #expect(resolution.fallbackReason == .staticSource)
    }

    private func makeCatalog() -> MobilityDatasetCatalog {
        MobilityDatasetCatalog(
            version: "1.0.0",
            defaultSource: .bundledSample,
            datasets: [
                MobilityDatasetDescriptor(
                    id: "bundled-sample",
                    datasetID: "sample-korea-mobility-2025-q1",
                    source: .bundledSample,
                    providerID: "flow_internal",
                    displayName: "Bundled Sample",
                    version: "1.0.0",
                    schemaVersion: "1.0.0",
                    updatedAt: "2026-03-01T00:00:00Z",
                    availableModes: [.road, .rail, .air, .maritime],
                    supportedSpatialLevels: [.city],
                    supportedGranularities: [.year, .month, .hourOfDay],
                    reliability: .medium,
                    spatialPrecision: .city,
                    temporalPrecision: .hour,
                    qualityScore: 0.7,
                    liveMetadata: nil
                ),
                MobilityDatasetDescriptor(
                    id: "seoul-capital-snapshot",
                    datasetID: "seoul-capital-living-mobility",
                    source: .seoulCapitalSnapshot,
                    providerID: "seoul_open_data_plaza",
                    displayName: "Seoul Capital Mobility",
                    version: "2025.01",
                    schemaVersion: "1.0.0",
                    updatedAt: "2025-02-15T00:00:00Z",
                    availableModes: [.road, .rail, .air],
                    supportedSpatialLevels: [.city],
                    supportedGranularities: [.hourOfDay],
                    reliability: .high,
                    spatialPrecision: .district,
                    temporalPrecision: .hour,
                    qualityScore: 0.92,
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
    }

    private func makeContract(
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        activationState: SnapshotActivationEligibility.State = .eligible
    ) -> MaterializedSnapshotContract {
        MaterializedSnapshotContract(
            snapshotID: snapshotID,
            source: source,
            schemaVersion: "1.0.0",
            datasetVersion: datasetVersion,
            generatedAt: "2026-03-08T00:00:00Z",
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
            activationEligibility: SnapshotActivationEligibility(state: activationState, reasons: [])
        )
    }
}
