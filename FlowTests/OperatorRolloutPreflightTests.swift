import Testing
@testable import Flow

struct OperatorRolloutPreflightTests {
    private let evaluator = RolloutPreflightEvaluator()

    @Test
    func evaluatesApprovedHealthyImmediateSourceAsReady() throws {
        let result = evaluator.evaluate(
            makeLiveSourceSummary(
                source: .seoulCapitalSnapshot,
                proposal: makeProposalSummary(
                    source: .seoulCapitalSnapshot,
                    lifecycleState: .approved,
                    approvalState: .approved,
                    rolloutMode: .immediate
                ),
                approvalSummary: OperatorApprovalSummary(
                    proposalID: "proposal-seoul",
                    proposalLifecycleState: .approved,
                    approvalState: .approved,
                    decisionSummary: "Approved for immediate execution",
                    rolloutMode: .immediate,
                    directExecutionCompatible: true
                ),
                rolloutReadinessSummary: OperatorRolloutReadinessSummary(
                    state: .immediateReady,
                    summary: "Approved for immediate execution",
                    blockedReason: nil
                )
            )
        )

        #expect(result.source == .seoulCapitalSnapshot)
        #expect(result.overallReady)
        #expect(result.recommendation == .immediate)
        #expect(result.blockingReasons.isEmpty)
        #expect(result.warningReasons.contains("No rollback target is currently available"))
    }

    @Test
    func blocksWhenNoProposalExists() throws {
        let result = evaluator.evaluate(
            makeLiveSourceSummary(
                source: .koreaNational,
                proposal: nil,
                approvalSummary: nil,
                rolloutReadinessSummary: OperatorRolloutReadinessSummary(
                    state: .notReady,
                    summary: "No rollout proposal",
                    blockedReason: nil
                )
            )
        )

        let approvalItem = try #require(result.checklistItems.first(where: { $0.kind == .approvalCompatibility }))
        #expect(result.overallReady == false)
        #expect(result.recommendation == .blocked)
        #expect(approvalItem.status == .blocked)
        #expect(result.blockingReasons.contains("No rollout proposal submitted"))
    }

    @Test
    func blocksIncompatibleApprovedProposalAndKeepsReasonsAligned() throws {
        let result = evaluator.evaluate(
            makeLiveSourceSummary(
                source: .koreaNational,
                proposal: makeProposalSummary(
                    source: .koreaNational,
                    lifecycleState: .approved,
                    approvalState: .approved,
                    rolloutMode: .staged,
                    lastDecisionReason: "Approved after review"
                ),
                liveSummary: OperatorSourceLiveSummary(
                    activeSnapshotID: nil,
                    lastKnownGoodSnapshotID: nil,
                    latestCandidateSnapshotID: "national-2026.05",
                    latestCandidateCompatibility: .incompatible,
                    latestCandidateEligibleForActivation: false,
                    lastRefreshOutcome: .success,
                    lastRefreshAt: "2026-03-16T09:00:00Z",
                    rollbackAvailable: false,
                    operatorActivationStatus: .attentionRequired,
                    readiness: .blocked,
                    syncState: .ready,
                    metrics: .empty
                ),
                healthSummary: OperatorSourceHealthSummary(
                    state: .blocked,
                    operationalStatus: .blocked,
                    reasons: [.candidateIncompatible, .readinessBlocked],
                    latestObservedAt: "2026-03-16T09:00:00Z"
                ),
                approvalSummary: OperatorApprovalSummary(
                    proposalID: "proposal-national",
                    proposalLifecycleState: .approved,
                    approvalState: .approved,
                    decisionSummary: "Approved but blocked by rollout checks",
                    rolloutMode: .staged,
                    directExecutionCompatible: false
                ),
                rolloutReadinessSummary: OperatorRolloutReadinessSummary(
                    state: .blocked,
                    summary: "Candidate blocked",
                    blockedReason: "Candidate incompatible"
                )
            )
        )

        let compatibilityItem = try #require(result.checklistItems.first(where: { $0.kind == .candidateCompatibility }))
        let approvalItem = try #require(result.checklistItems.first(where: { $0.kind == .approvalCompatibility }))

        #expect(result.recommendation == .blocked)
        #expect(result.overallReady == false)
        #expect(compatibilityItem.status == .blocked)
        #expect(approvalItem.status == .passed)
        #expect(result.blockingReasons.contains("Candidate is incompatible"))
        #expect(result.blockingReasons.contains("Candidate is not eligible for activation"))
        #expect(result.blockingReasons.contains("Candidate incompatible"))
    }

    @Test
    func treatsStaticSourcesAsNotApplicable() throws {
        let result = evaluator.evaluate(
            OperatorSourceSummary(
                source: .bundledSample,
                displayName: "Bundled Sample",
                isLiveCapable: false,
                liveSummary: nil,
                healthSummary: OperatorSourceHealthSummary(
                    state: .static,
                    operationalStatus: .staticBaseline,
                    reasons: [.staticSource],
                    latestObservedAt: nil
                )
            )
        )

        #expect(result.source == .bundledSample)
        #expect(result.recommendation == .notApplicable)
        #expect(result.overallReady == false)
        #expect(result.blockingReasons.isEmpty)
        #expect(result.warningReasons.isEmpty)
    }

    @Test
    func keepsRecoveryDegradedPreflightAlignedWithApprovedProposal() throws {
        let result = evaluator.evaluate(
            makeLiveSourceSummary(
                source: .seoulCapitalSnapshot,
                proposal: makeProposalSummary(
                    source: .seoulCapitalSnapshot,
                    lifecycleState: .approved,
                    approvalState: .approved,
                    rolloutMode: .rollbackPrepared,
                    lastDecisionReason: "Approved for staged execution"
                ),
                healthSummary: OperatorSourceHealthSummary(
                    state: .recoveryNeeded,
                    operationalStatus: .recoveryNeeded,
                    reasons: [.bootstrapDegraded],
                    latestObservedAt: "2026-03-16T09:30:00Z"
                ),
                approvalSummary: OperatorApprovalSummary(
                    proposalID: "proposal-recovery",
                    proposalLifecycleState: .approved,
                    approvalState: .approved,
                    decisionSummary: "Approved but recovered state needs review",
                    rolloutMode: .rollbackPrepared,
                    directExecutionCompatible: false
                ),
                rolloutReadinessSummary: OperatorRolloutReadinessSummary(
                    state: .blocked,
                    summary: "Review recovered state before rollout",
                    blockedReason: "Startup recovery degraded"
                )
            )
        )

        let bootstrapItem = try #require(result.checklistItems.first(where: { $0.kind == .bootstrapRecovery }))
        let approvalItem = try #require(result.checklistItems.first(where: { $0.kind == .approvalCompatibility }))
        let readinessItem = try #require(result.checklistItems.first(where: { $0.kind == .rolloutReadiness }))

        #expect(result.overallReady == false)
        #expect(result.recommendation == .blocked)
        #expect(bootstrapItem.status == .blocked)
        #expect(approvalItem.status == .passed)
        #expect(readinessItem.status == .blocked)
        #expect(result.blockingReasons.contains("Recovered operator state should be reviewed"))
        #expect(result.blockingReasons.contains("Startup recovery degraded"))
    }

    private func makeLiveSourceSummary(
        source: FlowDatasetSource,
        proposal: OperatorProposalSummary?,
        liveSummary: OperatorSourceLiveSummary? = nil,
        healthSummary: OperatorSourceHealthSummary? = nil,
        approvalSummary: OperatorApprovalSummary?,
        rolloutReadinessSummary: OperatorRolloutReadinessSummary
    ) -> OperatorSourceSummary {
        OperatorSourceSummary(
            source: source,
            displayName: source == .seoulCapitalSnapshot ? "Seoul Capital Area" : "Korea National",
            isLiveCapable: true,
            proposalSummary: proposal,
            liveSummary: liveSummary ?? OperatorSourceLiveSummary(
                activeSnapshotID: "seoul-2026.03",
                lastKnownGoodSnapshotID: "seoul-2026.02",
                latestCandidateSnapshotID: "seoul-2026.04",
                latestCandidateCompatibility: .compatible,
                latestCandidateEligibleForActivation: true,
                lastRefreshOutcome: .success,
                lastRefreshAt: "2026-03-16T08:00:00Z",
                rollbackAvailable: false,
                operatorActivationStatus: .active,
                readiness: .ready,
                syncState: .ready,
                metrics: .empty
            ),
            healthSummary: healthSummary ?? OperatorSourceHealthSummary(
                state: .healthy,
                operationalStatus: .active,
                reasons: [.active],
                latestObservedAt: "2026-03-16T08:00:00Z"
            ),
            approvalSummary: approvalSummary,
            rolloutReadinessSummary: rolloutReadinessSummary
        )
    }

    private func makeProposalSummary(
        source: FlowDatasetSource,
        lifecycleState: RolloutProposalLifecycleState,
        approvalState: ActivationApprovalState,
        rolloutMode: StagedRolloutMode,
        lastDecisionReason: String? = nil
    ) -> OperatorProposalSummary {
        OperatorProposalSummary(
            proposal: RolloutProposal(
                id: "proposal-\(source.rawValue)",
                source: source,
                action: .promote,
                targetSnapshotID: "\(source.rawValue)-2026.04",
                targetDatasetVersion: "2026.04",
                rolloutMode: rolloutMode,
                lifecycleState: lifecycleState,
                approvalState: approvalState,
                stages: [],
                createdAt: "2026-03-16T07:55:00Z",
                updatedAt: "2026-03-16T08:00:00Z",
                createdBy: "operator-1",
                note: nil,
                executionReadinessSummary: "candidate_ready",
                lastDecisionAt: "2026-03-16T08:00:00Z",
                lastDecisionReason: lastDecisionReason
            )
        )
    }
}
