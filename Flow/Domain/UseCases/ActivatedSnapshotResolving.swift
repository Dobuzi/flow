import Foundation

enum ActivatedSnapshotFallbackReason: String, Hashable {
    case staticSource
    case catalogUnavailable
    case descriptorUnavailable
    case noActiveSnapshot
    case activeSnapshotMissing
    case activeSnapshotIneligible
}

struct ActivatedSnapshotResolution: Hashable {
    let source: FlowDatasetSource
    let isLiveCapable: Bool
    let activatedSnapshotID: String?
    let activatedDatasetVersion: String?
    let compatibilityClassification: IngestionCompatibilityClassification?
    let isUsingActivatedSnapshot: Bool
    let fallbackReason: ActivatedSnapshotFallbackReason?

    static func fallback(
        source: FlowDatasetSource,
        isLiveCapable: Bool,
        reason: ActivatedSnapshotFallbackReason
    ) -> ActivatedSnapshotResolution {
        ActivatedSnapshotResolution(
            source: source,
            isLiveCapable: isLiveCapable,
            activatedSnapshotID: nil,
            activatedDatasetVersion: nil,
            compatibilityClassification: nil,
            isUsingActivatedSnapshot: false,
            fallbackReason: reason
        )
    }
}

protocol ActivatedSnapshotResolving {
    func resolve(for source: FlowDatasetSource) async -> ActivatedSnapshotResolution
}
