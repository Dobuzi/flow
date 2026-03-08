import CryptoKit
import Foundation

struct SnapshotIntegrityIssue: Hashable {
    enum Severity: String, Hashable {
        case error
        case warning
    }

    let code: String
    let message: String
    let severity: Severity
}

struct SnapshotIntegrityCheckResult: Hashable {
    let isValid: Bool
    let issues: [SnapshotIntegrityIssue]
}

protocol SnapshotIntegrityChecking {
    func check(
        contract: MaterializedSnapshotContract,
        files: [SnapshotMaterializationInput.FilePayload]
    ) -> SnapshotIntegrityCheckResult
}

struct DefaultSnapshotIntegrityChecker: SnapshotIntegrityChecking {
    func check(
        contract: MaterializedSnapshotContract,
        files: [SnapshotMaterializationInput.FilePayload]
    ) -> SnapshotIntegrityCheckResult {
        var issues: [SnapshotIntegrityIssue] = []
        let requiredRoles = MaterializedSnapshotContract.requiredFileRoles
        let contractByRole = contract.requiredFiles.reduce(into: [SnapshotRequiredFile.Role: SnapshotRequiredFile]()) { partial, file in
            partial[file.role] = file
        }
        let fileByRole = files.reduce(into: [SnapshotRequiredFile.Role: SnapshotMaterializationInput.FilePayload]()) { partial, file in
            let role = SnapshotRequiredFile.Role(rawValue: file.role.rawValue) ?? .flows
            partial[role] = file
        }

        for role in requiredRoles.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let contractFile = contractByRole[role] else {
                issues.append(
                    SnapshotIntegrityIssue(
                        code: "required_contract_file_missing:\(role.rawValue)",
                        message: "Required contract file role is missing.",
                        severity: .error
                    )
                )
                continue
            }

            guard let materializedFile = fileByRole[role] else {
                issues.append(
                    SnapshotIntegrityIssue(
                        code: "materialized_file_missing:\(role.rawValue)",
                        message: "Materialized file payload is missing for required role.",
                        severity: .error
                    )
                )
                continue
            }

            let checksum = (contractFile.checksumSHA256 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if checksum.isEmpty {
                issues.append(
                    SnapshotIntegrityIssue(
                        code: "checksum_missing:\(role.rawValue)",
                        message: "Checksum is required for integrity verification.",
                        severity: .error
                    )
                )
            } else {
                let actualChecksum = sha256Hex(for: materializedFile.data)
                if checksum.lowercased() != actualChecksum.lowercased() {
                    issues.append(
                        SnapshotIntegrityIssue(
                            code: "checksum_mismatch:\(role.rawValue)",
                            message: "Checksum does not match materialized file payload.",
                            severity: .error
                        )
                    )
                }
            }

            if let expectedByteCount = contractFile.byteCount, expectedByteCount != materializedFile.data.count {
                issues.append(
                    SnapshotIntegrityIssue(
                        code: "byte_count_mismatch:\(role.rawValue)",
                        message: "Byte count does not match materialized file payload.",
                        severity: .error
                    )
                )
            }

            if let expectedRecordCount = contractFile.recordCount {
                let actualRecordCount = materializedFile.recordCountHint ?? inferRecordCount(from: materializedFile.data)
                if expectedRecordCount != actualRecordCount {
                    issues.append(
                        SnapshotIntegrityIssue(
                            code: "record_count_mismatch:\(role.rawValue)",
                            message: "Record count does not match materialized file payload.",
                            severity: .error
                        )
                    )
                }
            }
        }

        return SnapshotIntegrityCheckResult(
            isValid: issues.filter { $0.severity == .error }.isEmpty,
            issues: issues
        )
    }

    private func inferRecordCount(from data: Data) -> Int {
        let text = String(decoding: data, as: UTF8.self)
        return text.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
