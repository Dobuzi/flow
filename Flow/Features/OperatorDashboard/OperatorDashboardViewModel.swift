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
    let metrics: OperatorSourceMetrics
}

struct OperatorSourceSummary: Identifiable, Hashable {
    let source: FlowDatasetSource
    let displayName: String
    let isLiveCapable: Bool
    let proposalSummary: OperatorProposalSummary?
    let liveSummary: OperatorSourceLiveSummary?
    let healthSummary: OperatorSourceHealthSummary
    let approvalSummary: OperatorApprovalSummary?
    let rolloutReadinessSummary: OperatorRolloutReadinessSummary?
    let rolloutPreflight: RolloutPreflightResult?

    init(
        source: FlowDatasetSource,
        displayName: String,
        isLiveCapable: Bool,
        proposalSummary: OperatorProposalSummary? = nil,
        liveSummary: OperatorSourceLiveSummary?,
        healthSummary: OperatorSourceHealthSummary,
        approvalSummary: OperatorApprovalSummary? = nil,
        rolloutReadinessSummary: OperatorRolloutReadinessSummary? = nil,
        rolloutPreflight: RolloutPreflightResult? = nil
    ) {
        self.source = source
        self.displayName = displayName
        self.isLiveCapable = isLiveCapable
        self.proposalSummary = proposalSummary
        self.liveSummary = liveSummary
        self.healthSummary = healthSummary
        self.approvalSummary = approvalSummary
        self.rolloutReadinessSummary = rolloutReadinessSummary
        self.rolloutPreflight = rolloutPreflight
    }

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
    private let proposalStore: RolloutProposalStoring?
    private let metricsCollector: OperatorMetricsCollector
    private let healthAggregator: OperatorHealthAggregator
    private let approvalReadinessResolver = OperatorApprovalReadinessResolver()
    private let rolloutPreflightEvaluator = RolloutPreflightEvaluator()

    init(
        catalogRepository: MobilityCatalogRepository = MobilityRepositoryFactory.liveAwareCatalogRepository(),
        bootstrapStatus: PersistentOperatorStateBootstrapStatus? = MobilityRepositoryFactory.sharedOperatorStateBootstrapStatus,
        proposalStore: RolloutProposalStoring? = MobilityRepositoryFactory.sharedRolloutProposalStore,
        activationHistoryStore: SnapshotActivationHistoryStoring? = MobilityRepositoryFactory.sharedActivationHistoryStore,
        refreshStateStore: DatasetRefreshStateStoring? = MobilityRepositoryFactory.sharedRefreshStateStore
    ) {
        self.catalogRepository = catalogRepository
        self.bootstrapStatus = bootstrapStatus
        self.proposalStore = proposalStore
        self.metricsCollector = OperatorMetricsCollector(
            activationHistoryStore: activationHistoryStore,
            refreshStateStore: refreshStateStore
        )
        self.healthAggregator = OperatorHealthAggregator(bootstrapStatus: bootstrapStatus)
    }

    func load() async {
        do {
            let catalog = try await catalogRepository.fetchCatalog()
            let proposalSummariesBySource = await latestProposalSummariesBySource()
            var sources: [OperatorSourceSummary] = []
            sources.reserveCapacity(catalog.datasets.count)

            for descriptor in catalog.datasets {
                let metrics = await metricsCollector.metrics(
                    for: descriptor.source,
                    isLiveCapable: descriptor.liveMetadata?.supportsLiveRefresh == true
                )
                sources.append(
                    makeSourceSummary(
                        from: descriptor,
                        proposalSummary: proposalSummariesBySource[descriptor.source],
                        metrics: metrics
                    )
                )
            }

            dashboard = OperatorDashboardSummary(
                catalogVersion: catalog.version,
                sources: sources,
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

    private func makeSourceSummary(
        from descriptor: MobilityDatasetDescriptor,
        proposalSummary: OperatorProposalSummary?,
        metrics: OperatorSourceMetrics?
    ) -> OperatorSourceSummary {
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
                syncState: live.syncState,
                metrics: metrics ?? .empty
            )
        } else {
            liveSummary = nil
        }

        let healthSummary = healthAggregator.summary(
            for: descriptor.source,
            isLiveCapable: descriptor.liveMetadata?.supportsLiveRefresh == true,
            liveSummary: liveSummary
        )
        let approvalSummary = approvalReadinessResolver.approvalSummary(
            isLiveCapable: descriptor.liveMetadata?.supportsLiveRefresh == true,
            liveSummary: liveSummary,
            healthSummary: healthSummary,
            proposalSummary: proposalSummary
        )
        let rolloutReadinessSummary = approvalReadinessResolver.rolloutReadinessSummary(
            isLiveCapable: descriptor.liveMetadata?.supportsLiveRefresh == true,
            liveSummary: liveSummary,
            healthSummary: healthSummary,
            proposalSummary: proposalSummary
        )

        let summary = OperatorSourceSummary(
            source: descriptor.source,
            displayName: descriptor.displayName,
            isLiveCapable: descriptor.liveMetadata?.supportsLiveRefresh == true,
            proposalSummary: proposalSummary,
            liveSummary: liveSummary,
            healthSummary: healthSummary,
            approvalSummary: approvalSummary,
            rolloutReadinessSummary: rolloutReadinessSummary
        )

        return OperatorSourceSummary(
            source: summary.source,
            displayName: summary.displayName,
            isLiveCapable: summary.isLiveCapable,
            proposalSummary: summary.proposalSummary,
            liveSummary: summary.liveSummary,
            healthSummary: summary.healthSummary,
            approvalSummary: summary.approvalSummary,
            rolloutReadinessSummary: summary.rolloutReadinessSummary,
            rolloutPreflight: rolloutPreflightEvaluator.evaluate(summary)
        )
    }

    private func latestProposalSummariesBySource() async -> [FlowDatasetSource: OperatorProposalSummary] {
        guard let proposalStore else { return [:] }

        var latestBySource: [FlowDatasetSource: OperatorProposalSummary] = [:]
        for proposal in await proposalStore.allProposals() {
            if latestBySource[proposal.source] == nil {
                latestBySource[proposal.source] = OperatorProposalSummary(proposal: proposal)
            }
        }
        return latestBySource
    }

    private func resolvedLastRefreshTimestamp(from live: DatasetLiveMetadata) -> String? {
        live.lastRefreshFailedAt
            ?? live.lastSuccessfulRefreshAt
            ?? live.lastRefreshAttemptAt
    }
}
