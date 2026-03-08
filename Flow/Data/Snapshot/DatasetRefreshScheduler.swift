import Foundation

struct DatasetRefreshRequest: Hashable {
    let source: FlowDatasetSource
    let trigger: DatasetRefreshTrigger
    let preferredUpstreamVersion: String?
}

struct DatasetRefreshResult: Equatable {
    enum Status: String, Hashable {
        case succeeded
        case skipped
        case failed
    }

    let source: FlowDatasetSource
    let trigger: DatasetRefreshTrigger
    let status: Status
    let startedAt: String
    let finishedAt: String
    let storedSnapshotID: String?
    let storedDatasetVersion: String?
    let compatibilityClassification: IngestionCompatibilityClassification?
    let eligibleForActivation: Bool?
    let didStoreCandidate: Bool
    let error: DatasetRefreshError?
}

enum DatasetRefreshError: Error, Equatable {
    case catalogUnavailable(reason: String)
    case schedulerFailure(reason: String)
    case sourceNotLiveCapable
    case adapterNotConfigured
    case refreshInProgress
    case periodicNotDue(nextEligibleAt: String?)
    case ingestionFailed(IngestionPipelineError)
}

protocol DatasetRefreshScheduling {
    func refresh(_ request: DatasetRefreshRequest) async -> DatasetRefreshResult
    func triggerPeriodicRefresh() async -> [DatasetRefreshResult]
}

actor DefaultDatasetRefreshScheduler: DatasetRefreshScheduling {
    typealias CoordinatorRegistry = [FlowDatasetSource: IngestionPipelineCoordinating]

    private let catalogRepository: MobilityCatalogRepository
    private let coordinatorRegistry: CoordinatorRegistry
    private let minimumPeriodicInterval: TimeInterval
    private let refreshStateStore: DatasetRefreshStateStoring?
    private let nowProvider: () -> Date
    private let timestampProvider: (Date) -> String

    private var inProgressSources: Set<FlowDatasetSource> = []
    private var lastAttemptBySource: [FlowDatasetSource: Date] = [:]

    init(
        catalogRepository: MobilityCatalogRepository,
        coordinatorRegistry: CoordinatorRegistry,
        minimumPeriodicInterval: TimeInterval = 60 * 60,
        refreshStateStore: DatasetRefreshStateStoring? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        timestampProvider: @escaping (Date) -> String = { date in
            ISO8601DateFormatter().string(from: date)
        }
    ) {
        self.catalogRepository = catalogRepository
        self.coordinatorRegistry = coordinatorRegistry
        self.minimumPeriodicInterval = minimumPeriodicInterval
        self.refreshStateStore = refreshStateStore
        self.nowProvider = nowProvider
        self.timestampProvider = timestampProvider
    }

    func refresh(_ request: DatasetRefreshRequest) async -> DatasetRefreshResult {
        let now = nowProvider()
        let startedAt = timestampProvider(now)

        let catalog: MobilityDatasetCatalog
        do {
            catalog = try await catalogRepository.fetchCatalog()
        } catch {
            let result = DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .failed,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .catalogUnavailable(reason: String(describing: error))
            )
            await refreshStateStore?.record(result)
            return result
        }

        guard let descriptor = catalog.descriptor(for: request.source),
              descriptor.liveMetadata?.supportsLiveRefresh == true else {
            let result = DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .skipped,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .sourceNotLiveCapable
            )
            await refreshStateStore?.record(result)
            return result
        }

        if request.trigger == .periodic,
           let lastAttempt = lastAttemptBySource[request.source] {
            let elapsed = now.timeIntervalSince(lastAttempt)
            if elapsed < minimumPeriodicInterval {
                let next = lastAttempt.addingTimeInterval(minimumPeriodicInterval)
                let result = DatasetRefreshResult(
                    source: request.source,
                    trigger: request.trigger,
                    status: .skipped,
                    startedAt: startedAt,
                    finishedAt: timestampProvider(nowProvider()),
                    storedSnapshotID: nil,
                    storedDatasetVersion: nil,
                    compatibilityClassification: nil,
                    eligibleForActivation: nil,
                    didStoreCandidate: false,
                    error: .periodicNotDue(nextEligibleAt: timestampProvider(next))
                )
                await refreshStateStore?.record(result)
                return result
            }
        }

        guard !inProgressSources.contains(request.source) else {
            let result = DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .skipped,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .refreshInProgress
            )
            await refreshStateStore?.record(result)
            return result
        }

        guard let coordinator = coordinatorRegistry[request.source] else {
            let result = DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .skipped,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .adapterNotConfigured
            )
            await refreshStateStore?.record(result)
            return result
        }

        inProgressSources.insert(request.source)
        lastAttemptBySource[request.source] = now
        defer { inProgressSources.remove(request.source) }

        let fetchRequest = ExternalDatasetFetchRequest(
            source: request.source,
            providerID: descriptor.providerID,
            expectedSchemaVersion: descriptor.schemaVersion,
            preferredUpstreamVersion: request.preferredUpstreamVersion,
            requestID: "\(request.source.rawValue)-\(request.trigger.rawValue)-\(startedAt)"
        )

        do {
            let ingestionResult = try await coordinator.ingest(
                request: IngestionPipelineRequest(fetchRequest: fetchRequest)
            )
            let result = DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .succeeded,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: ingestionResult.contract?.snapshotID,
                storedDatasetVersion: ingestionResult.contract?.datasetVersion,
                compatibilityClassification: ingestionResult.compatibilityGate?.classification,
                eligibleForActivation: ingestionResult.contract?.activationEligibility.state == .eligible,
                didStoreCandidate: ingestionResult.status == .succeeded && ingestionResult.contract != nil,
                error: nil
            )
            await refreshStateStore?.record(result)
            return result
        } catch let error as IngestionPipelineError {
            let result = DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .failed,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .ingestionFailed(error)
            )
            await refreshStateStore?.record(result)
            return result
        } catch {
            let result = DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .failed,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .schedulerFailure(reason: String(describing: error))
            )
            await refreshStateStore?.record(result)
            return result
        }
    }

    func triggerPeriodicRefresh() async -> [DatasetRefreshResult] {
        let catalog: MobilityDatasetCatalog
        do {
            catalog = try await catalogRepository.fetchCatalog()
        } catch {
            let now = nowProvider()
            return FlowDatasetSource.allCases.map { source in
                DatasetRefreshResult(
                    source: source,
                    trigger: .periodic,
                    status: .failed,
                    startedAt: timestampProvider(now),
                    finishedAt: timestampProvider(nowProvider()),
                    storedSnapshotID: nil,
                    storedDatasetVersion: nil,
                    compatibilityClassification: nil,
                    eligibleForActivation: nil,
                    didStoreCandidate: false,
                    error: .catalogUnavailable(reason: String(describing: error))
                )
            }
        }

        var results: [DatasetRefreshResult] = []
        let liveSources = catalog.datasets
            .filter { $0.liveMetadata?.supportsLiveRefresh == true }
            .map(\.source)

        for source in liveSources {
            let result = await refresh(
                DatasetRefreshRequest(
                    source: source,
                    trigger: .periodic,
                    preferredUpstreamVersion: nil
                )
            )
            results.append(result)
        }
        return results
    }
}
