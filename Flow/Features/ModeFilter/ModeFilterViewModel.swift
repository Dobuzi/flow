import Foundation
import Combine

@MainActor
final class ModeFilterViewModel: ObservableObject {
    @Published var selectedModes: Set<TransportMode>
    private let dispatch: (AppAction) -> Void

    init(state: AppState, dispatch: @escaping (AppAction) -> Void) {
        self.selectedModes = state.selectedModes
        self.dispatch = dispatch
    }

    func sync(from state: AppState) {
        selectedModes = state.selectedModes
    }

    func toggle(_ mode: TransportMode) {
        if selectedModes.contains(mode) {
            selectedModes.remove(mode)
        } else {
            selectedModes.insert(mode)
        }
        dispatch(.setModes(selectedModes))
    }

    func selectAll() {
        selectedModes = Set(TransportMode.allCases)
        dispatch(.setModes(selectedModes))
    }

    func clearAll() {
        selectedModes = []
        dispatch(.setModes(selectedModes))
    }
}
