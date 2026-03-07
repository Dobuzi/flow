import Foundation

enum MobilityRepositoryFactory {
    static func flowRepository(for source: FlowDatasetSource) -> FlowRepository {
        switch source {
        case .bundledSample:
            return LocalFlowRepository()
        case .seoulCapitalSnapshot:
            return SeoulCapitalMobilityFlowRepository()
        case .koreaNational:
            return NationalBaselineMobilityFlowRepository()
        }
    }

    static func locationRepository(for source: FlowDatasetSource) -> LocationRepository {
        switch source {
        case .bundledSample:
            return LocalLocationRepository()
        case .seoulCapitalSnapshot:
            return SeoulCapitalMobilityLocationRepository()
        case .koreaNational:
            return NationalBaselineMobilityLocationRepository()
        }
    }

    static func catalogRepository() -> MobilityCatalogRepository {
        LocalMobilityCatalogRepository()
    }
}
