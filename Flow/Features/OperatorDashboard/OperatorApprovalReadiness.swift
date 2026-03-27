import Foundation

struct OperatorProposalSummary: Hashable {
    let proposalID: String
    let lifecycleState: RolloutProposalLifecycleState
    let approvalState: ActivationApprovalState
    let rolloutMode: StagedRolloutMode
    let targetSnapshotID: String?
    let targetDatasetVersion: String?
    let updatedAt: String
    let lastDecisionAt: String?
    let lastDecisionReason: String?

    init(proposal: RolloutProposal) {
        self.proposalID = proposal.id
        self.lifecycleState = proposal.lifecycleState
        self.approvalState = proposal.approvalState
        self.rolloutMode = proposal.rolloutMode
        self.targetSnapshotID = proposal.targetSnapshotID
        self.targetDatasetVersion = proposal.targetDatasetVersion
        self.updatedAt = proposal.updatedAt
        self.lastDecisionAt = proposal.lastDecisionAt
        self.lastDecisionReason = proposal.lastDecisionReason
    }
}

enum OperatorRolloutReadinessState: Hashable {
    case staticBaseline
    case immediateReady
    case stagedEligible
    case blocked
    case notReady
}

struct OperatorApprovalSummary: Hashable {
    let proposalID: String
    let proposalLifecycleState: RolloutProposalLifecycleState
    let approvalState: ActivationApprovalState
    let decisionSummary: String
    let rolloutMode: StagedRolloutMode
    let directExecutionCompatible: Bool
}

struct OperatorRolloutReadinessSummary: Hashable {
    let state: OperatorRolloutReadinessState
    let summary: String
    let blockedReason: String?
}

struct OperatorApprovalReadinessResolver {
    func approvalSummary(
        isLiveCapable: Bool,
        liveSummary: OperatorSourceLiveSummary?,
        healthSummary: OperatorSourceHealthSummary,
        proposalSummary: OperatorProposalSummary?
    ) -> OperatorApprovalSummary? {
        guard isLiveCapable, let liveSummary, let proposalSummary else { return nil }

        let readiness = rolloutReadinessSummary(
            isLiveCapable: isLiveCapable,
            liveSummary: liveSummary,
            healthSummary: healthSummary,
            proposalSummary: proposalSummary
        )

        return OperatorApprovalSummary(
            proposalID: proposalSummary.proposalID,
            proposalLifecycleState: proposalSummary.lifecycleState,
            approvalState: proposalSummary.approvalState,
            decisionSummary: approvalDecisionSummary(
                proposalSummary: proposalSummary,
                readiness: readiness,
                healthSummary: healthSummary
            ),
            rolloutMode: proposalSummary.rolloutMode,
            directExecutionCompatible: readiness.state == .immediateReady || readiness.state == .stagedEligible
        )
    }

    func rolloutReadinessSummary(
        isLiveCapable: Bool,
        liveSummary: OperatorSourceLiveSummary?,
        healthSummary: OperatorSourceHealthSummary,
        proposalSummary: OperatorProposalSummary?
    ) -> OperatorRolloutReadinessSummary {
        guard isLiveCapable, let liveSummary else {
            return OperatorRolloutReadinessSummary(
                state: .staticBaseline,
                summary: "Static baseline dataset",
                blockedReason: nil
            )
        }

        guard let proposalSummary else {
            return OperatorRolloutReadinessSummary(
                state: .notReady,
                summary: "No rollout proposal",
                blockedReason: nil
            )
        }

        switch proposalSummary.lifecycleState {
        case .draft:
            return OperatorRolloutReadinessSummary(
                state: .notReady,
                summary: "Draft proposal not submitted",
                blockedReason: nil
            )
        case .proposed:
            return OperatorRolloutReadinessSummary(
                state: .notReady,
                summary: "Awaiting approval",
                blockedReason: nil
            )
        case .rejected:
            return OperatorRolloutReadinessSummary(
                state: .blocked,
                summary: "Proposal rejected",
                blockedReason: proposalSummary.lastDecisionReason ?? "Proposal rejected"
            )
        case .cancelled:
            return OperatorRolloutReadinessSummary(
                state: .blocked,
                summary: "Proposal cancelled",
                blockedReason: proposalSummary.lastDecisionReason ?? "Proposal cancelled"
            )
        case .approved, .readyForExecution:
            break
        }

        if healthSummary.state == .recoveryNeeded {
            return OperatorRolloutReadinessSummary(
                state: .blocked,
                summary: "Review recovered state before rollout",
                blockedReason: "Startup recovery degraded"
            )
        }

        guard liveSummary.latestCandidateSnapshotID != nil else {
            return OperatorRolloutReadinessSummary(
                state: .notReady,
                summary: "No candidate snapshot available",
                blockedReason: nil
            )
        }

        if liveSummary.syncState == .failed {
            return OperatorRolloutReadinessSummary(
                state: .blocked,
                summary: "Rollout unavailable",
                blockedReason: "Sync failed"
            )
        }

        if liveSummary.latestCandidateCompatibility != .compatible {
            return OperatorRolloutReadinessSummary(
                state: .blocked,
                summary: "Candidate blocked",
                blockedReason: "Candidate incompatible"
            )
        }

        if liveSummary.latestCandidateEligibleForActivation == false {
            return OperatorRolloutReadinessSummary(
                state: .blocked,
                summary: "Candidate blocked",
                blockedReason: "Candidate not eligible"
            )
        }

        switch liveSummary.readiness {
        case .blocked:
            return OperatorRolloutReadinessSummary(
                state: .blocked,
                summary: "Candidate blocked",
                blockedReason: "Readiness blocked"
            )
        case .pendingValidation:
            return OperatorRolloutReadinessSummary(
                state: .notReady,
                summary: "Pending validation",
                blockedReason: nil
            )
        case .staticOnly:
            return OperatorRolloutReadinessSummary(
                state: .staticBaseline,
                summary: "Static baseline dataset",
                blockedReason: nil
            )
        case .ready:
            switch proposalSummary.rolloutMode {
            case .immediate:
                return OperatorRolloutReadinessSummary(
                    state: .immediateReady,
                    summary: "Approved for immediate execution",
                    blockedReason: nil
                )
            case .staged, .rollbackPrepared:
                if liveSummary.rollbackAvailable && liveSummary.activeSnapshotID != nil {
                    return OperatorRolloutReadinessSummary(
                        state: .stagedEligible,
                        summary: "Approved for staged execution",
                        blockedReason: nil
                    )
                }
                return OperatorRolloutReadinessSummary(
                    state: .notReady,
                    summary: "Rollback preparation required",
                    blockedReason: nil
                )
            case .dryRun:
                return OperatorRolloutReadinessSummary(
                    state: .notReady,
                    summary: "Dry-run proposal is not executable",
                    blockedReason: nil
                )
            }
        }
    }

    private func approvalDecisionSummary(
        proposalSummary: OperatorProposalSummary,
        readiness: OperatorRolloutReadinessSummary,
        healthSummary: OperatorSourceHealthSummary
    ) -> String {
        switch proposalSummary.lifecycleState {
        case .draft:
            return "Draft proposal not submitted"
        case .proposed:
            return proposalSummary.lastDecisionReason ?? "Awaiting approval"
        case .approved:
            if healthSummary.state == .recoveryNeeded {
                return "Approved but recovered state needs review"
            }
            switch readiness.state {
            case .immediateReady:
                return "Approved for immediate execution"
            case .stagedEligible:
                return "Approved for staged execution"
            case .blocked:
                return proposalSummary.lastDecisionReason ?? "Approved but blocked by rollout checks"
            case .notReady:
                return proposalSummary.lastDecisionReason ?? "Approved but not ready for execution"
            case .staticBaseline:
                return proposalSummary.lastDecisionReason ?? "Approved"
            }
        case .rejected:
            return proposalSummary.lastDecisionReason ?? "Proposal rejected"
        case .cancelled:
            return proposalSummary.lastDecisionReason ?? "Proposal cancelled"
        case .readyForExecution:
            return "Ready for execution"
        }
    }
}
