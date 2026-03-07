import SwiftUI

struct ModeFilterSheet: View {
    @ObservedObject var viewModel: ModeFilterViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Transport Modes") {
                    ForEach(TransportMode.allCases, id: \.self) { mode in
                        Toggle(
                            mode.rawValue.capitalized,
                            isOn: Binding(
                                get: { viewModel.selectedModes.contains(mode) },
                                set: { _ in viewModel.toggle(mode) }
                            )
                        )
                    }
                }

                Section("Quick Actions") {
                    Button("Select All") {
                        viewModel.selectAll()
                    }
                    Button("Clear All") {
                        viewModel.clearAll()
                    }
                }
            }
            .navigationTitle("Mode Filters")
        }
    }
}
