import SwiftUI

struct TimeControlSheet: View {
    @ObservedObject var viewModel: TimeControlViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Year") {
                    Stepper(value: Binding(
                        get: { viewModel.selectedYear },
                        set: { viewModel.setYear($0) }
                    ), in: 2000...2100) {
                        Text("\(viewModel.selectedYear)")
                    }
                }

                Section("Month") {
                    Stepper(value: Binding(
                        get: { viewModel.selectedMonth },
                        set: { viewModel.setMonth($0) }
                    ), in: 1...12) {
                        Text("\(viewModel.selectedMonth)")
                    }
                }

                Section("Hour of Day") {
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.selectedHour) },
                            set: { viewModel.setHour(Int($0.rounded())) }
                        ),
                        in: 0...23,
                        step: 1
                    )
                    Text(String(format: "%02d:00", viewModel.selectedHour))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Playback") {
                    Picker("Playback", selection: Binding(
                        get: { viewModel.playbackState },
                        set: { viewModel.setPlayback($0) }
                    )) {
                        Text("Stopped").tag(AppState.PlaybackState.stopped)
                        Text("Playing").tag(AppState.PlaybackState.playing)
                        Text("Paused").tag(AppState.PlaybackState.paused)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Time Controls")
        }
    }
}
