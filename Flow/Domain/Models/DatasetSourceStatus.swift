import Foundation

struct DatasetSourceStatus: Equatable {
    enum State: String, Equatable {
        case loading
        case ready
        case limited
        case unavailable
    }

    let source: FlowDatasetSource
    let state: State
    let message: String
}
