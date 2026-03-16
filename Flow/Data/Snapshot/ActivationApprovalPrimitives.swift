import Foundation

enum ActivationApprovalState: String, Codable, Hashable {
    case proposed
    case awaitingApproval
    case approved
    case rejected
    case cancelled
    case executed
    case executionBlocked
    case executionFailed
}

enum ActivationApprovalDecision: String, Codable, Hashable {
    case submitForApproval
    case approve
    case reject
    case cancel
}

enum StagedRolloutMode: String, Codable, Hashable {
    case immediate
    case staged
    case rollbackPrepared
    case dryRun
}

struct ActivationProposal: Codable, Hashable {
    let proposalID: String
    let source: FlowDatasetSource
    let action: SnapshotActivationCommand.Action
    let targetSnapshotID: String?
    let targetDatasetVersion: String?
    let createdAt: String
    let createdBy: String?
    let note: String?
    let approvalState: ActivationApprovalState
    let rolloutMode: StagedRolloutMode
    let executionReadinessSummary: String?
}

struct ActivationRolloutCommand: Codable, Hashable {
    let proposal: ActivationProposal
    let command: SnapshotActivationCommand
    let decidedBy: String?
    let decidedAt: String?
    let decisionReason: String?

    var source: FlowDatasetSource {
        proposal.source
    }

    var action: SnapshotActivationCommand.Action {
        proposal.action
    }

    var approvalState: ActivationApprovalState {
        proposal.approvalState
    }

    var rolloutMode: StagedRolloutMode {
        proposal.rolloutMode
    }

    static func directExecutionCompatible(
        command: SnapshotActivationCommand,
        rolloutMode: StagedRolloutMode = .immediate,
        executionReadinessSummary: String? = nil
    ) -> ActivationRolloutCommand {
        ActivationRolloutCommand(
            proposal: ActivationProposal(
                proposalID: command.context.commandID,
                source: command.source,
                action: command.action,
                targetSnapshotID: command.scaffoldTargetSnapshotID,
                targetDatasetVersion: command.scaffoldTargetDatasetVersion,
                createdAt: command.context.requestedAt,
                createdBy: command.context.requestedBy,
                note: command.context.note,
                approvalState: .approved,
                rolloutMode: rolloutMode,
                executionReadinessSummary: executionReadinessSummary
            ),
            command: command,
            decidedBy: command.context.requestedBy,
            decidedAt: command.context.requestedAt,
            decisionReason: nil
        )
    }

    func applying(
        _ decision: ActivationApprovalDecision,
        by actor: String?,
        at timestamp: String = ISO8601DateFormatter().string(from: Date()),
        reason: String? = nil
    ) -> ActivationRolloutCommand {
        ActivationRolloutCommand(
            proposal: ActivationProposal(
                proposalID: proposal.proposalID,
                source: proposal.source,
                action: proposal.action,
                targetSnapshotID: proposal.targetSnapshotID,
                targetDatasetVersion: proposal.targetDatasetVersion,
                createdAt: proposal.createdAt,
                createdBy: proposal.createdBy,
                note: proposal.note,
                approvalState: proposal.approvalState.applying(decision),
                rolloutMode: proposal.rolloutMode,
                executionReadinessSummary: proposal.executionReadinessSummary
            ),
            command: command,
            decidedBy: actor,
            decidedAt: timestamp,
            decisionReason: reason
        )
    }

    func markingExecuted(
        at timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) -> ActivationRolloutCommand {
        with(state: .executed, decidedAt: timestamp, decisionReason: decisionReason)
    }

    func markingExecutionBlocked(
        reason: String?,
        at timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) -> ActivationRolloutCommand {
        with(state: .executionBlocked, decidedAt: timestamp, decisionReason: reason)
    }

    func markingExecutionFailed(
        reason: String?,
        at timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) -> ActivationRolloutCommand {
        with(state: .executionFailed, decidedAt: timestamp, decisionReason: reason)
    }

    private func with(
        state: ActivationApprovalState,
        decidedAt timestamp: String?,
        decisionReason: String?
    ) -> ActivationRolloutCommand {
        ActivationRolloutCommand(
            proposal: ActivationProposal(
                proposalID: proposal.proposalID,
                source: proposal.source,
                action: proposal.action,
                targetSnapshotID: proposal.targetSnapshotID,
                targetDatasetVersion: proposal.targetDatasetVersion,
                createdAt: proposal.createdAt,
                createdBy: proposal.createdBy,
                note: proposal.note,
                approvalState: state,
                rolloutMode: proposal.rolloutMode,
                executionReadinessSummary: proposal.executionReadinessSummary
            ),
            command: command,
            decidedBy: decidedBy,
            decidedAt: timestamp,
            decisionReason: decisionReason
        )
    }
}

extension SnapshotActivationCommand {
    func proposedRollout(
        proposalID: String = UUID().uuidString,
        state: ActivationApprovalState = .proposed,
        rolloutMode: StagedRolloutMode = .immediate,
        createdAt: String? = nil,
        createdBy: String? = nil,
        note: String? = nil,
        executionReadinessSummary: String? = nil
    ) -> ActivationRolloutCommand {
        ActivationRolloutCommand(
            proposal: ActivationProposal(
                proposalID: proposalID,
                source: source,
                action: action,
                targetSnapshotID: scaffoldTargetSnapshotID,
                targetDatasetVersion: scaffoldTargetDatasetVersion,
                createdAt: createdAt ?? context.requestedAt,
                createdBy: createdBy ?? context.requestedBy,
                note: note ?? context.note,
                approvalState: state,
                rolloutMode: rolloutMode,
                executionReadinessSummary: executionReadinessSummary
            ),
            command: self,
            decidedBy: nil,
            decidedAt: nil,
            decisionReason: nil
        )
    }

    fileprivate var scaffoldTargetSnapshotID: String? {
        switch self {
        case .promote(let command):
            return command.snapshotID
        case .demote(let command):
            return command.expectedActiveSnapshotID
        case .rollback(let command):
            return command.expectedActiveSnapshotID
        }
    }

    fileprivate var scaffoldTargetDatasetVersion: String? {
        switch self {
        case .promote(let command):
            return command.datasetVersion
        case .demote, .rollback:
            return nil
        }
    }
}

private extension ActivationApprovalState {
    func applying(_ decision: ActivationApprovalDecision) -> ActivationApprovalState {
        switch decision {
        case .submitForApproval:
            return .awaitingApproval
        case .approve:
            return .approved
        case .reject:
            return .rejected
        case .cancel:
            return .cancelled
        }
    }
}
