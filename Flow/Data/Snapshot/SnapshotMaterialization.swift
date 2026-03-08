import Foundation

struct SnapshotMaterializationInput: Hashable {
    let source: FlowDatasetSource
    let providerID: String
    let upstreamVersion: String
    let fetchedAt: String
    let rawPayloadFingerprint: String?
}

struct SnapshotMaterializationResult: Hashable {
    enum Status: String, Hashable {
        case materialized
        case rejected
    }

    let status: Status
    let contract: MaterializedSnapshotContract?
    let warnings: [String]
}

protocol SnapshotMaterializing {
    func materialize(input: SnapshotMaterializationInput) async throws -> SnapshotMaterializationResult
}
