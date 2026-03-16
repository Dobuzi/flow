import Foundation

enum OperatorRolloutReadinessState: Hashable {
    case staticBaseline
    case immediateReady
    case stagedEligible
    case blocked
    case notReady
}

struct OperatorApprovalSummary: Hashable {
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
        healthSummary: OperatorSourceHealthSummary
    ) -> OperatorApprovalSummary? {
        guard isLiveCapable, let liveSummary else { return nil }

        let readiness = rolloutReadinessSummary(
            isLiveCapable: isLiveCapable,
            liveSummary: liveSummary,
            healthSummary: healthSummary
        )

        if healthSummary.state == .recoveryNeeded {
            return OperatorApprovalSummary(
                approvalState: .awaitingApproval,
                decisionSummary: "Recovered state should be reviewed",
                rolloutMode: .staged,
                directExecutionCompatible: false
            )
        }

        switch readiness.state {
        case .immediateReady:
            return OperatorApprovalSummary(
                approvalState: .approved,
                decisionSummary: "Direct execution compatible",
                rolloutMode: .immediate,
                directExecutionCompatible: true
            )

        case .stagedEligible:
            return OperatorApprovalSummary(
                approvalState: .approved,
                decisionSummary: "Rollback-prepared rollout compatible",
                rolloutMode: .rollbackPrepared,
                directExecutionCompatible: true
            )

        case .blocked:
            return OperatorApprovalSummary(
                approvalState: .proposed,
                decisionSummary: "Candidate proposed but blocked",
                rolloutMode: .staged,
                directExecutionCompatible: false
            )

        case .notReady:
            return OperatorApprovalSummary(
                approvalState: .awaitingApproval,
                decisionSummary: "Awaiting candidate readiness review",
                rolloutMode: .staged,
                directExecutionCompatible: false
            )

        case .staticBaseline:
            return nil
        }
    }

    func rolloutReadinessSummary(
        isLiveCapable: Bool,
        liveSummary: OperatorSourceLiveSummary?,
        healthSummary: OperatorSourceHealthSummary
    ) -> OperatorRolloutReadinessSummary {
        guard isLiveCapable, let liveSummary else {
            return OperatorRolloutReadinessSummary(
                state: .staticBaseline,
                summary: "Static baseline dataset",
                blockedReason: nil
            )
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
            if liveSummary.rollbackAvailable && liveSummary.activeSnapshotID != nil {
                return OperatorRolloutReadinessSummary(
                    state: .stagedEligible,
                    summary: "Rollback-prepared rollout available",
                    blockedReason: nil
                )
            }
            return OperatorRolloutReadinessSummary(
                state: .immediateReady,
                summary: "Ready for immediate execution",
                blockedReason: nil
            )
        }
    }
}
