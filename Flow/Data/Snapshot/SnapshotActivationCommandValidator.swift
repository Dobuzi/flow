import Foundation

protocol SnapshotActivationCommandValidating {
    func validate(
        _ command: SnapshotActivationCommand,
        context: SnapshotActivationCommandValidationContext?
    ) -> SnapshotActivationCommandValidationResult
}

struct SnapshotActivationCommandValidationContext: Hashable {
    let isLiveCapable: Bool?
    let currentState: SnapshotActivationState?
    let candidateSnapshot: StoredSnapshotVersion?
    let rollbackTarget: StoredSnapshotVersion?

    init(
        isLiveCapable: Bool? = nil,
        currentState: SnapshotActivationState? = nil,
        candidateSnapshot: StoredSnapshotVersion? = nil,
        rollbackTarget: StoredSnapshotVersion? = nil
    ) {
        self.isLiveCapable = isLiveCapable
        self.currentState = currentState
        self.candidateSnapshot = candidateSnapshot
        self.rollbackTarget = rollbackTarget
    }
}

struct SnapshotActivationCommandValidationResult: Hashable {
    let command: SnapshotActivationCommand
    let issues: [SnapshotActivationCommandValidationIssueDetail]

    var isValid: Bool {
        !issues.contains(where: { $0.severity == .error })
    }

    static func valid(command: SnapshotActivationCommand) -> SnapshotActivationCommandValidationResult {
        SnapshotActivationCommandValidationResult(command: command, issues: [])
    }
}

enum SnapshotActivationCommandValidationIssueSeverity: String, Hashable {
    case warning
    case error
}

enum SnapshotActivationCommandValidationIssueCode: String, Hashable {
    case missingTargetReference
    case emptySnapshotID
    case emptyDatasetVersion
    case emptyExpectedActiveSnapshotID
    case emptyCommandID
    case malformedRequestedAt
    case currentStateSourceMismatch
    case candidateSourceMismatch
    case rollbackTargetSourceMismatch
    case rollbackUnsupportedForStaticSource
}

struct SnapshotActivationCommandValidationIssueDetail: Hashable {
    let code: SnapshotActivationCommandValidationIssueCode
    let severity: SnapshotActivationCommandValidationIssueSeverity
    let message: String
}

struct DefaultSnapshotActivationCommandValidator: SnapshotActivationCommandValidating {
    func validate(
        _ command: SnapshotActivationCommand,
        context: SnapshotActivationCommandValidationContext? = nil
    ) -> SnapshotActivationCommandValidationResult {
        var issues: [SnapshotActivationCommandValidationIssueDetail] = []

        issues.append(contentsOf: mapPrimitiveIssues(command.validationIssues()))
        issues.append(contentsOf: validateCommandContext(command.context))

        switch command {
        case .promote(let promote):
            issues.append(contentsOf: validatePromoteCommand(promote))
        case .demote(let demote):
            issues.append(contentsOf: validateDemoteCommand(demote))
        case .rollback(let rollback):
            issues.append(contentsOf: validateRollbackCommand(rollback, isLiveCapable: context?.isLiveCapable))
        }

        if let context {
            issues.append(contentsOf: validateContextConsistency(command: command, context: context))
        }

        return SnapshotActivationCommandValidationResult(command: command, issues: issues)
    }

    private func mapPrimitiveIssues(
        _ primitiveIssues: [SnapshotActivationCommandValidationIssue]
    ) -> [SnapshotActivationCommandValidationIssueDetail] {
        primitiveIssues.map { issue in
            switch issue {
            case .missingTargetReference:
                return .init(
                    code: .missingTargetReference,
                    severity: .error,
                    message: "Promote command requires snapshotID or datasetVersion."
                )
            case .emptySnapshotID:
                return .init(
                    code: .emptySnapshotID,
                    severity: .error,
                    message: "Promote command snapshotID must not be empty."
                )
            case .emptyDatasetVersion:
                return .init(
                    code: .emptyDatasetVersion,
                    severity: .error,
                    message: "Promote command datasetVersion must not be empty."
                )
            }
        }
    }

    private func validateCommandContext(
        _ context: SnapshotActivationCommandContext
    ) -> [SnapshotActivationCommandValidationIssueDetail] {
        var issues: [SnapshotActivationCommandValidationIssueDetail] = []

        if context.commandID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                .init(
                    code: .emptyCommandID,
                    severity: .error,
                    message: "Command context commandID must not be empty."
                )
            )
        }

        if ISO8601DateFormatter().date(from: context.requestedAt) == nil {
            issues.append(
                .init(
                    code: .malformedRequestedAt,
                    severity: .error,
                    message: "Command context requestedAt must be ISO-8601 compatible."
                )
            )
        }

        return issues
    }

    private func validatePromoteCommand(
        _ command: PromoteSnapshotCommand
    ) -> [SnapshotActivationCommandValidationIssueDetail] {
        // Promote-specific structural checks are covered by primitive validationIssues().
        // Keep a dedicated hook for future promote semantics.
        _ = command
        return []
    }

    private func validateDemoteCommand(
        _ command: DemoteSnapshotCommand
    ) -> [SnapshotActivationCommandValidationIssueDetail] {
        guard let expectedActiveSnapshotID = command.expectedActiveSnapshotID else {
            return []
        }

        if expectedActiveSnapshotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [
                .init(
                    code: .emptyExpectedActiveSnapshotID,
                    severity: .error,
                    message: "Demote command expectedActiveSnapshotID must not be empty when provided."
                )
            ]
        }

        return []
    }

    private func validateRollbackCommand(
        _ command: RollbackSnapshotCommand,
        isLiveCapable: Bool?
    ) -> [SnapshotActivationCommandValidationIssueDetail] {
        var issues: [SnapshotActivationCommandValidationIssueDetail] = []

        if let expectedActiveSnapshotID = command.expectedActiveSnapshotID,
           expectedActiveSnapshotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                .init(
                    code: .emptyExpectedActiveSnapshotID,
                    severity: .error,
                    message: "Rollback command expectedActiveSnapshotID must not be empty when provided."
                )
            )
        }

        if let isLiveCapable, !isLiveCapable {
            issues.append(
                .init(
                    code: .rollbackUnsupportedForStaticSource,
                    severity: .error,
                    message: "Rollback command is not supported for static/non-live sources."
                )
            )
        }

        return issues
    }

    private func validateContextConsistency(
        command: SnapshotActivationCommand,
        context: SnapshotActivationCommandValidationContext
    ) -> [SnapshotActivationCommandValidationIssueDetail] {
        var issues: [SnapshotActivationCommandValidationIssueDetail] = []

        if let currentState = context.currentState,
           currentState.source != command.source {
            issues.append(
                .init(
                    code: .currentStateSourceMismatch,
                    severity: .error,
                    message: "Current activation state source does not match command source."
                )
            )
        }

        if let candidate = context.candidateSnapshot,
           candidate.source != command.source {
            issues.append(
                .init(
                    code: .candidateSourceMismatch,
                    severity: .error,
                    message: "Candidate snapshot source does not match command source."
                )
            )
        }

        if let rollbackTarget = context.rollbackTarget,
           rollbackTarget.source != command.source {
            issues.append(
                .init(
                    code: .rollbackTargetSourceMismatch,
                    severity: .error,
                    message: "Rollback target snapshot source does not match command source."
                )
            )
        }

        return issues
    }
}
