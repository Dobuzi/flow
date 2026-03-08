import Foundation

struct SnapshotRequiredFile: Codable, Hashable {
    enum Role: String, Codable, Hashable, CaseIterable {
        case manifest
        case nodes
        case flows
    }

    let role: Role
    let relativePath: String
    let checksumSHA256: String?
    let byteCount: Int?
    let recordCount: Int?
}

struct SnapshotCompatibilityMetadata: Codable, Hashable {
    let isSchemaCompatible: Bool
    let isCompatibilityCheckPassed: Bool
    let compatibilityReasons: [String]
    let checkedFields: [String]
}

struct SnapshotActivationEligibility: Codable, Hashable {
    enum State: String, Codable, Hashable {
        case eligible
        case ineligible
        case pending
    }

    let state: State
    let reasons: [String]
}

struct SnapshotContractValidationResult: Hashable {
    let isValid: Bool
    let reasons: [String]
}

struct MaterializedSnapshotContract: Codable, Hashable {
    let snapshotID: String
    let source: FlowDatasetSource
    let schemaVersion: String
    let datasetVersion: String
    let generatedAt: String
    let timeCoverage: String
    let spatialCoverage: SpatialLevel
    let recordsCount: Int
    let requiredFiles: [SnapshotRequiredFile]
    let compatibility: SnapshotCompatibilityMetadata
    let activationEligibility: SnapshotActivationEligibility

    static let requiredFileRoles: Set<SnapshotRequiredFile.Role> = [.manifest, .nodes, .flows]

    func validateStructure() -> SnapshotContractValidationResult {
        var reasons: [String] = []

        if snapshotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("snapshot_id_missing")
        }
        if schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("schema_version_missing")
        }
        if datasetVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("dataset_version_missing")
        }
        if generatedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("generated_at_missing")
        }
        if timeCoverage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("time_coverage_missing")
        }
        if recordsCount < 0 {
            reasons.append("records_count_negative")
        }

        let roleSet = Set(requiredFiles.map(\.role))
        for role in Self.requiredFileRoles where !roleSet.contains(role) {
            reasons.append("required_file_missing:\(role.rawValue)")
        }

        if requiredFiles.contains(where: { $0.relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            reasons.append("required_file_path_missing")
        }

        if activationEligibility.state == .eligible {
            if !compatibility.isSchemaCompatible || !compatibility.isCompatibilityCheckPassed {
                reasons.append("eligible_but_incompatible")
            }
            if !activationEligibility.reasons.isEmpty {
                reasons.append("eligible_with_reasons")
            }
        }

        return SnapshotContractValidationResult(
            isValid: reasons.isEmpty,
            reasons: reasons
        )
    }

    static func from(
        dataset: FlowDataset,
        source: FlowDatasetSource,
        compatibilityResult: DatasetCompatibilityResult,
        requiredFiles: [SnapshotRequiredFile],
        snapshotID: String? = nil,
        activationEligibility: SnapshotActivationEligibility? = nil
    ) -> MaterializedSnapshotContract {
        let defaultEligibility = SnapshotActivationEligibility(
            state: compatibilityResult.isCompatible ? .eligible : .ineligible,
            reasons: compatibilityResult.reasons
        )

        return MaterializedSnapshotContract(
            snapshotID: snapshotID ?? "\(source.rawValue)-\(dataset.version)",
            source: source,
            schemaVersion: dataset.schemaVersion,
            datasetVersion: dataset.version,
            generatedAt: dataset.createdAt,
            timeCoverage: dataset.timeCoverage,
            spatialCoverage: dataset.spatialLevel,
            recordsCount: dataset.recordsCount,
            requiredFiles: requiredFiles,
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: !compatibilityResult.reasons.contains("schema_version_unsupported")
                    && !compatibilityResult.reasons.contains("national_schema_version_unsupported"),
                isCompatibilityCheckPassed: compatibilityResult.isCompatible,
                compatibilityReasons: compatibilityResult.reasons,
                checkedFields: compatibilityResult.checkedFields
            ),
            activationEligibility: activationEligibility ?? defaultEligibility
        )
    }
}
