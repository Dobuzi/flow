import Foundation

protocol CatalogLiveMetadataEnriching {
    func enrich(_ descriptor: MobilityDatasetDescriptor) async -> MobilityDatasetDescriptor
}

struct CatalogLiveMetadataEnricher: CatalogLiveMetadataEnriching {
    private let versionStore: DatasetVersionStoring
    private let activationPolicy: SnapshotActivationPolicying

    init(
        versionStore: DatasetVersionStoring,
        activationPolicy: SnapshotActivationPolicying
    ) {
        self.versionStore = versionStore
        self.activationPolicy = activationPolicy
    }

    func enrich(_ descriptor: MobilityDatasetDescriptor) async -> MobilityDatasetDescriptor {
        guard let base = descriptor.liveMetadata, base.supportsLiveRefresh else {
            return descriptor
        }

        let versions = await versionStore.versions(for: descriptor.source)
        let latest = versions.first
        let latestSuccessful = versions.first(where: isSuccessfulRefreshCandidate(_:))
        let activationState = await activationPolicy.currentState(for: descriptor.source)

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
            lastRefreshAttemptAt: latest?.indexedAt ?? base.lastRefreshAttemptAt,
            lastSuccessfulRefreshAt: latestSuccessful?.indexedAt ?? base.lastSuccessfulRefreshAt,
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
