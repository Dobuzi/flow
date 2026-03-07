import Testing
import Foundation
@testable import Flow

@MainActor
struct AppStoreDatasetSourcePersistenceTests {
    @Test
    func fallsBackToBundledSampleWhenPersistedSourceIsUnknown() {
        let suiteName = "AppStoreDatasetSourcePersistenceTests.unknown"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("unknown_source", forKey: "settings.dataset_option")

        let store = AppStore(userDefaults: defaults)

        #expect(store.state.selectedDatasetSource == .bundledSample)
        #expect(defaults.string(forKey: "settings.dataset_option") == FlowDatasetSource.bundledSample.rawValue)
    }

    @Test
    func mapsLegacyPersistedAliasToCurrentSource() {
        let suiteName = "AppStoreDatasetSourcePersistenceTests.alias"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("seoul", forKey: "settings.dataset_option")

        let store = AppStore(userDefaults: defaults)

        #expect(store.state.selectedDatasetSource == .seoulCapitalSnapshot)
    }
}
