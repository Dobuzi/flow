import Foundation

protocol CatalogLiveMetadataEnriching {
    func enrich(_ descriptor: MobilityDatasetDescriptor) async -> MobilityDatasetDescriptor
}

struct CatalogLiveMetadataEnricher: CatalogLiveMetadataEnriching {
    private let versionStore: DatasetVersionStoring
    private let activationPolicy: SnapshotActivationPolicying
    private let refreshStateStore: DatasetRefreshStateStoring?

    init(
        versionStore: DatasetVersionStoring,
        activationPolicy: SnapshotActivationPolicying,
        refreshStateStore: DatasetRefreshStateStoring? = nil
    ) {
        self.versionStore = versionStore
        self.activationPolicy = activationPolicy
        self.refreshStateStore = refreshStateStore
    }

    func enrich(_ descriptor: MobilityDatasetDescriptor) async -> MobilityDatasetDescriptor {
        guard let base = descriptor.liveMetadata, base.supportsLiveRefresh else {
            return descriptor
        }

        let versions = await versionStore.versions(for: descriptor.source)
        let latest = versions.first
        let latestSuccessful = versions.first(where: isSuccessfulRefreshCandidate(_:))
        let activationState = await activationPolicy.currentState(for: descriptor.source)
        let refreshState = await refreshStateStore?.state(for: descriptor.source)
        let latestCandidateDecision = await activationPolicy.evaluateActivation(
            source: descriptor.source,
            requestedSnapshotID: latest?.snapshotID
        )

        let latestCandidateEligibleForActivation: Bool?
        switch latestCandidateDecision.status {
        case .activatable:
            latestCandidateEligibleForActivation = true
        case .storedButNotActivatable:
            latestCandidateEligibleForActivation = false
        case .snapshotNotFound, .noCandidate:
            latestCandidateEligibleForActivation = nil
        }

        let readiness: DatasetRefreshReadiness
        if latestSuccessful != nil || activationState.activeSnapshotID != nil {
            readiness = .ready
        } else if latest == nil {
            readiness = .pendingValidation
        } else {
            readiness = .blocked
        }

        let syncState: DatasetSyncState
        switch latest?.compatibilityClassification {
        case .compatible:
            syncState = .ready
        case .partiallyCompatible:
            syncState = .degraded
        case .incompatible:
            syncState = .failed
        case .none:
            syncState = .idle
        }

        let merged = DatasetLiveMetadata(
            supportsLiveRefresh: base.supportsLiveRefresh,
            latestKnownDatasetVersion: latest?.datasetVersion ?? base.latestKnownDatasetVersion,
            latestKnownSnapshotID: latest?.snapshotID ?? base.latestKnownSnapshotID,
            lastRefreshAttemptAt: refreshState?.lastRefreshAttemptAt ?? latest?.indexedAt ?? base.lastRefreshAttemptAt,
            lastSuccessfulRefreshAt: refreshState?.lastRefreshSucceededAt ?? latestSuccessful?.indexedAt ?? base.lastSuccessfulRefreshAt,
            lastRefreshFailedAt: refreshState?.lastRefreshFailedAt ?? base.lastRefreshFailedAt,
            lastRefreshTrigger: refreshState?.lastRefreshTrigger ?? base.lastRefreshTrigger,
            lastRefreshOutcome: refreshState?.lastRefreshOutcome ?? base.lastRefreshOutcome,
            lastRefreshFailureReason: refreshState?.lastRefreshFailureReason ?? base.lastRefreshFailureReason,
            latestCandidateSnapshotID: refreshState?.latestCandidateSnapshotID ?? latest?.snapshotID ?? base.latestCandidateSnapshotID,
            latestCandidateCompatibility: refreshState?.latestCandidateCompatibility ?? latest?.compatibilityClassification ?? base.latestCandidateCompatibility,
            latestCandidateEligibleForActivation: refreshState?.latestCandidateEligibleForActivation ?? latestCandidateEligibleForActivation ?? base.latestCandidateEligibleForActivation,
            activeSnapshotID: activationState.activeSnapshotID ?? base.activeSnapshotID,
            lastKnownGoodSnapshotID: activationState.lastKnownGoodSnapshotID ?? base.lastKnownGoodSnapshotID,
            readiness: readiness,
            syncState: syncState
        )

        return descriptor.withLiveMetadata(merged)
    }

    private func isSuccessfulRefreshCandidate(_ version: StoredSnapshotVersion) -> Bool {
        version.compatibilityClassification == .compatible
            && version.activationEligibility.state == .eligible
    }
}
