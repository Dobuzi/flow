import SwiftUI

@main
struct FlowApp: App {
    @StateObject private var store = AppStore()

    init() {
        MobilityRepositoryFactory.bootstrapPersistentOperatorState()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
        }
    }
}
