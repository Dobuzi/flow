import Foundation
import Combine

struct OperatorSourceLiveSummary: Hashable {
    let activeSnapshotID: String?
    let lastKnownGoodSnapshotID: String?
    let latestCandidateSnapshotID: String?
    let latestCandidateCompatibility: IngestionCompatibilityClassification?
    let latestCandidateEligibleForActivation: Bool?
    let lastRefreshOutcome: DatasetRefreshOutcome?
    let lastRefreshAt: String?
    let rollbackAvailable: Bool
    let operatorActivationStatus: DatasetOperatorActivationStatus
    let readiness: DatasetRefreshReadiness
    let syncState: DatasetSyncState
}

struct OperatorSourceSummary: Identifiable, Hashable {
    let source: FlowDatasetSource
    let displayName: String
    let isLiveCapable: Bool
    let liveSummary: OperatorSourceLiveSummary?

    var id: FlowDatasetSource {
        source
    }
}

struct OperatorDashboardSummary: Hashable {
    let catalogVersion: String
    let sources: [OperatorSourceSummary]
    let bootstrapStatus: PersistentOperatorStateBootstrapStatus?

    var liveSources: [OperatorSourceSummary] {
        sources.filter(\.isLiveCapable)
    }

    var staticSources: [OperatorSourceSummary] {
        sources.filter { !$0.isLiveCapable }
    }
}

@MainActor
final class OperatorDashboardViewModel: ObservableObject {
    @Published private(set) var dashboard: OperatorDashboardSummary?
    @Published private(set) var loadError: FlowNonFatalError?

    private let catalogRepository: MobilityCatalogRepository
    private let bootstrapStatus: PersistentOperatorStateBootstrapStatus?

    init(
        catalogRepository: MobilityCatalogRepository = MobilityRepositoryFactory.liveAwareCatalogRepository(),
        bootstrapStatus: PersistentOperatorStateBootstrapStatus? = MobilityRepositoryFactory.sharedOperatorStateBootstrapStatus
    ) {
        self.catalogRepository = catalogRepository
        self.bootstrapStatus = bootstrapStatus
    }

    func load() async {
        do {
            let catalog = try await catalogRepository.fetchCatalog()
            dashboard = OperatorDashboardSummary(
                catalogVersion: catalog.version,
                sources: catalog.datasets.map(Self.makeSourceSummary(from:)),
                bootstrapStatus: bootstrapStatus
            )
            loadError = nil
        } catch {
            dashboard = nil
            loadError = FlowLogger.nonFatalError(
                scope: .settings,
                userMessage: "Failed to load operator dashboard.",
                underlying: error
            )
        }
    }

    private static func makeSourceSummary(from descriptor: MobilityDatasetDescriptor) -> OperatorSourceSummary {
        let liveSummary: OperatorSourceLiveSummary?
        if let live = descriptor.liveMetadata, live.supportsLiveRefresh {
            liveSummary = OperatorSourceLiveSummary(
                activeSnapshotID: live.activationMetadata?.activeSnapshotID ?? live.activeSnapshotID,
                lastKnownGoodSnapshotID: live.activationMetadata?.lastKnownGoodSnapshotID ?? live.lastKnownGoodSnapshotID,
                latestCandidateSnapshotID: live.activationMetadata?.latestCandidateSnapshotID ?? live.latestCandidateSnapshotID,
                latestCandidateCompatibility: live.activationMetadata?.latestCandidateCompatibility ?? live.latestCandidateCompatibility,
                latestCandidateEligibleForActivation: live.activationMetadata?.latestCandidateEligibleForActivation ?? live.latestCandidateEligibleForActivation,
                lastRefreshOutcome: live.lastRefreshOutcome,
                lastRefreshAt: resolvedLastRefreshTimestamp(from: live),
                rollbackAvailable: live.activationMetadata?.rollbackAvailable ?? false,
                operatorActivationStatus: live.activationMetadata?.operatorActivationStatus ?? .noHistory,
                readiness: live.readiness,
                syncState: live.syncState
            )
        } else {
            liveSummary = nil
        }

        return OperatorSourceSummary(
            source: descriptor.source,
            displayName: descriptor.displayName,
            isLiveCapable: descriptor.liveMetadata?.supportsLiveRefresh == true,
            liveSummary: liveSummary
        )
    }

    private static func resolvedLastRefreshTimestamp(from live: DatasetLiveMetadata) -> String? {
        live.lastRefreshFailedAt
            ?? live.lastSuccessfulRefreshAt
            ?? live.lastRefreshAttemptAt
    }
}
