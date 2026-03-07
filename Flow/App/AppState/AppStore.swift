import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var state = AppState()
    private let userDefaults: UserDefaults
    private let datasetSourceKey = "settings.dataset_option"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let stored = userDefaults.string(forKey: datasetSourceKey) {
            if let source = FlowDatasetSource.fromPersistedValue(stored) {
                state.selectedDatasetSource = source
            } else {
                FlowLogger.warning("Unknown dataset source value '\(stored)'. Falling back to bundled sample.")
                state.selectedDatasetSource = .bundledSample
                userDefaults.set(FlowDatasetSource.bundledSample.rawValue, forKey: datasetSourceKey)
            }
        }
    }

    func send(_ action: AppAction) {
        switch action {
        case .setDatasetSource(let source):
            state.selectedDatasetSource = source
            userDefaults.set(source.rawValue, forKey: datasetSourceKey)
        case .setYear(let year):
            state.selectedYear = year
        case .setMonth(let month):
            state.selectedMonth = month
        case .setHour(let hour):
            state.selectedHour = max(0, min(23, hour))
        case .toggleMode(let mode):
            if state.selectedModes.contains(mode) {
                state.selectedModes.remove(mode)
            } else {
                state.selectedModes.insert(mode)
            }
        case .setModes(let modes):
            state.selectedModes = modes
        case .setRegion(let region):
            state.mapRegion = region
        case .setSpatialLevel(let level):
            state.spatialLevel = level
        case .setPlayback(let playback):
            state.playbackState = playback
        case .setAnimationPhase(let phase):
            state.animationPhase = phase
        case .setSelectedFlowID(let id):
            state.selectedFlowID = id
        }
    }
}
