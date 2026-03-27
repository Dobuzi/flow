import Foundation
import Testing
@testable import Flow

struct OperatorApprovalReadinessTests {
    private let resolver = OperatorApprovalReadinessResolver()

    @Test
    func keepsLiveSourcesWithoutProposalNotReady() throws {
        let liveSummary = makeReadyLiveSummary()
        let healthSummary = makeHealthyHealthSummary()

        let approval = resolver.approvalSummary(
            isLiveCapable: true,
            liveSummary: liveSummary,
            healthSummary: healthSummary,
            proposalSummary: nil
        )
        let readiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: liveSummary,
            healthSummary: healthSummary,
            proposalSummary: nil
        )

        #expect(approval == nil)
        #expect(readiness.state == .notReady)
        #expect(readiness.summary == "No rollout proposal")
    }

    @Test
    func resolvesAwaitingApprovalForSubmittedProposal() throws {
        let proposal = makeProposalSummary(
            lifecycleState: .proposed,
            approvalState: .awaitingApproval,
            rolloutMode: .staged
        )

        let approval = try #require(resolver.approvalSummary(
            isLiveCapable: true,
            liveSummary: makeReadyLiveSummary(),
            healthSummary: makeHealthyHealthSummary(),
            proposalSummary: proposal
        ))
        let readiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: makeReadyLiveSummary(),
            healthSummary: makeHealthyHealthSummary(),
            proposalSummary: proposal
        )

        #expect(approval.approvalState == .awaitingApproval)
        #expect(approval.proposalLifecycleState == .proposed)
        #expect(approval.directExecutionCompatible == false)
        #expect(approval.decisionSummary == "Awaiting approval")
        #expect(readiness.state == .notReady)
        #expect(readiness.summary == "Awaiting approval")
    }

    @Test
    func resolvesApprovedProposalAsReadyOnlyWhenTechnicalChecksPass() throws {
        let proposal = makeProposalSummary(
            lifecycleState: .approved,
            approvalState: .approved,
            rolloutMode: .immediate
        )

        let approval = try #require(resolver.approvalSummary(
            isLiveCapable: true,
            liveSummary: makeReadyLiveSummary(),
            healthSummary: makeHealthyHealthSummary(),
            proposalSummary: proposal
        ))
        let readiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: makeReadyLiveSummary(),
            healthSummary: makeHealthyHealthSummary(),
            proposalSummary: proposal
        )

        #expect(approval.approvalState == .approved)
        #expect(approval.directExecutionCompatible == true)
        #expect(approval.decisionSummary == "Approved for immediate execution")
        #expect(readiness.state == .immediateReady)
        #expect(readiness.summary == "Approved for immediate execution")

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
            healthSummary: blockedHealthSummary,
            proposalSummary: proposal
        ))
        let blockedReadiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: blockedLiveSummary,
            healthSummary: blockedHealthSummary,
            proposalSummary: proposal
        )

        #expect(blockedApproval.approvalState == .approved)
        #expect(blockedApproval.directExecutionCompatible == false)
        #expect(blockedApproval.decisionSummary == "Approved but blocked by rollout checks")
        #expect(blockedReadiness.state == .blocked)
        #expect(blockedReadiness.blockedReason == "Candidate incompatible")
    }

    @Test
    func resolvesRejectedAndCancelledProposalsAsBlocked() throws {
        let liveSummary = makeReadyLiveSummary()
        let healthSummary = makeHealthyHealthSummary()
        let rejected = makeProposalSummary(
            lifecycleState: .rejected,
            approvalState: .rejected,
            rolloutMode: .staged,
            lastDecisionReason: "Candidate failed review"
        )
        let cancelled = makeProposalSummary(
            lifecycleState: .cancelled,
            approvalState: .cancelled,
            rolloutMode: .staged,
            lastDecisionReason: "Operator withdrew rollout"
        )

        let rejectedApproval = try #require(resolver.approvalSummary(
            isLiveCapable: true,
            liveSummary: liveSummary,
            healthSummary: healthSummary,
            proposalSummary: rejected
        ))
        let rejectedReadiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: liveSummary,
            healthSummary: healthSummary,
            proposalSummary: rejected
        )
        let cancelledApproval = try #require(resolver.approvalSummary(
            isLiveCapable: true,
            liveSummary: liveSummary,
            healthSummary: healthSummary,
            proposalSummary: cancelled
        ))
        let cancelledReadiness = resolver.rolloutReadinessSummary(
            isLiveCapable: true,
            liveSummary: liveSummary,
            healthSummary: healthSummary,
            proposalSummary: cancelled
        )

        #expect(rejectedApproval.approvalState == .rejected)
        #expect(rejectedApproval.decisionSummary == "Candidate failed review")
        #expect(rejectedReadiness.state == .blocked)
        #expect(rejectedReadiness.blockedReason == "Candidate failed review")

        #expect(cancelledApproval.approvalState == .cancelled)
        #expect(cancelledApproval.decisionSummary == "Operator withdrew rollout")
        #expect(cancelledReadiness.state == .blocked)
        #expect(cancelledReadiness.blockedReason == "Operator withdrew rollout")
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
            ),
            proposalSummary: nil
        )
        let readiness = resolver.rolloutReadinessSummary(
            isLiveCapable: false,
            liveSummary: nil,
            healthSummary: OperatorSourceHealthSummary(
                state: .static,
                operationalStatus: .staticBaseline,
                reasons: [.staticSource],
                latestObservedAt: nil
            ),
            proposalSummary: nil
        )

        #expect(approval == nil)
        #expect(readiness.state == .staticBaseline)
        #expect(readiness.summary == "Static baseline dataset")
    }

    private func makeReadyLiveSummary() -> OperatorSourceLiveSummary {
        OperatorSourceLiveSummary(
            activeSnapshotID: "seoul-2026.03",
            lastKnownGoodSnapshotID: "seoul-2026.02",
            latestCandidateSnapshotID: "seoul-2026.04",
            latestCandidateCompatibility: .compatible,
            latestCandidateEligibleForActivation: true,
            lastRefreshOutcome: .success,
            lastRefreshAt: "2026-03-16T04:00:00Z",
            rollbackAvailable: true,
            operatorActivationStatus: .activeRollbackReady,
            readiness: .ready,
            syncState: .ready,
            metrics: .empty
        )
    }

    private func makeHealthyHealthSummary() -> OperatorSourceHealthSummary {
        OperatorSourceHealthSummary(
            state: .healthy,
            operationalStatus: .rollbackReady,
            reasons: [.rollbackReady, .active],
            latestObservedAt: "2026-03-16T04:00:00Z"
        )
    }

    private func makeProposalSummary(
        lifecycleState: RolloutProposalLifecycleState,
        approvalState: ActivationApprovalState,
        rolloutMode: StagedRolloutMode,
        lastDecisionReason: String? = nil
    ) -> OperatorProposalSummary {
        OperatorProposalSummary(
            proposal: RolloutProposal(
                id: UUID().uuidString,
                source: .seoulCapitalSnapshot,
                action: .promote,
                targetSnapshotID: "seoul-2026.04",
                targetDatasetVersion: "2026.04",
                rolloutMode: rolloutMode,
                lifecycleState: lifecycleState,
                approvalState: approvalState,
                stages: [],
                createdAt: "2026-03-16T03:55:00Z",
                updatedAt: "2026-03-16T04:00:00Z",
                createdBy: "operator-1",
                note: nil,
                executionReadinessSummary: "candidate_ready",
                lastDecisionAt: "2026-03-16T04:00:00Z",
                lastDecisionReason: lastDecisionReason
            )
        )
    }
}
