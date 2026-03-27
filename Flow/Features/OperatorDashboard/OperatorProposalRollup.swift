import Foundation

enum OperatorProposalHealthState: Hashable {
    case none
    case draft
    case awaitingApproval
    case approvedReady
    case approvedBlocked
    case rejected
    case cancelled
    case attentionRequired
}

struct OperatorProposalRollup: Hashable {
    let source: FlowDatasetSource
    let latestProposalID: String?
    let targetSnapshotID: String?
    let targetDatasetVersion: String?
    let lifecycleState: RolloutProposalLifecycleState?
    let approvalState: ActivationApprovalState?
    let lifecycleSummary: String
    let latestTimestamp: String?
    let isTerminal: Bool
    let requiresAttention: Bool
    let healthState: OperatorProposalHealthState
}

struct OperatorProposalRollupResolver {
    func rollup(
        source: FlowDatasetSource,
        isLiveCapable: Bool,
        proposalSummary: OperatorProposalSummary?,
        approvalSummary: OperatorApprovalSummary?,
        rolloutReadinessSummary: OperatorRolloutReadinessSummary?,
        rolloutPreflight: RolloutPreflightResult?,
        healthSummary: OperatorSourceHealthSummary
    ) -> OperatorProposalRollup? {
        guard isLiveCapable else { return nil }

        guard let proposalSummary else {
            return OperatorProposalRollup(
                source: source,
                latestProposalID: nil,
                targetSnapshotID: nil,
                targetDatasetVersion: nil,
                lifecycleState: nil,
                approvalState: nil,
                lifecycleSummary: "No proposal",
                latestTimestamp: nil,
                isTerminal: false,
                requiresAttention: false,
                healthState: .none
            )
        }

        let healthState = proposalHealthState(
            proposalSummary: proposalSummary,
            approvalSummary: approvalSummary,
            rolloutReadinessSummary: rolloutReadinessSummary,
            rolloutPreflight: rolloutPreflight,
            healthSummary: healthSummary
        )

        return OperatorProposalRollup(
            source: source,
            latestProposalID: proposalSummary.proposalID,
            targetSnapshotID: proposalSummary.targetSnapshotID,
            targetDatasetVersion: proposalSummary.targetDatasetVersion,
            lifecycleState: proposalSummary.lifecycleState,
            approvalState: proposalSummary.approvalState,
            lifecycleSummary: lifecycleSummary(
                proposalSummary: proposalSummary,
                rolloutReadinessSummary: rolloutReadinessSummary
            ),
            latestTimestamp: proposalSummary.lastDecisionAt ?? proposalSummary.updatedAt,
            isTerminal: isTerminal(proposalSummary.lifecycleState),
            requiresAttention: requiresAttention(healthState),
            healthState: healthState
        )
    }

    private func proposalHealthState(
        proposalSummary: OperatorProposalSummary,
        approvalSummary: OperatorApprovalSummary?,
        rolloutReadinessSummary: OperatorRolloutReadinessSummary?,
        rolloutPreflight: RolloutPreflightResult?,
        healthSummary: OperatorSourceHealthSummary
    ) -> OperatorProposalHealthState {
        switch proposalSummary.lifecycleState {
        case .draft:
            return .draft
        case .proposed:
            return .awaitingApproval
        case .rejected:
            return .rejected
        case .cancelled:
            return .cancelled
        case .approved, .readyForExecution:
            break
        }

        let hasBlockingPreflight = rolloutPreflight?.blockingReasons.isEmpty == false
        let readinessState = rolloutReadinessSummary?.state
        if readinessState == .immediateReady || readinessState == .stagedEligible {
            return .approvedReady
        }

        if readinessState == .blocked ||
            hasBlockingPreflight ||
            healthSummary.state == .blocked ||
            healthSummary.state == .recoveryNeeded ||
            healthSummary.state == .unavailable ||
            approvalSummary?.directExecutionCompatible == false {
            return .approvedBlocked
        }

        return .attentionRequired
    }

    private func lifecycleSummary(
        proposalSummary: OperatorProposalSummary,
        rolloutReadinessSummary: OperatorRolloutReadinessSummary?
    ) -> String {
        switch proposalSummary.lifecycleState {
        case .draft:
            return "Draft"
        case .proposed:
            return "Proposed -> Awaiting Approval"
        case .approved:
            switch rolloutReadinessSummary?.state {
            case .immediateReady:
                return "Approved -> Immediate Ready"
            case .stagedEligible:
                return "Approved -> Staged Eligible"
            case .blocked:
                return "Approved -> Blocked"
            case .notReady:
                return "Approved -> Not Ready"
            case .staticBaseline, .none:
                return "Approved"
            }
        case .rejected:
            return "Rejected"
        case .cancelled:
            return "Cancelled"
        case .readyForExecution:
            return "Ready For Execution"
        }
    }

    private func isTerminal(_ lifecycleState: RolloutProposalLifecycleState) -> Bool {
        switch lifecycleState {
        case .rejected, .cancelled:
            return true
        case .draft, .proposed, .approved, .readyForExecution:
            return false
        }
    }

    private func requiresAttention(_ healthState: OperatorProposalHealthState) -> Bool {
        switch healthState {
        case .approvedBlocked, .rejected, .cancelled, .attentionRequired:
            return true
        case .none, .draft, .awaitingApproval, .approvedReady:
            return false
        }
    }
}
