import Foundation

enum RolloutChecklistStatus: Hashable {
    case passed
    case warning
    case blocked
    case notApplicable
}

enum RolloutChecklistKind: Hashable {
    case liveRolloutSupport
    case bootstrapRecovery
    case candidateCompatibility
    case candidateEligibility
    case refreshHealth
    case rollbackSafety
    case approvalCompatibility
    case rolloutReadiness
}

struct RolloutChecklistItem: Hashable {
    let kind: RolloutChecklistKind
    let title: String
    let status: RolloutChecklistStatus
    let detail: String
}

enum RolloutPreflightRecommendation: Hashable {
    case immediate
    case staged
    case blocked
    case notApplicable
}

struct RolloutPreflightResult: Hashable {
    let source: FlowDatasetSource
    let overallReady: Bool
    let checklistItems: [RolloutChecklistItem]
    let blockingReasons: [String]
    let warningReasons: [String]
    let recommendation: RolloutPreflightRecommendation
}

struct RolloutPreflightEvaluator {
    func evaluate(_ source: OperatorSourceSummary) -> RolloutPreflightResult {
        guard source.isLiveCapable,
              let live = source.liveSummary,
              let approval = source.approvalSummary,
              let readiness = source.rolloutReadinessSummary else {
            return RolloutPreflightResult(
                source: source.source,
                overallReady: false,
                checklistItems: [
                    RolloutChecklistItem(
                        kind: .liveRolloutSupport,
                        title: "Live rollout support",
                        status: .notApplicable,
                        detail: "Static baseline dataset"
                    )
                ],
                blockingReasons: [],
                warningReasons: [],
                recommendation: .notApplicable
            )
        }

        let items = [
            liveRolloutSupportItem(),
            bootstrapRecoveryItem(for: source.healthSummary),
            candidateCompatibilityItem(for: live),
            candidateEligibilityItem(for: live),
            refreshHealthItem(for: live, healthSummary: source.healthSummary),
            rollbackSafetyItem(for: live),
            approvalCompatibilityItem(for: approval),
            rolloutReadinessItem(for: readiness)
        ]

        let blockingReasons = items
            .filter { $0.status == .blocked }
            .map(\.detail)
        let warningReasons = items
            .filter { $0.status == .warning }
            .map(\.detail)

        return RolloutPreflightResult(
            source: source.source,
            overallReady: blockingReasons.isEmpty && items.contains(where: { $0.status == .passed }),
            checklistItems: items,
            blockingReasons: blockingReasons,
            warningReasons: warningReasons,
            recommendation: recommendation(
                approval: approval,
                readiness: readiness,
                blockingReasons: blockingReasons
            )
        )
    }

    private func liveRolloutSupportItem() -> RolloutChecklistItem {
        RolloutChecklistItem(
            kind: .liveRolloutSupport,
            title: "Live rollout support",
            status: .passed,
            detail: "Source supports live rollout controls"
        )
    }

    private func bootstrapRecoveryItem(for healthSummary: OperatorSourceHealthSummary) -> RolloutChecklistItem {
        if healthSummary.state == .recoveryNeeded {
            return RolloutChecklistItem(
                kind: .bootstrapRecovery,
                title: "Bootstrap recovery",
                status: .blocked,
                detail: "Recovered operator state should be reviewed"
            )
        }

        return RolloutChecklistItem(
            kind: .bootstrapRecovery,
            title: "Bootstrap recovery",
            status: .passed,
            detail: "Persistent operator state restored cleanly"
        )
    }

    private func candidateCompatibilityItem(for live: OperatorSourceLiveSummary) -> RolloutChecklistItem {
        guard live.latestCandidateSnapshotID != nil else {
            return RolloutChecklistItem(
                kind: .candidateCompatibility,
                title: "Candidate compatibility",
                status: .blocked,
                detail: "No candidate snapshot available"
            )
        }

        if live.latestCandidateCompatibility == .compatible {
            return RolloutChecklistItem(
                kind: .candidateCompatibility,
                title: "Candidate compatibility",
                status: .passed,
                detail: "Candidate is compatible"
            )
        }

        return RolloutChecklistItem(
            kind: .candidateCompatibility,
            title: "Candidate compatibility",
            status: .blocked,
            detail: "Candidate is incompatible"
        )
    }

    private func candidateEligibilityItem(for live: OperatorSourceLiveSummary) -> RolloutChecklistItem {
        guard live.latestCandidateSnapshotID != nil else {
            return RolloutChecklistItem(
                kind: .candidateEligibility,
                title: "Activation eligibility",
                status: .notApplicable,
                detail: "No candidate available"
            )
        }

        if live.latestCandidateEligibleForActivation == true {
            return RolloutChecklistItem(
                kind: .candidateEligibility,
                title: "Activation eligibility",
                status: .passed,
                detail: "Candidate is eligible for activation"
            )
        }

        if live.latestCandidateEligibleForActivation == false {
            return RolloutChecklistItem(
                kind: .candidateEligibility,
                title: "Activation eligibility",
                status: .blocked,
                detail: "Candidate is not eligible for activation"
            )
        }

        return RolloutChecklistItem(
            kind: .candidateEligibility,
            title: "Activation eligibility",
            status: .warning,
            detail: "Activation eligibility is unknown"
        )
    }

    private func refreshHealthItem(
        for live: OperatorSourceLiveSummary,
        healthSummary: OperatorSourceHealthSummary
    ) -> RolloutChecklistItem {
        if live.syncState == .failed {
            return RolloutChecklistItem(
                kind: .refreshHealth,
                title: "Refresh health",
                status: .blocked,
                detail: "Refresh sync failed"
            )
        }

        if live.lastRefreshOutcome == .failed || healthSummary.state == .degraded {
            return RolloutChecklistItem(
                kind: .refreshHealth,
                title: "Refresh health",
                status: .warning,
                detail: "Refresh health is degraded"
            )
        }

        return RolloutChecklistItem(
            kind: .refreshHealth,
            title: "Refresh health",
            status: .passed,
            detail: "Refresh health is stable"
        )
    }

    private func rollbackSafetyItem(for live: OperatorSourceLiveSummary) -> RolloutChecklistItem {
        if live.activeSnapshotID == nil {
            return RolloutChecklistItem(
                kind: .rollbackSafety,
                title: "Rollback safety",
                status: .notApplicable,
                detail: "No active snapshot to roll back from"
            )
        }

        if live.rollbackAvailable {
            return RolloutChecklistItem(
                kind: .rollbackSafety,
                title: "Rollback safety",
                status: .passed,
                detail: "Rollback target is available"
            )
        }

        return RolloutChecklistItem(
            kind: .rollbackSafety,
            title: "Rollback safety",
            status: .warning,
            detail: "No rollback target is currently available"
        )
    }

    private func approvalCompatibilityItem(for approval: OperatorApprovalSummary) -> RolloutChecklistItem {
        switch approval.approvalState {
        case .approved, .executed:
            return RolloutChecklistItem(
                kind: .approvalCompatibility,
                title: "Approval compatibility",
                status: .passed,
                detail: approval.decisionSummary
            )
        case .proposed, .awaitingApproval:
            return RolloutChecklistItem(
                kind: .approvalCompatibility,
                title: "Approval compatibility",
                status: .warning,
                detail: approval.decisionSummary
            )
        case .rejected, .cancelled, .executionBlocked, .executionFailed:
            return RolloutChecklistItem(
                kind: .approvalCompatibility,
                title: "Approval compatibility",
                status: .blocked,
                detail: approval.decisionSummary
            )
        }
    }

    private func rolloutReadinessItem(for readiness: OperatorRolloutReadinessSummary) -> RolloutChecklistItem {
        switch readiness.state {
        case .immediateReady, .stagedEligible:
            return RolloutChecklistItem(
                kind: .rolloutReadiness,
                title: "Rollout readiness",
                status: .passed,
                detail: readiness.summary
            )
        case .notReady:
            return RolloutChecklistItem(
                kind: .rolloutReadiness,
                title: "Rollout readiness",
                status: .warning,
                detail: readiness.summary
            )
        case .blocked:
            return RolloutChecklistItem(
                kind: .rolloutReadiness,
                title: "Rollout readiness",
                status: .blocked,
                detail: readiness.blockedReason ?? readiness.summary
            )
        case .staticBaseline:
            return RolloutChecklistItem(
                kind: .rolloutReadiness,
                title: "Rollout readiness",
                status: .notApplicable,
                detail: readiness.summary
            )
        }
    }

    private func recommendation(
        approval: OperatorApprovalSummary,
        readiness: OperatorRolloutReadinessSummary,
        blockingReasons: [String]
    ) -> RolloutPreflightRecommendation {
        guard blockingReasons.isEmpty else { return .blocked }

        switch readiness.state {
        case .stagedEligible:
            return .staged
        case .immediateReady where approval.directExecutionCompatible:
            return .immediate
        case .notReady, .blocked:
            return .blocked
        case .staticBaseline:
            return .notApplicable
        case .immediateReady:
            return .staged
        }
    }
}
