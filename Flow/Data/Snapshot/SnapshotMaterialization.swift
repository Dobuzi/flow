import Foundation

struct SnapshotMaterializationInput: Hashable {
    struct FilePayload: Hashable {
        enum Role: String, Hashable, CaseIterable {
            case manifest
            case nodes
            case flows
        }

        let role: Role
        let data: Data
        let recordCountHint: Int?
        let checksumSHA256: String?
    }

    let source: FlowDatasetSource
    let providerID: String
    let upstreamVersion: String
    let fetchedAt: String
    let rawPayloadFingerprint: String?
    let files: [FilePayload]
    let metadata: [String: String]
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
