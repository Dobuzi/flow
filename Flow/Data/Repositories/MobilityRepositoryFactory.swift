import Foundation

enum MobilityRepositoryFactory {
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

    static func catalogRepository() -> MobilityCatalogRepository {
        LocalMobilityCatalogRepository()
    }

    static func liveAwareCatalogRepository(
        versionStore: DatasetVersionStoring,
        activationPolicy: SnapshotActivationPolicying
    ) -> MobilityCatalogRepository {
        LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: versionStore,
                activationPolicy: activationPolicy
            )
        )
    }
}
