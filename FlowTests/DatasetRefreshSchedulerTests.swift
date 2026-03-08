import Foundation
import Testing
@testable import Flow

private struct StubCatalogRepository: MobilityCatalogRepository {
    let catalog: MobilityDatasetCatalog

    func fetchCatalog() async throws -> MobilityDatasetCatalog {
        catalog
    }
}

private struct StubIngestionCoordinator: IngestionPipelineCoordinating {
    let result: Result<IngestionPipelineResult, IngestionPipelineError>

    func ingest(request: IngestionPipelineRequest) async throws -> IngestionPipelineResult {
        try result.get()
    }
}

private actor RefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        isWaiting = false
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private struct BlockingIngestionCoordinator: IngestionPipelineCoordinating {
    let gate: RefreshGate
    let output: IngestionPipelineResult

    func ingest(request: IngestionPipelineRequest) async throws -> IngestionPipelineResult {
        await gate.wait()
        return output
    }
}

private final class MutableNow {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

struct DatasetRefreshSchedulerTests {
    @Test
    func manualRefreshSucceedsForLiveCapableSource() async {
        let repository = StubCatalogRepository(catalog: makeCatalog())
        let scheduler = DefaultDatasetRefreshScheduler(
            catalogRepository: repository,
            coordinatorRegistry: [
                .seoulCapitalSnapshot: StubIngestionCoordinator(result: .success(makeIngestionSuccess(snapshotID: "seoul-2026.03")))
            ],
            minimumPeriodicInterval: 3600
        )

        let result = await scheduler.refresh(
            DatasetRefreshRequest(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                preferredUpstreamVersion: nil
            )
        )

        #expect(result.status == .succeeded)
        #expect(result.didStoreCandidate)
        #expect(result.storedSnapshotID == "seoul-2026.03")
        #expect(result.error == nil)
    }

    @Test
    func periodicRefreshRespectsMinimumInterval() async {
        let now = MutableNow(Date(timeIntervalSince1970: 1_762_359_200))
        let repository = StubCatalogRepository(catalog: makeCatalog())
        let scheduler = DefaultDatasetRefreshScheduler(
            catalogRepository: repository,
            coordinatorRegistry: [
                .seoulCapitalSnapshot: StubIngestionCoordinator(result: .success(makeIngestionSuccess(snapshotID: "seoul-2026.03")))
            ],
            minimumPeriodicInterval: 3600,
            nowProvider: { now.date }
        )

        let first = await scheduler.triggerPeriodicRefresh()
        #expect(first.contains { $0.source == .seoulCapitalSnapshot && $0.status == .succeeded })

        let second = await scheduler.triggerPeriodicRefresh()
        let secondSeoul = second.first(where: { $0.source == .seoulCapitalSnapshot })
        #expect(secondSeoul?.status == .skipped)
        #expect({
            guard let error = secondSeoul?.error,
                  case .periodicNotDue = error else {
                return false
            }
            return true
        }())

        now.date = now.date.addingTimeInterval(3601)
        let third = await scheduler.triggerPeriodicRefresh()
        #expect(third.contains { $0.source == .seoulCapitalSnapshot && $0.status == .succeeded })
    }

    @Test
    func nonLiveSourceIsSkippedCleanly() async {
        let repository = StubCatalogRepository(catalog: makeCatalog())
        let scheduler = DefaultDatasetRefreshScheduler(
            catalogRepository: repository,
            coordinatorRegistry: [:]
        )

        let result = await scheduler.refresh(
            DatasetRefreshRequest(
                source: .bundledSample,
                trigger: .manual,
                preferredUpstreamVersion: nil
            )
        )

        #expect(result.status == .skipped)
        #expect(result.error == .sourceNotLiveCapable)
    }

    @Test
    func inProgressRefreshIsSkippedSafely() async {
        let gate = RefreshGate()
        let repository = StubCatalogRepository(catalog: makeCatalog())
        let scheduler = DefaultDatasetRefreshScheduler(
            catalogRepository: repository,
            coordinatorRegistry: [
                .seoulCapitalSnapshot: BlockingIngestionCoordinator(
                    gate: gate,
                    output: makeIngestionSuccess(snapshotID: "seoul-2026.03")
                )
            ]
        )

        let firstTask = Task {
            await scheduler.refresh(
                DatasetRefreshRequest(
                    source: .seoulCapitalSnapshot,
                    trigger: .manual,
                    preferredUpstreamVersion: nil
                )
            )
        }

        for _ in 0..<20 {
            if await gate.isWaiting { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let second = await scheduler.refresh(
            DatasetRefreshRequest(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                preferredUpstreamVersion: nil
            )
        )
        #expect(second.status == .skipped)
        #expect(second.error == .refreshInProgress)

        await gate.resume()
        let first = await firstTask.value
        #expect(first.status == .succeeded)
    }

    @Test
    func ingestionFailureIsSurfacedWithoutRuntimeMutation() async throws {
        let repository = StubCatalogRepository(catalog: makeCatalog())
        let scheduler = DefaultDatasetRefreshScheduler(
            catalogRepository: repository,
            coordinatorRegistry: [
                .seoulCapitalSnapshot: StubIngestionCoordinator(
                    result: .failure(.adapterFailure(.networkUnavailable))
                )
            ]
        )

        let result = await scheduler.refresh(
            DatasetRefreshRequest(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                preferredUpstreamVersion: nil
            )
        )

        #expect(result.status == .failed)
        #expect(result.didStoreCandidate == false)
        #expect(result.storedSnapshotID == nil)
        #expect(result.error == .ingestionFailed(.adapterFailure(.networkUnavailable)))

        for source in [FlowDatasetSource.bundledSample, .seoulCapitalSnapshot, .koreaNational] {
            let dataset = try await MobilityRepositoryFactory.flowRepository(for: source).fetchDataset()
            #expect(!dataset.datasetID.isEmpty)
        }
    }

    private func makeCatalog() -> MobilityDatasetCatalog {
        MobilityDatasetCatalog(
            version: "1.0.0",
            defaultSource: .bundledSample,
            datasets: [
                makeDescriptor(source: .bundledSample, live: nil),
                makeDescriptor(
                    source: .seoulCapitalSnapshot,
                    live: DatasetLiveMetadata(
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
                ),
                makeDescriptor(
                    source: .koreaNational,
                    live: DatasetLiveMetadata(
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

    private func makeDescriptor(source: FlowDatasetSource, live: DatasetLiveMetadata?) -> MobilityDatasetDescriptor {
        let id: String
        let datasetID: String
        let providerID: String
        let displayName: String

        switch source {
        case .bundledSample:
            id = "bundled-sample"
            datasetID = "sample-korea-mobility-2025-q1"
            providerID = "flow_internal"
            displayName = "Bundled Sample"
        case .seoulCapitalSnapshot:
            id = "seoul-capital-snapshot"
            datasetID = "seoul-capital-living-mobility"
            providerID = "seoul_open_data_plaza"
            displayName = "Seoul Capital Mobility"
        case .koreaNational:
            id = "korea-national-baseline"
            datasetID = "korea-national-baseline-2025"
            providerID = "korea_transport_institute"
            displayName = "Korea National"
        }

        return MobilityDatasetDescriptor(
            id: id,
            datasetID: datasetID,
            source: source,
            providerID: providerID,
            displayName: displayName,
            version: "2026.03",
            schemaVersion: "1.0.0",
            updatedAt: "2026-03-08T00:00:00Z",
            availableModes: [.road, .rail, .air],
            supportedSpatialLevels: [.city, .province],
            supportedGranularities: [.month, .hourOfDay],
            reliability: .high,
            spatialPrecision: .city,
            temporalPrecision: .hour,
            qualityScore: 0.9,
            liveMetadata: live
        )
    }

    private func makeIngestionSuccess(snapshotID: String) -> IngestionPipelineResult {
        IngestionPipelineResult(
            status: .succeeded,
            contract: MaterializedSnapshotContract(
                snapshotID: snapshotID,
                source: .seoulCapitalSnapshot,
                schemaVersion: "1.0.0",
                datasetVersion: "2026.03",
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
                activationEligibility: SnapshotActivationEligibility(state: .eligible, reasons: [])
            ),
            materializationWarnings: [],
            schemaValidation: DatasetSchemaValidationResult(
                schemaVersion: "1.0.0",
                supportedVersions: ["1.0.0"],
                isCompatible: true,
                reason: nil
            ),
            compatibilityGate: .init(
                classification: .compatible,
                result: DatasetCompatibilityResult(
                    source: .seoulCapitalSnapshot,
                    isCompatible: true,
                    reasons: [],
                    checkedFields: ["schemaVersion"],
                    missingFields: []
                )
            ),
            stepStatus: .init(
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
