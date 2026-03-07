import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    enum DatasetOption: String, CaseIterable, Identifiable {
        case bundledSample = "bundled_sample"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bundledSample:
                return "Bundled Sample"
            }
        }
    }

    @Published private(set) var dataset: FlowDataset?
    @Published private(set) var cacheStats: CacheDataSource.CacheStats?
    @Published private(set) var loadError: FlowNonFatalError?
    @Published var selectedDatasetOptionRaw: String
    @Published var preferredSpatialLevelRaw: String

    private let flowRepository: FlowRepository
    private let cacheDataSource: CacheDataSource
    private let userDefaults: UserDefaults

    private let datasetOptionKey = "settings.dataset_option"
    private let preferredSpatialLevelKey = "settings.preferred_spatial_level"

    init(
        flowRepository: FlowRepository = LocalFlowRepository(),
        cacheDataSource: CacheDataSource = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.flowRepository = flowRepository
        self.cacheDataSource = cacheDataSource
        self.userDefaults = userDefaults

        selectedDatasetOptionRaw = userDefaults.string(forKey: datasetOptionKey)
            ?? DatasetOption.bundledSample.rawValue
        preferredSpatialLevelRaw = userDefaults.string(forKey: preferredSpatialLevelKey)
            ?? SpatialLevel.national.rawValue
    }

    func load() async {
        do {
            dataset = try await flowRepository.fetchDataset()
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

    func saveDatasetOption(_ rawValue: String) {
        selectedDatasetOptionRaw = rawValue
        userDefaults.set(rawValue, forKey: datasetOptionKey)
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
