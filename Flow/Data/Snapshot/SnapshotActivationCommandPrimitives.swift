import Foundation

enum SnapshotActivationCommandTrigger: String, Codable, Hashable {
    case operatorManual
    case operatorConfirmed
    case recoveryRollback
}

struct SnapshotActivationCommandContext: Codable, Hashable {
    let commandID: String
    let requestedAt: String
    let trigger: SnapshotActivationCommandTrigger
    let requestedBy: String?
    let note: String?

    init(
        commandID: String = UUID().uuidString,
        requestedAt: String = ISO8601DateFormatter().string(from: Date()),
        trigger: SnapshotActivationCommandTrigger,
        requestedBy: String? = nil,
        note: String? = nil
    ) {
        self.commandID = commandID
        self.requestedAt = requestedAt
        self.trigger = trigger
        self.requestedBy = requestedBy
        self.note = note
    }
}

struct PromoteSnapshotCommand: Codable, Hashable {
    let source: FlowDatasetSource
    let snapshotID: String?
    let datasetVersion: String?
    let context: SnapshotActivationCommandContext

    init(
        source: FlowDatasetSource,
        snapshotID: String? = nil,
        datasetVersion: String? = nil,
        context: SnapshotActivationCommandContext
    ) {
        self.source = source
        self.snapshotID = snapshotID
        self.datasetVersion = datasetVersion
        self.context = context
    }
}

struct DemoteSnapshotCommand: Codable, Hashable {
    let source: FlowDatasetSource
    let expectedActiveSnapshotID: String?
    let preserveLastKnownGood: Bool
    let context: SnapshotActivationCommandContext
}

struct RollbackSnapshotCommand: Codable, Hashable {
    let source: FlowDatasetSource
    let expectedActiveSnapshotID: String?
    let context: SnapshotActivationCommandContext
}

enum SnapshotActivationCommand: Codable, Hashable {
    case promote(PromoteSnapshotCommand)
    case demote(DemoteSnapshotCommand)
    case rollback(RollbackSnapshotCommand)

    enum Action: String, Codable, Hashable {
        case promote
        case demote
        case rollback
    }

    var source: FlowDatasetSource {
        switch self {
        case .promote(let command):
            command.source
        case .demote(let command):
            command.source
        case .rollback(let command):
            command.source
        }
    }

    var context: SnapshotActivationCommandContext {
        switch self {
        case .promote(let command):
            command.context
        case .demote(let command):
            command.context
        case .rollback(let command):
            command.context
        }
    }

    var action: Action {
        switch self {
        case .promote:
            .promote
        case .demote:
            .demote
        case .rollback:
            .rollback
        }
    }

    func validationIssues() -> [SnapshotActivationCommandValidationIssue] {
        switch self {
        case .promote(let command):
            var issues: [SnapshotActivationCommandValidationIssue] = []
            let normalizedSnapshotID = command.snapshotID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedVersion = command.datasetVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedSnapshotID?.isEmpty == true {
                issues.append(.emptySnapshotID)
            }
            if normalizedVersion?.isEmpty == true {
                issues.append(.emptyDatasetVersion)
            }
            let hasSnapshotID = !(normalizedSnapshotID?.isEmpty ?? true)
            let hasVersion = !(normalizedVersion?.isEmpty ?? true)
            if !hasSnapshotID && !hasVersion {
                issues.append(.missingTargetReference)
            }
            return issues
        case .demote, .rollback:
            return []
        }
    }
}

enum SnapshotActivationCommandValidationIssue: String, Hashable {
    case missingTargetReference
    case emptySnapshotID
    case emptyDatasetVersion
}

enum SnapshotActivationExecutionStatus: String, Hashable {
    case succeeded
    case blocked
    case failed
    case noOp
}

enum SnapshotActivationBlockReason: String, Hashable {
    case commandInvalid
    case snapshotNotFound
    case snapshotNotEligible
    case snapshotIncompatible
    case noActiveSnapshot
    case noRollbackTarget
    case sourceMismatch
    case alreadyActive
    case alreadyInactive
    case policyRejected
}

enum SnapshotActivationFailureReason: String, Hashable {
    case policyEvaluationFailed
    case stateMutationFailed
    case persistenceFailed
    case unknown
}

struct SnapshotActivationExecutionResult: Hashable {
    let command: SnapshotActivationCommand
    let status: SnapshotActivationExecutionStatus
    let occurredAt: String
    let previousState: SnapshotActivationState?
    let resultingState: SnapshotActivationState?
    let blockReason: SnapshotActivationBlockReason?
    let failureReason: SnapshotActivationFailureReason?
    let details: [String]

    static func succeeded(
        command: SnapshotActivationCommand,
        previousState: SnapshotActivationState?,
        resultingState: SnapshotActivationState,
        details: [String] = [],
        occurredAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> SnapshotActivationExecutionResult {
        SnapshotActivationExecutionResult(
            command: command,
            status: .succeeded,
            occurredAt: occurredAt,
            previousState: previousState,
            resultingState: resultingState,
            blockReason: nil,
            failureReason: nil,
            details: details
        )
    }

    static func blocked(
        command: SnapshotActivationCommand,
        reason: SnapshotActivationBlockReason,
        previousState: SnapshotActivationState?,
        details: [String] = [],
        occurredAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> SnapshotActivationExecutionResult {
        SnapshotActivationExecutionResult(
            command: command,
            status: .blocked,
            occurredAt: occurredAt,
            previousState: previousState,
            resultingState: previousState,
            blockReason: reason,
            failureReason: nil,
            details: details
        )
    }

    static func failed(
        command: SnapshotActivationCommand,
        reason: SnapshotActivationFailureReason,
        previousState: SnapshotActivationState?,
        details: [String] = [],
        occurredAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> SnapshotActivationExecutionResult {
        SnapshotActivationExecutionResult(
            command: command,
            status: .failed,
            occurredAt: occurredAt,
            previousState: previousState,
            resultingState: previousState,
            blockReason: nil,
            failureReason: reason,
            details: details
        )
    }

    static func noOp(
        command: SnapshotActivationCommand,
        reason: SnapshotActivationBlockReason,
        currentState: SnapshotActivationState?,
        details: [String] = [],
        occurredAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> SnapshotActivationExecutionResult {
        SnapshotActivationExecutionResult(
            command: command,
            status: .noOp,
            occurredAt: occurredAt,
            previousState: currentState,
            resultingState: currentState,
            blockReason: reason,
            failureReason: nil,
            details: details
        )
    }
}

extension SnapshotActivationBlockReason {
    static func from(activationDecision: SnapshotActivationDecision) -> SnapshotActivationBlockReason {
        switch activationDecision.status {
        case .snapshotNotFound:
            return .snapshotNotFound
        case .noCandidate:
            return .policyRejected
        case .storedButNotActivatable:
            if activationDecision.reasons.contains(where: { $0.hasPrefix("compatibility_") || $0.contains("schema_version_unsupported") }) {
                return .snapshotIncompatible
            }
            return .snapshotNotEligible
        case .activatable:
            return .policyRejected
        }
    }

    static func from(rollbackDecision: SnapshotRollbackDecision) -> SnapshotActivationBlockReason {
        switch rollbackDecision.status {
        case .rollbackAvailable:
            return .policyRejected
        case .noSafeRollback:
            return .noRollbackTarget
        }
    }
}
