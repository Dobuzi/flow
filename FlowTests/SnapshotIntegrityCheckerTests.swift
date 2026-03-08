import CryptoKit
import Foundation
import Testing
@testable import Flow

struct SnapshotIntegrityCheckerTests {
    @Test
    func passesForValidContractAndFiles() {
        let checker = DefaultSnapshotIntegrityChecker()
        let files = makeFiles()
        let contract = makeContract(from: files)

        let result = checker.check(contract: contract, files: files)
        #expect(result.isValid)
        #expect(result.issues.isEmpty)
    }

    @Test
    func detectsMissingRequiredRole() {
        let checker = DefaultSnapshotIntegrityChecker()
        var files = makeFiles()
        files.removeAll { $0.role == .flows }
        let contract = makeContract(from: makeFiles())

        let result = checker.check(contract: contract, files: files)
        #expect(!result.isValid)
        #expect(result.issues.map(\.code).contains("materialized_file_missing:flows"))
    }

    @Test
    func detectsChecksumMismatch() {
        let checker = DefaultSnapshotIntegrityChecker()
        let files = makeFiles()
        var contract = makeContract(from: files)
        contract = MaterializedSnapshotContract(
            snapshotID: contract.snapshotID,
            source: contract.source,
            schemaVersion: contract.schemaVersion,
            datasetVersion: contract.datasetVersion,
            generatedAt: contract.generatedAt,
            timeCoverage: contract.timeCoverage,
            spatialCoverage: contract.spatialCoverage,
            recordsCount: contract.recordsCount,
            requiredFiles: contract.requiredFiles.map {
                if $0.role == .flows {
                    return SnapshotRequiredFile(
                        role: $0.role,
                        relativePath: $0.relativePath,
                        checksumSHA256: "deadbeef",
                        byteCount: $0.byteCount,
                        recordCount: $0.recordCount
                    )
                }
                return $0
            },
            compatibility: contract.compatibility,
            activationEligibility: contract.activationEligibility
        )

        let result = checker.check(contract: contract, files: files)
        #expect(!result.isValid)
        #expect(result.issues.map(\.code).contains("checksum_mismatch:flows"))
    }

    private func makeFiles() -> [SnapshotMaterializationInput.FilePayload] {
        [
            .init(role: .manifest, data: Data("{\"v\":1}".utf8), recordCountHint: nil, checksumSHA256: nil),
            .init(role: .nodes, data: Data("[]".utf8), recordCountHint: 0, checksumSHA256: nil),
            .init(role: .flows, data: Data("{\"v\":1}\n{\"v\":2}\n".utf8), recordCountHint: 2, checksumSHA256: nil)
        ]
    }

    private func makeContract(from files: [SnapshotMaterializationInput.FilePayload]) -> MaterializedSnapshotContract {
        let requiredFiles = files.map { file in
            SnapshotRequiredFile(
                role: SnapshotRequiredFile.Role(rawValue: file.role.rawValue) ?? .flows,
                relativePath: "\(file.role.rawValue).\(file.role == .flows ? "jsonl" : "json")",
                checksumSHA256: sha256Hex(for: file.data),
                byteCount: file.data.count,
                recordCount: file.recordCountHint
            )
        }

        return MaterializedSnapshotContract(
            snapshotID: "test-snapshot",
            source: .koreaNational,
            schemaVersion: "1.0.0",
            datasetVersion: "2026.01",
            generatedAt: "2026-03-08T00:00:00Z",
            timeCoverage: "2026-01~2026-12",
            spatialCoverage: .province,
            recordsCount: 2,
            requiredFiles: requiredFiles,
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: true,
                compatibilityReasons: [],
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(state: .eligible, reasons: [])
        )
    }

    private func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
