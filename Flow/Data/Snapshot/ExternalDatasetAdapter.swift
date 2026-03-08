import Foundation

struct ExternalDatasetFetchRequest: Hashable {
    let source: FlowDatasetSource
    let providerID: String
    let expectedSchemaVersion: String
    let preferredUpstreamVersion: String?
    let requestID: String
}

struct ExternalDatasetAdapterCapabilities: Hashable {
    let supportsIncrementalFetch: Bool
    let supportsVersionSelection: Bool
    let maxPageSize: Int?
}

struct ExternalDatasetPayload: Hashable {
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
    let files: [FilePayload]
    let metadata: [String: String]

    func validateStructure() -> SnapshotContractValidationResult {
        var reasons: [String] = []

        if providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("provider_id_missing")
        }
        if upstreamVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("upstream_version_missing")
        }
        if fetchedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("fetched_at_missing")
        }

        let roleSet = Set(files.map(\.role))
        for role in FilePayload.Role.allCases where !roleSet.contains(role) {
            reasons.append("required_payload_file_missing:\(role.rawValue)")
        }

        if files.contains(where: { $0.data.isEmpty }) {
            reasons.append("payload_file_empty")
        }

        return SnapshotContractValidationResult(
            isValid: reasons.isEmpty,
            reasons: reasons
        )
    }

    func toMaterializationInput(rawPayloadFingerprint: String? = nil) -> SnapshotMaterializationInput {
        let mappedFiles = files.map { file in
            SnapshotMaterializationInput.FilePayload(
                role: .init(rawValue: file.role.rawValue) ?? .flows,
                data: file.data,
                recordCountHint: file.recordCountHint,
                checksumSHA256: file.checksumSHA256
            )
        }

        return SnapshotMaterializationInput(
            source: source,
            providerID: providerID,
            upstreamVersion: upstreamVersion,
            fetchedAt: fetchedAt,
            rawPayloadFingerprint: rawPayloadFingerprint,
            files: mappedFiles,
            metadata: metadata
        )
    }
}

enum ExternalDatasetAdapterError: Error, Equatable {
    case networkUnavailable
    case timeout(seconds: Int)
    case unauthorized
    case forbidden
    case rateLimited(retryAfterSeconds: Int?)
    case payloadInvalid(reason: String)
    case schemaIncompatible(upstreamSchemaVersion: String)
    case unsupportedUpstreamVersion(version: String)
    case datasetEmpty
    case partialData(missingRoles: Set<ExternalDatasetPayload.FilePayload.Role>)
    case upstreamTemporary(reason: String)
    case unknown(reason: String)

    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .timeout, .rateLimited, .upstreamTemporary:
            return true
        default:
            return false
        }
    }

    var category: String {
        switch self {
        case .networkUnavailable, .timeout:
            return "transport"
        case .unauthorized, .forbidden:
            return "auth"
        case .rateLimited, .upstreamTemporary:
            return "upstream_temporary"
        case .payloadInvalid, .datasetEmpty, .partialData:
            return "payload"
        case .schemaIncompatible, .unsupportedUpstreamVersion:
            return "compatibility"
        case .unknown:
            return "unknown"
        }
    }
}

protocol ExternalDatasetAdapting {
    var source: FlowDatasetSource { get }
    var capabilities: ExternalDatasetAdapterCapabilities { get }

    func fetch(request: ExternalDatasetFetchRequest) async throws -> ExternalDatasetPayload
}
