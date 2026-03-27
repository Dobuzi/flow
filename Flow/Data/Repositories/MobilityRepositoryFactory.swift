import Foundation

enum MobilityRepositoryFactory {
    static let sharedVersionStore: DatasetVersionStoring = InMemoryDatasetVersionStore()
    private static let sharedOperatorStateBootstrap = PersistentOperatorStateBootstrap(
        versionStore: sharedVersionStore
    ).bootstrap()
    static let sharedActivationStateStore: SnapshotActivationStateStoring = sharedOperatorStateBootstrap.activationStateStore
    static let sharedActivationPolicy: SnapshotActivationPolicying = sharedOperatorStateBootstrap.activationPolicy
    static let sharedActivationHistoryStore: SnapshotActivationHistoryStoring = sharedOperatorStateBootstrap.activationHistoryStore
    static let sharedRefreshStateStore: DatasetRefreshStateStoring = sharedOperatorStateBootstrap.refreshStateStore
    static let sharedActivationStateProjector: SnapshotActivationStateProjecting = sharedOperatorStateBootstrap.activationStateProjector
    static let sharedOperatorStateBootstrapStatus: PersistentOperatorStateBootstrapStatus = sharedOperatorStateBootstrap.status
    static let sharedRolloutProposalStore: RolloutProposalStoring = PersistentRolloutProposalStore()
    static let sharedRolloutProposalAuditStore: RolloutProposalAuditStoring = PersistentRolloutProposalAuditStore()

    static func bootstrapPersistentOperatorState() {
        _ = sharedOperatorStateBootstrapStatus
    }

    static var nationalDataSourceBuilder: () -> NationalBaselineMobilityDataSource = {
        SafeNationalBaselineMobilityDataSource(
            wrapped: NationalBaselineSnapshotDataSource()
        )
    }

    static func flowRepository(for source: FlowDatasetSource) -> FlowRepository {
        switch source {
        case .bundledSample:
            return LocalFlowRepository()
        case .seoulCapitalSnapshot:
            return SeoulCapitalMobilityFlowRepository()
        case .koreaNational:
            return NationalBaselineMobilityFlowRepository(
                dataSource: nationalDataSourceBuilder()
            )
        }
    }

    static func flowRepository(
        for source: FlowDatasetSource,
        resolution: ActivatedSnapshotResolution
    ) -> FlowRepository {
        if resolution.isUsingActivatedSnapshot {
            FlowLogger.info(
                "Using activated snapshot context for \(source.rawValue): " +
                "\(resolution.activatedSnapshotID ?? "unknown")"
            )
        } else if let reason = resolution.fallbackReason {
            FlowLogger.info("Activation fallback for \(source.rawValue): \(reason.rawValue)")
        }
        return flowRepository(for: source)
    }

    static func locationRepository(for source: FlowDatasetSource) -> LocationRepository {
        switch source {
        case .bundledSample:
            return LocalLocationRepository()
        case .seoulCapitalSnapshot:
            return SeoulCapitalMobilityLocationRepository()
        case .koreaNational:
            return NationalBaselineMobilityLocationRepository(
                dataSource: nationalDataSourceBuilder()
            )
        }
    }

    static func locationRepository(
        for source: FlowDatasetSource,
        resolution: ActivatedSnapshotResolution
    ) -> LocationRepository {
        if resolution.isUsingActivatedSnapshot {
            FlowLogger.info(
                "Using activated location snapshot context for \(source.rawValue): " +
                "\(resolution.activatedSnapshotID ?? "unknown")"
            )
        } else if let reason = resolution.fallbackReason {
            FlowLogger.info("Activation fallback for location \(source.rawValue): \(reason.rawValue)")
        }
        return locationRepository(for: source)
    }

    static func catalogRepository() -> MobilityCatalogRepository {
        LocalMobilityCatalogRepository()
    }

    static func liveAwareCatalogRepository(
        versionStore: DatasetVersionStoring = sharedVersionStore,
        activationPolicy: SnapshotActivationPolicying = sharedActivationPolicy,
        refreshStateStore: DatasetRefreshStateStoring? = sharedRefreshStateStore,
        activationStateProjector: SnapshotActivationStateProjecting? = sharedActivationStateProjector
    ) -> MobilityCatalogRepository {
        LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: versionStore,
                activationPolicy: activationPolicy,
                refreshStateStore: refreshStateStore,
                activationStateProjector: activationStateProjector
            )
        )
    }

    static func activatedSnapshotResolver(
        versionStore: DatasetVersionStoring = sharedVersionStore,
        activationPolicy: SnapshotActivationPolicying = sharedActivationPolicy,
        refreshStateStore: DatasetRefreshStateStoring = sharedRefreshStateStore
    ) -> ActivatedSnapshotResolving {
        DefaultActivatedSnapshotResolver(
            catalogRepository: liveAwareCatalogRepository(
                versionStore: versionStore,
                activationPolicy: activationPolicy,
                refreshStateStore: refreshStateStore,
                activationStateProjector: DefaultSnapshotActivationStateProjector(
                    activationPolicy: activationPolicy,
                    historyStore: sharedActivationHistoryStore,
                    versionStore: versionStore
                )
            ),
            versionStore: versionStore,
            activationPolicy: activationPolicy
        )
    }
}
