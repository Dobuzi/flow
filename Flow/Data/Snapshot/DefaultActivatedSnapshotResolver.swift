import Foundation

struct DefaultActivatedSnapshotResolver: ActivatedSnapshotResolving {
    private let catalogRepository: MobilityCatalogRepository
    private let versionStore: DatasetVersionStoring
    private let activationPolicy: SnapshotActivationPolicying

    init(
        catalogRepository: MobilityCatalogRepository,
        versionStore: DatasetVersionStoring,
        activationPolicy: SnapshotActivationPolicying
    ) {
        self.catalogRepository = catalogRepository
        self.versionStore = versionStore
        self.activationPolicy = activationPolicy
    }

    func resolve(for source: FlowDatasetSource) async -> ActivatedSnapshotResolution {
        let descriptor: MobilityDatasetDescriptor
        do {
            guard let found = try await catalogRepository.fetchCatalog().descriptor(for: source) else {
                return .fallback(
                    source: source,
                    isLiveCapable: false,
                    reason: .descriptorUnavailable
                )
            }
            descriptor = found
        } catch {
            return .fallback(
                source: source,
                isLiveCapable: false,
                reason: .catalogUnavailable
            )
        }

        guard descriptor.liveMetadata?.supportsLiveRefresh == true else {
            return .fallback(
                source: source,
                isLiveCapable: false,
                reason: .staticSource
            )
        }

        let activationState = await activationPolicy.currentState(for: source)
        guard let activeSnapshotID = activationState.activeSnapshotID else {
            return .fallback(
                source: source,
                isLiveCapable: true,
                reason: .noActiveSnapshot
            )
        }

        guard let snapshot = await versionStore.snapshot(snapshotID: activeSnapshotID),
              snapshot.source == source else {
            return .fallback(
                source: source,
                isLiveCapable: true,
                reason: .activeSnapshotMissing
            )
        }

        let eligible = snapshot.isIngestionCandidate
            && snapshot.compatibilityClassification == .compatible
            && snapshot.activationEligibility.state == .eligible

        guard eligible else {
            return .fallback(
                source: source,
                isLiveCapable: true,
                reason: .activeSnapshotIneligible
            )
        }

        return ActivatedSnapshotResolution(
            source: source,
            isLiveCapable: true,
            activatedSnapshotID: snapshot.snapshotID,
            activatedDatasetVersion: snapshot.datasetVersion,
            compatibilityClassification: snapshot.compatibilityClassification,
            isUsingActivatedSnapshot: true,
            fallbackReason: nil
        )
    }
}
