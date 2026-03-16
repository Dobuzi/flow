import Testing
@testable import Flow

struct OperatorRolloutPreflightTests {
    private let evaluator = RolloutPreflightEvaluator()

    @Test
    func evaluatesHealthyImmediateSourceAsReady() throws {
        let result = evaluator.evaluate(
            OperatorSourceSummary(
                source: .seoulCapitalSnapshot,
                displayName: "Seoul Capital Area",
                isLiveCapable: true,
                liveSummary: OperatorSourceLiveSummary(
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
                healthSummary: OperatorSourceHealthSummary(
                    state: .healthy,
                    operationalStatus: .active,
                    reasons: [.active],
                    latestObservedAt: "2026-03-16T08:00:00Z"
                ),
                approvalSummary: OperatorApprovalSummary(
                    approvalState: .approved,
                    decisionSummary: "Direct execution compatible",
                    rolloutMode: .immediate,
                    directExecutionCompatible: true
                ),
                rolloutReadinessSummary: OperatorRolloutReadinessSummary(
                    state: .immediateReady,
                    summary: "Ready for immediate execution",
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
    func warnsWhenRefreshHealthIsDegradedButNotBlocked() throws {
        let result = evaluator.evaluate(
            OperatorSourceSummary(
                source: .koreaNational,
                displayName: "Korea National",
                isLiveCapable: true,
                liveSummary: OperatorSourceLiveSummary(
                    activeSnapshotID: "national-2026.03",
                    lastKnownGoodSnapshotID: "national-2026.02",
                    latestCandidateSnapshotID: "national-2026.04",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    lastRefreshOutcome: .failed,
                    lastRefreshAt: "2026-03-16T08:00:00Z",
                    rollbackAvailable: false,
                    operatorActivationStatus: .attentionRequired,
                    readiness: .pendingValidation,
                    syncState: .degraded,
                    metrics: .empty
                ),
                healthSummary: OperatorSourceHealthSummary(
                    state: .degraded,
                    operationalStatus: .degraded,
                    reasons: [.refreshFailed],
                    latestObservedAt: "2026-03-16T08:00:00Z"
                ),
                approvalSummary: OperatorApprovalSummary(
                    approvalState: .awaitingApproval,
                    decisionSummary: "Awaiting candidate readiness review",
                    rolloutMode: .staged,
                    directExecutionCompatible: false
                ),
                rolloutReadinessSummary: OperatorRolloutReadinessSummary(
                    state: .notReady,
                    summary: "Pending validation",
                    blockedReason: nil
                )
            )
        )

        let refreshItem = try #require(result.checklistItems.first(where: { $0.kind == .refreshHealth }))
        let readinessItem = try #require(result.checklistItems.first(where: { $0.kind == .rolloutReadiness }))

        #expect(result.overallReady == false)
        #expect(result.recommendation == .blocked)
        #expect(refreshItem.status == .warning)
        #expect(readinessItem.status == .warning)
        #expect(result.warningReasons.contains("Refresh health is degraded"))
        #expect(result.warningReasons.contains("Pending validation"))
        #expect(result.blockingReasons.isEmpty)
    }

    @Test
    func blocksIncompatibleOrIneligibleCandidates() throws {
        let result = evaluator.evaluate(
            OperatorSourceSummary(
                source: .koreaNational,
                displayName: "Korea National",
                isLiveCapable: true,
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
                    approvalState: .proposed,
                    decisionSummary: "Candidate proposed but blocked",
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
        let eligibilityItem = try #require(result.checklistItems.first(where: { $0.kind == .candidateEligibility }))

        #expect(result.recommendation == .blocked)
        #expect(result.overallReady == false)
        #expect(compatibilityItem.status == .blocked)
        #expect(eligibilityItem.status == .blocked)
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
        #expect(result.checklistItems == [
            RolloutChecklistItem(
                kind: .liveRolloutSupport,
                title: "Live rollout support",
                status: .notApplicable,
                detail: "Static baseline dataset"
            )
        ])
    }

    @Test
    func keepsRecoveryDegradedPreflightAlignedWithApprovalAndReadiness() throws {
        let result = evaluator.evaluate(
            OperatorSourceSummary(
                source: .seoulCapitalSnapshot,
                displayName: "Seoul Capital Area",
                isLiveCapable: true,
                liveSummary: OperatorSourceLiveSummary(
                    activeSnapshotID: "seoul-2026.03",
                    lastKnownGoodSnapshotID: "seoul-2026.02",
                    latestCandidateSnapshotID: "seoul-2026.04",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    lastRefreshOutcome: .success,
                    lastRefreshAt: "2026-03-16T09:30:00Z",
                    rollbackAvailable: true,
                    operatorActivationStatus: .activeRollbackReady,
                    readiness: .ready,
                    syncState: .ready,
                    metrics: .empty
                ),
                healthSummary: OperatorSourceHealthSummary(
                    state: .recoveryNeeded,
                    operationalStatus: .recoveryNeeded,
                    reasons: [.bootstrapDegraded],
                    latestObservedAt: "2026-03-16T09:30:00Z"
                ),
                approvalSummary: OperatorApprovalSummary(
                    approvalState: .awaitingApproval,
                    decisionSummary: "Recovered state should be reviewed",
                    rolloutMode: .staged,
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
        #expect(approvalItem.status == .warning)
        #expect(readinessItem.status == .blocked)
        #expect(result.blockingReasons.contains("Recovered operator state should be reviewed"))
        #expect(result.blockingReasons.contains("Startup recovery degraded"))
        #expect(result.warningReasons.contains("Recovered state should be reviewed"))
    }
}
