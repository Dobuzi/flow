import Foundation
import Combine

@MainActor
final class TimeControlViewModel: ObservableObject {
    @Published var selectedYear: Int
    @Published var selectedMonth: Int
    @Published var selectedHour: Int
    @Published var playbackState: AppState.PlaybackState

    private let dispatch: (AppAction) -> Void

    init(state: AppState, dispatch: @escaping (AppAction) -> Void) {
        self.selectedYear = state.selectedYear
        self.selectedMonth = state.selectedMonth
        self.selectedHour = state.selectedHour
        self.playbackState = state.playbackState
        self.dispatch = dispatch
    }

    func sync(from state: AppState) {
        selectedYear = state.selectedYear
        selectedMonth = state.selectedMonth
        selectedHour = state.selectedHour
        playbackState = state.playbackState
    }

    func setYear(_ year: Int) {
        let clamped = max(2000, min(2100, year))
        selectedYear = clamped
        dispatch(.setYear(clamped))
    }

    func setMonth(_ month: Int) {
        let clamped = max(1, min(12, month))
        selectedMonth = clamped
        dispatch(.setMonth(clamped))
    }

    func setHour(_ hour: Int) {
        let clamped = max(0, min(23, hour))
        selectedHour = clamped
        dispatch(.setHour(clamped))
    }

    func setPlayback(_ state: AppState.PlaybackState) {
        playbackState = state
        dispatch(.setPlayback(state))
    }
}
