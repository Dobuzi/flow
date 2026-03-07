import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var dataset: FlowDataset?
    @Published private(set) var cacheStats: CacheDataSource.CacheStats?
    @Published private(set) var loadError: FlowNonFatalError?
    @Published var preferredSpatialLevelRaw: String

    private let flowRepositoryBuilder: (FlowDatasetSource) -> FlowRepository
    private let cacheDataSource: CacheDataSource
    private let userDefaults: UserDefaults

    private let preferredSpatialLevelKey = "settings.preferred_spatial_level"

    init(
        flowRepositoryBuilder: @escaping (FlowDatasetSource) -> FlowRepository = { source in
            MobilityRepositoryFactory.flowRepository(for: source)
        },
        cacheDataSource: CacheDataSource = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.flowRepositoryBuilder = flowRepositoryBuilder
        self.cacheDataSource = cacheDataSource
        self.userDefaults = userDefaults

        preferredSpatialLevelRaw = userDefaults.string(forKey: preferredSpatialLevelKey)
            ?? SpatialLevel.national.rawValue
    }

    func load(source: FlowDatasetSource) async {
        do {
            dataset = try await flowRepositoryBuilder(source).fetchDataset()
            loadError = nil
        } catch {
            loadError = FlowLogger.nonFatalError(
                scope: .settings,
                userMessage: "Failed to load dataset settings.",
                underlying: error
            )
            dataset = nil
        }
        await refreshCacheStats()
    }

    func savePreferredSpatialLevel(_ rawValue: String) {
        preferredSpatialLevelRaw = rawValue
        userDefaults.set(rawValue, forKey: preferredSpatialLevelKey)
    }

    func refreshCacheStats() async {
        cacheStats = await cacheDataSource.cacheStats()
    }

    func clearCache() async {
        await cacheDataSource.clearAll()
        await refreshCacheStats()
    }
}
