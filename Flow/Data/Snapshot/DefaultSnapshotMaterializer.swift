import CryptoKit
import Foundation

struct DefaultSnapshotMaterializer: SnapshotMaterializing {
    private let compatibilityChecker: DatasetCompatibilityChecking

    init(compatibilityChecker: DatasetCompatibilityChecking = DatasetCompatibilityChecker()) {
        self.compatibilityChecker = compatibilityChecker
    }

    func materialize(input: SnapshotMaterializationInput) async throws -> SnapshotMaterializationResult {
        let requiredRoles = Set(SnapshotMaterializationInput.FilePayload.Role.allCases)
        let roleSet = Set(input.files.map(\.role))
        let missingRoles = requiredRoles.subtracting(roleSet)
        if !missingRoles.isEmpty {
            return SnapshotMaterializationResult(
                status: .rejected,
                contract: nil,
                warnings: missingRoles
                    .map { "required_file_missing:\($0.rawValue)" }
                    .sorted()
            )
        }

        let schemaVersion = input.metadata["schema_version"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let timeCoverage = input.metadata["time_coverage"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let spatialLevelRaw = input.metadata["spatial_coverage"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let spatialLevel = SpatialLevel(rawValue: spatialLevelRaw) else {
            return SnapshotMaterializationResult(
                status: .rejected,
                contract: nil,
                warnings: ["spatial_coverage_invalid"]
            )
        }

        if schemaVersion.isEmpty {
            return SnapshotMaterializationResult(status: .rejected, contract: nil, warnings: ["schema_version_missing"])
        }
        if timeCoverage.isEmpty {
            return SnapshotMaterializationResult(status: .rejected, contract: nil, warnings: ["time_coverage_missing"])
        }

        let datasetID = nonEmptyOrDefault(input.metadata["dataset_id"], defaultValue: "\(input.source.rawValue)-\(input.upstreamVersion)")
        let snapshotID = nonEmptyOrDefault(input.metadata["snapshot_id"], defaultValue: "\(input.source.rawValue)-\(input.upstreamVersion)")
        let recordsCount = inferRecordsCount(from: input.files)

        let dataset = FlowDataset(
            datasetID: datasetID,
            version: input.upstreamVersion,
            source: input.source.rawValue,
            createdAt: input.fetchedAt,
            spatialLevel: spatialLevel,
            timeCoverage: timeCoverage,
            recordsCount: recordsCount,
            schemaVersion: schemaVersion
        )

        let compatibility = compatibilityChecker.evaluate(dataset: dataset, source: input.source)
        let requiredFiles = input.files.map { file in
            SnapshotRequiredFile(
                role: SnapshotRequiredFile.Role(rawValue: file.role.rawValue) ?? .flows,
                relativePath: "\(file.role.rawValue).\(extensionFor(role: file.role))",
                checksumSHA256: file.checksumSHA256 ?? sha256Hex(for: file.data),
                byteCount: file.data.count,
                recordCount: file.recordCountHint ?? inferRecordCount(from: file)
            )
        }

        let contract = MaterializedSnapshotContract.from(
            dataset: dataset,
            source: input.source,
            compatibilityResult: compatibility,
            requiredFiles: requiredFiles,
            snapshotID: snapshotID
        )

        let validation = contract.validateStructure()
        if !validation.isValid {
            return SnapshotMaterializationResult(
                status: .rejected,
                contract: nil,
                warnings: validation.reasons
            )
        }

        return SnapshotMaterializationResult(
            status: .materialized,
            contract: contract,
            warnings: []
        )
    }

    private func nonEmptyOrDefault(_ value: String?, defaultValue: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultValue : trimmed
    }

    private func extensionFor(role: SnapshotMaterializationInput.FilePayload.Role) -> String {
        switch role {
        case .manifest, .nodes:
            return "json"
        case .flows:
            return "jsonl"
        }
    }

    private func inferRecordsCount(from files: [SnapshotMaterializationInput.FilePayload]) -> Int {
        if let flowFile = files.first(where: { $0.role == .flows }) {
            return flowFile.recordCountHint ?? inferRecordCount(from: flowFile)
        }
        return 0
    }

    private func inferRecordCount(from file: SnapshotMaterializationInput.FilePayload) -> Int {
        let text = String(decoding: file.data, as: UTF8.self)
        return text.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
