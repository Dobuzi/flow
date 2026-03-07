import SwiftUI
import MapKit

struct MapDashboardView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = MapDashboardViewModel()
    @State private var isTimeSheetPresented = false
    @State private var isModeSheetPresented = false

    var body: some View {
        ZStack(alignment: .top) {
            MapContainerView(region: Binding(
                get: { store.state.mapRegion },
                set: { store.send(.setRegion($0)) }
            ),
            segments: viewModel.renderableSegments,
            selectedFlowID: store.state.selectedFlowID,
            spatialLevel: store.state.spatialLevel,
            animationPhase: store.state.animationPhase) { region in
                store.send(.setRegion(region))
                store.send(.setSpatialLevel(LODPolicy.spatialLevel(for: region)))
            } onSelectFlow: { selectedID in
                store.send(.setSelectedFlowID(selectedID))
            } onMetric: { key, value in
                viewModel.recordMetric(key, milliseconds: value)
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                QuickControlBar(
                    spatialLevel: store.state.spatialLevel,
                    flowCount: viewModel.flowCount,
                    nodeCount: viewModel.nodeCount
                )
                Button {
                    isTimeSheetPresented = true
                } label: {
                    Label("Time", systemImage: "clock")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                Button {
                    isModeSheetPresented = true
                } label: {
                    Label("Modes", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                FlowLegendView(
                    selectedModes: store.state.selectedModes,
                    unitWarningText: viewModel.legendUnitStatus.warningText
                )

                if let error = viewModel.loadError {
                    NonBlockingErrorBanner(error: error)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 12)

            if let detail = viewModel.selectedFlowDetail {
                VStack {
                    Spacer()
                    FlowDetailCard(
                        detail: detail,
                        onClear: { store.send(.setSelectedFlowID(nil)) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
                }
            }
        }
        .task {
            await viewModel.load(initialState: store.state)
            syncSelection()
        }
        .task(id: store.state.playbackState) {
            guard store.state.playbackState == .playing else { return }
            while store.state.playbackState == .playing {
                let tickStart = CFAbsoluteTimeGetCurrent()
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard store.state.playbackState == .playing else { break }
                let nextHour = (store.state.selectedHour + 1) % 24
                store.send(.setHour(nextHour))
                let elapsed = (CFAbsoluteTimeGetCurrent() - tickStart) * 1000.0
                viewModel.recordMetric("playback_tick_ms", milliseconds: elapsed)
            }
        }
        .task(id: store.state.playbackState == .playing) {
            guard store.state.playbackState == .playing else { return }
            var phase = store.state.animationPhase
            while store.state.playbackState == .playing {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard store.state.playbackState == .playing else { break }
                phase += 2
                store.send(.setAnimationPhase(phase))
            }
        }
        .sheet(isPresented: $isTimeSheetPresented) {
            TimeControlSheet(
                viewModel: TimeControlViewModel(
                    state: store.state,
                    dispatch: { action in
                        store.send(action)
                    }
                )
            )
        }
        .sheet(isPresented: $isModeSheetPresented) {
            ModeFilterSheet(
                viewModel: ModeFilterViewModel(
                    state: store.state,
                    dispatch: { action in
                        store.send(action)
                    }
                )
            )
        }
        .onChange(of: store.state.selectedYear) { _, _ in
            syncSelection()
        }
        .onChange(of: store.state.selectedMonth) { _, _ in
            syncSelection()
        }
        .onChange(of: store.state.selectedHour) { _, _ in
            syncSelection()
        }
        .onChange(of: store.state.selectedModes) { _, _ in
            syncSelection()
        }
        .onChange(of: store.state.spatialLevel) { _, _ in
            syncSelection()
        }
        .onChange(of: store.state.selectedDatasetSource) { _, _ in
            Task {
                await viewModel.load(initialState: store.state)
                syncSelection()
            }
        }
        .onChange(of: store.state.selectedFlowID) { _, _ in
            syncSelection()
        }
        .onDisappear {
            let budget = viewModel.budgetStatusReport()
            FlowLogger.info("Performance budget report: \(budget)")
        }
    }

    private func syncSelection() {
        viewModel.applySelection(from: store.state)
    }
}
