import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            MapDashboardView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.bar.xaxis")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
