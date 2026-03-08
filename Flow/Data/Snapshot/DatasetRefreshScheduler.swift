import Foundation

enum DatasetRefreshTrigger: String, Hashable {
    case manual
    case periodic
}

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
    private let nowProvider: () -> Date
    private let timestampProvider: (Date) -> String

    private var inProgressSources: Set<FlowDatasetSource> = []
    private var lastAttemptBySource: [FlowDatasetSource: Date] = [:]

    init(
        catalogRepository: MobilityCatalogRepository,
        coordinatorRegistry: CoordinatorRegistry,
        minimumPeriodicInterval: TimeInterval = 60 * 60,
        nowProvider: @escaping () -> Date = Date.init,
        timestampProvider: @escaping (Date) -> String = { date in
            ISO8601DateFormatter().string(from: date)
        }
    ) {
        self.catalogRepository = catalogRepository
        self.coordinatorRegistry = coordinatorRegistry
        self.minimumPeriodicInterval = minimumPeriodicInterval
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
            return DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .failed,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                didStoreCandidate: false,
                error: .catalogUnavailable(reason: String(describing: error))
            )
        }

        guard let descriptor = catalog.descriptor(for: request.source),
              descriptor.liveMetadata?.supportsLiveRefresh == true else {
            return DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .skipped,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                didStoreCandidate: false,
                error: .sourceNotLiveCapable
            )
        }

        if request.trigger == .periodic,
           let lastAttempt = lastAttemptBySource[request.source] {
            let elapsed = now.timeIntervalSince(lastAttempt)
            if elapsed < minimumPeriodicInterval {
                let next = lastAttempt.addingTimeInterval(minimumPeriodicInterval)
                return DatasetRefreshResult(
                    source: request.source,
                    trigger: request.trigger,
                    status: .skipped,
                    startedAt: startedAt,
                    finishedAt: timestampProvider(nowProvider()),
                    storedSnapshotID: nil,
                    storedDatasetVersion: nil,
                    didStoreCandidate: false,
                    error: .periodicNotDue(nextEligibleAt: timestampProvider(next))
                )
            }
        }

        guard !inProgressSources.contains(request.source) else {
            return DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .skipped,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                didStoreCandidate: false,
                error: .refreshInProgress
            )
        }

        guard let coordinator = coordinatorRegistry[request.source] else {
            return DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .skipped,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                didStoreCandidate: false,
                error: .adapterNotConfigured
            )
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
            return DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .succeeded,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: ingestionResult.contract?.snapshotID,
                storedDatasetVersion: ingestionResult.contract?.datasetVersion,
                didStoreCandidate: ingestionResult.status == .succeeded && ingestionResult.contract != nil,
                error: nil
            )
        } catch let error as IngestionPipelineError {
            return DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .failed,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                didStoreCandidate: false,
                error: .ingestionFailed(error)
            )
        } catch {
            return DatasetRefreshResult(
                source: request.source,
                trigger: request.trigger,
                status: .failed,
                startedAt: startedAt,
                finishedAt: timestampProvider(nowProvider()),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                didStoreCandidate: false,
                error: .schedulerFailure(reason: String(describing: error))
            )
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
