import Testing
@testable import Flow

struct OperatorApprovalReadinessTests {
    private let resolver = OperatorApprovalReadinessResolver()

    @Test
    func resolvesDirectExecutionCompatibleImmediateReadiness() throws {
        let liveSummary = OperatorSourceLiveSummary(
            activeSnapshotID: nil,
            lastKnownGoodSnapshotID: nil,
            latestCandidateSnapshotID: "seoul-2026.04",
            latestCandidateCompatibility: .compatible,
            latestCandidateEligibleForActivation: true,
            lastRefreshOutcome: .success,
            lastRefreshAt: "2026-03-16T04:00:00Z",
            rollbackAvailable: false,
            operatorActivationStatus: .inactiveCandidateReady,
            readiness: .ready,
            syncState: .ready,
            metrics: .empty
        )
        let healthSummary = OperatorSourceHealthSummary(
            state: .healthy,
            operationalStatus: .candidateReady,
            reasons: [.candidateReady],
            latestObservedAt: "2026-03-16T04:00:00Z"
        )

        let approval = try #require(resolver.approvalSummary(
            isLiveCapable: true,
            liveSummary: liveSummary,
            healthSummary: healthSummary
        ))
        let readiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: liveSummary,
            healthSummary: healthSummary
        )

        #expect(approval.approvalState == .approved)
        #expect(approval.rolloutMode == .immediate)
        #expect(approval.directExecutionCompatible)
        #expect(approval.decisionSummary == "Direct execution compatible")
        #expect(readiness.state == .immediateReady)
        #expect(readiness.summary == "Ready for immediate execution")
    }

    @Test
    func resolvesBlockedAndRecoveryReviewStatesTruthfully() throws {
        let blockedLiveSummary = OperatorSourceLiveSummary(
            activeSnapshotID: "national-2026.03",
            lastKnownGoodSnapshotID: "national-2026.02",
            latestCandidateSnapshotID: "national-2026.04",
            latestCandidateCompatibility: .incompatible,
            latestCandidateEligibleForActivation: false,
            lastRefreshOutcome: .failed,
            lastRefreshAt: "2026-03-16T05:00:00Z",
            rollbackAvailable: true,
            operatorActivationStatus: .attentionRequired,
            readiness: .blocked,
            syncState: .degraded,
            metrics: .empty
        )
        let blockedHealthSummary = OperatorSourceHealthSummary(
            state: .blocked,
            operationalStatus: .blocked,
            reasons: [.candidateIncompatible, .readinessBlocked],
            latestObservedAt: "2026-03-16T05:00:00Z"
        )

        let blockedApproval = try #require(resolver.approvalSummary(
            isLiveCapable: true,
            liveSummary: blockedLiveSummary,
            healthSummary: blockedHealthSummary
        ))
        let blockedReadiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: blockedLiveSummary,
            healthSummary: blockedHealthSummary
        )

        #expect(blockedApproval.approvalState == .proposed)
        #expect(blockedApproval.rolloutMode == .staged)
        #expect(blockedApproval.directExecutionCompatible == false)
        #expect(blockedReadiness.state == .blocked)
        #expect(blockedReadiness.blockedReason == "Candidate incompatible")

        let recoveryHealthSummary = OperatorSourceHealthSummary(
            state: .recoveryNeeded,
            operationalStatus: .recoveryNeeded,
            reasons: [.bootstrapDegraded],
            latestObservedAt: "2026-03-16T06:00:00Z"
        )
        let recoveryApproval = try #require(resolver.approvalSummary(
            isLiveCapable: true,
            liveSummary: blockedLiveSummary,
            healthSummary: recoveryHealthSummary
        ))
        let recoveryReadiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: blockedLiveSummary,
            healthSummary: recoveryHealthSummary
        )

        #expect(recoveryApproval.approvalState == .awaitingApproval)
        #expect(recoveryApproval.decisionSummary == "Recovered state should be reviewed")
        #expect(recoveryReadiness.state == .blocked)
        #expect(recoveryReadiness.blockedReason == "Startup recovery degraded")
    }

    @Test
    func keepsStaticSourcesSafe() throws {
        let approval = resolver.approvalSummary(
            isLiveCapable: false,
            liveSummary: nil,
            healthSummary: OperatorSourceHealthSummary(
                state: .static,
                operationalStatus: .staticBaseline,
                reasons: [.staticSource],
                latestObservedAt: nil
            )
        )
        let readiness = resolver.rolloutReadinessSummary(
            isLiveCapable: false,
            liveSummary: nil,
            healthSummary: OperatorSourceHealthSummary(
                state: .static,
                operationalStatus: .staticBaseline,
                reasons: [.staticSource],
                latestObservedAt: nil
            )
        )

        #expect(approval == nil)
        #expect(readiness.state == .staticBaseline)
        #expect(readiness.summary == "Static baseline dataset")
    }

    @Test
    func resolvesSyncFailureAndMissingCandidateTruthfully() throws {
        let syncFailedLiveSummary = OperatorSourceLiveSummary(
            activeSnapshotID: "national-2026.03",
            lastKnownGoodSnapshotID: "national-2026.02",
            latestCandidateSnapshotID: "national-2026.04",
            latestCandidateCompatibility: .compatible,
            latestCandidateEligibleForActivation: true,
            lastRefreshOutcome: .failed,
            lastRefreshAt: "2026-03-16T07:00:00Z",
            rollbackAvailable: true,
            operatorActivationStatus: .attentionRequired,
            readiness: .ready,
            syncState: .failed,
            metrics: .empty
        )
        let syncFailedHealthSummary = OperatorSourceHealthSummary(
            state: .unavailable,
            operationalStatus: .unavailable,
            reasons: [.syncFailed],
            latestObservedAt: "2026-03-16T07:00:00Z"
        )

        let syncFailedApproval = try #require(resolver.approvalSummary(
            isLiveCapable: true,
            liveSummary: syncFailedLiveSummary,
            healthSummary: syncFailedHealthSummary
        ))
        let syncFailedReadiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: syncFailedLiveSummary,
            healthSummary: syncFailedHealthSummary
        )

        #expect(syncFailedApproval.approvalState == .proposed)
        #expect(syncFailedApproval.directExecutionCompatible == false)
        #expect(syncFailedApproval.rolloutMode == .staged)
        #expect(syncFailedReadiness.state == .blocked)
        #expect(syncFailedReadiness.blockedReason == "Sync failed")

        let noCandidateLiveSummary = OperatorSourceLiveSummary(
            activeSnapshotID: "seoul-2026.03",
            lastKnownGoodSnapshotID: "seoul-2026.02",
            latestCandidateSnapshotID: nil,
            latestCandidateCompatibility: nil,
            latestCandidateEligibleForActivation: nil,
            lastRefreshOutcome: .success,
            lastRefreshAt: "2026-03-16T07:10:00Z",
            rollbackAvailable: true,
            operatorActivationStatus: .activeRollbackReady,
            readiness: .ready,
            syncState: .ready,
            metrics: .empty
        )
        let noCandidateHealthSummary = OperatorSourceHealthSummary(
            state: .healthy,
            operationalStatus: .rollbackReady,
            reasons: [.active, .rollbackReady],
            latestObservedAt: "2026-03-16T07:10:00Z"
        )

        let noCandidateApproval = try #require(resolver.approvalSummary(
            isLiveCapable: true,
            liveSummary: noCandidateLiveSummary,
            healthSummary: noCandidateHealthSummary
        ))
        let noCandidateReadiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: noCandidateLiveSummary,
            healthSummary: noCandidateHealthSummary
        )

        #expect(noCandidateApproval.approvalState == .awaitingApproval)
        #expect(noCandidateApproval.directExecutionCompatible == false)
        #expect(noCandidateReadiness.state == .notReady)
        #expect(noCandidateReadiness.summary == "No candidate snapshot available")
    }
}
