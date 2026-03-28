import Testing
@testable import Flow

struct OperatorDashboardViewTests {
    @Test
    func buildsAuditLinksForGlobalAndSourceScopedNavigation() throws {
        let summary = OperatorDashboardSummary(
            catalogVersion: "2026.03",
            sources: [
                OperatorSourceSummary(
                    source: .seoulCapitalSnapshot,
                    displayName: "Seoul Capital Area",
                    isLiveCapable: true,
                    liveSummary: nil,
                    healthSummary: OperatorSourceHealthSummary(
                        state: .healthy,
                        operationalStatus: .inactive,
                        reasons: [.inactive],
                        latestObservedAt: nil
                    )
                )
            ],
            bootstrapStatus: nil
        )

        let globalLinks = OperatorDashboardPresentation.auditLinks(from: summary)
        #expect(globalLinks.count == 2)
        #expect(globalLinks[0].browserState.sourceFilter == .all)
        #expect(globalLinks[0].browserState.categoryFilter == .all)
        #expect(globalLinks[1].browserState.categoryFilter == .proposal)

        let card = try #require(OperatorDashboardPresentation.cardModels(from: summary).first)
        let sourceLink = OperatorDashboardPresentation.sourceAuditLink(for: card)
        #expect(sourceLink.browserState.sourceFilter == OperatorHistorySourceFilter(source: .seoulCapitalSnapshot))
        #expect(sourceLink.browserState.categoryFilter == .all)
    }

    @Test
    func buildsLiveCapableCardWithProposalBackedReadiness() throws {
        let summary = OperatorDashboardSummary(
            catalogVersion: "2026.03",
            sources: [
                OperatorSourceSummary(
                    source: .seoulCapitalSnapshot,
                    displayName: "Seoul Capital Area",
                    isLiveCapable: true,
                    proposalSummary: makeProposalSummary(
                        id: "proposal-seoul",
                        source: .seoulCapitalSnapshot,
                        lifecycleState: .approved,
                        approvalState: .approved,
                        rolloutMode: .rollbackPrepared,
                        lastDecisionReason: "Approved for staged execution"
                    ),
                    proposalRollup: OperatorProposalRollup(
                        source: .seoulCapitalSnapshot,
                        latestProposalID: "proposal-seoul",
                        targetSnapshotID: "seoulCapitalSnapshot-candidate",
                        targetDatasetVersion: "2026.04",
                        lifecycleState: .approved,
                        approvalState: .approved,
                        lifecycleSummary: "Approved -> Staged Eligible",
                        latestTimestamp: "2026-03-15T08:00:00Z",
                        isTerminal: false,
                        requiresAttention: false,
                        healthState: .approvedReady,
                        rollbackPrepared: true
                    ),
                    liveSummary: OperatorSourceLiveSummary(
                        activeSnapshotID: "seoul-2026.03",
                        lastKnownGoodSnapshotID: "seoul-2026.02",
                        latestCandidateSnapshotID: "seoul-2026.04",
                        latestCandidateCompatibility: .compatible,
                        latestCandidateEligibleForActivation: true,
                        lastRefreshOutcome: .success,
                        lastRefreshAt: "2026-03-15T08:00:00Z",
                        rollbackAvailable: true,
                        operatorActivationStatus: .activeRollbackReady,
                        readiness: .ready,
                        syncState: .ready,
                        metrics: .empty
                    ),
                    healthSummary: OperatorSourceHealthSummary(
                        state: .healthy,
                        operationalStatus: .rollbackReady,
                        reasons: [.rollbackReady, .active],
                        latestObservedAt: "2026-03-15T08:05:00Z"
                    ),
                    approvalSummary: OperatorApprovalSummary(
                        proposalID: "proposal-seoul",
                        proposalLifecycleState: .approved,
                        approvalState: .approved,
                        decisionSummary: "Approved for staged execution",
                        rolloutMode: .rollbackPrepared,
                        directExecutionCompatible: true
                    ),
                    rolloutReadinessSummary: OperatorRolloutReadinessSummary(
                        state: .stagedEligible,
                        summary: "Approved for staged execution",
                        blockedReason: nil
                    ),
                    rolloutPreflight: RolloutPreflightResult(
                        source: .seoulCapitalSnapshot,
                        overallReady: true,
                        checklistItems: [
                            RolloutChecklistItem(
                                kind: .candidateCompatibility,
                                title: "Candidate compatibility",
                                status: .passed,
                                detail: "Candidate is compatible"
                            )
                        ],
                        blockingReasons: [],
                        warningReasons: [],
                        recommendation: .staged
                    )
                )
            ],
            bootstrapStatus: nil
        )

        let card = try #require(OperatorDashboardPresentation.cardModels(from: summary).first)

        #expect(card.title == "Seoul Capital Area")
        #expect(card.capabilityLabel == "Live-capable")
        #expect(card.healthBadge == OperatorDashboardHealthBadgeModel(title: "Healthy", tone: .good))
        #expect(card.proposalHealthBadge == OperatorDashboardHealthBadgeModel(title: "Proposal Ready", tone: .good))
        #expect(card.statusSummary == "Rollback ready")
        #expect(card.reasonSummary == "Rollback ready")
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Proposal", value: "Approved")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Proposal Health", value: "Approved and ready")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Proposal Lifecycle", value: "Approved -> Staged Eligible")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Active Snapshot", value: "seoul-2026.03")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Approval", value: "Approved")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Approval Detail", value: "Approved for staged execution")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Rollout Readiness", value: "Staged Eligible")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Rollout Reason", value: "Approved for staged execution")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Preflight", value: "Staged")))
    }

    @Test
    func buildsStaticCardWithoutBogusOperatorState() {
        let card = OperatorDashboardPresentation.cardModel(
            from: OperatorSourceSummary(
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

        #expect(card.capabilityLabel == "Static")
        #expect(card.healthBadge == OperatorDashboardHealthBadgeModel(title: "Static", tone: .neutral))
        #expect(card.statusSummary == "Packaged baseline dataset")
        #expect(card.reasonSummary == nil)
    }

    @Test
    func buildsProposalBackedBlockedAndRecoveryIndicators() throws {
        let blocked = OperatorDashboardPresentation.cardModel(
            from: OperatorSourceSummary(
                source: .koreaNational,
                displayName: "Korea National",
                isLiveCapable: true,
                proposalSummary: makeProposalSummary(
                    id: "proposal-national",
                    source: .koreaNational,
                    lifecycleState: .rejected,
                    approvalState: .rejected,
                    rolloutMode: .staged,
                    lastDecisionReason: "Candidate failed review"
                ),
                proposalRollup: OperatorProposalRollup(
                    source: .koreaNational,
                    latestProposalID: "proposal-national",
                    targetSnapshotID: "koreaNational-candidate",
                    targetDatasetVersion: "2026.04",
                    lifecycleState: .rejected,
                    approvalState: .rejected,
                    lifecycleSummary: "Rejected",
                        latestTimestamp: "2026-03-15T08:00:00Z",
                        isTerminal: true,
                        requiresAttention: true,
                        healthState: .rejected,
                        rollbackPrepared: false
                    ),
                liveSummary: OperatorSourceLiveSummary(
                    activeSnapshotID: nil,
                    lastKnownGoodSnapshotID: nil,
                    latestCandidateSnapshotID: "national-2026.05",
                    latestCandidateCompatibility: .incompatible,
                    latestCandidateEligibleForActivation: false,
                    lastRefreshOutcome: .failed,
                    lastRefreshAt: "2026-03-16T02:00:00Z",
                    rollbackAvailable: false,
                    operatorActivationStatus: .attentionRequired,
                    readiness: .blocked,
                    syncState: .degraded,
                    metrics: .empty
                ),
                healthSummary: OperatorSourceHealthSummary(
                    state: .blocked,
                    operationalStatus: .blocked,
                    reasons: [.candidateIncompatible, .readinessBlocked, .refreshFailed],
                    latestObservedAt: "2026-03-16T02:00:00Z"
                ),
                approvalSummary: OperatorApprovalSummary(
                    proposalID: "proposal-national",
                    proposalLifecycleState: .rejected,
                    approvalState: .rejected,
                    decisionSummary: "Candidate failed review",
                    rolloutMode: .staged,
                    directExecutionCompatible: false
                ),
                rolloutReadinessSummary: OperatorRolloutReadinessSummary(
                    state: .blocked,
                    summary: "Proposal rejected",
                    blockedReason: "Candidate failed review"
                ),
                rolloutPreflight: RolloutPreflightResult(
                    source: .koreaNational,
                    overallReady: false,
                    checklistItems: [],
                    blockingReasons: ["Candidate is incompatible"],
                    warningReasons: [],
                    recommendation: .blocked
                )
            )
        )

        let recovery = OperatorDashboardPresentation.cardModel(
            from: OperatorSourceSummary(
                source: .seoulCapitalSnapshot,
                displayName: "Seoul Capital Area",
                isLiveCapable: true,
                proposalSummary: makeProposalSummary(
                    id: "proposal-recovery",
                    source: .seoulCapitalSnapshot,
                    lifecycleState: .approved,
                    approvalState: .approved,
                    rolloutMode: .rollbackPrepared,
                    lastDecisionReason: "Approved for staged execution"
                ),
                proposalRollup: OperatorProposalRollup(
                    source: .seoulCapitalSnapshot,
                    latestProposalID: "proposal-recovery",
                    targetSnapshotID: "seoulCapitalSnapshot-candidate",
                    targetDatasetVersion: "2026.04",
                    lifecycleState: .approved,
                    approvalState: .approved,
                    lifecycleSummary: "Approved -> Blocked",
                        latestTimestamp: "2026-03-15T08:00:00Z",
                        isTerminal: false,
                        requiresAttention: true,
                        healthState: .approvedBlocked,
                        rollbackPrepared: true
                    ),
                liveSummary: OperatorSourceLiveSummary(
                    activeSnapshotID: "seoul-2026.04",
                    lastKnownGoodSnapshotID: "seoul-2026.03",
                    latestCandidateSnapshotID: "seoul-2026.05",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    lastRefreshOutcome: .success,
                    lastRefreshAt: "2026-03-16T03:00:00Z",
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
                    latestObservedAt: "2026-03-16T03:00:00Z"
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
                ),
                rolloutPreflight: RolloutPreflightResult(
                    source: .seoulCapitalSnapshot,
                    overallReady: false,
                    checklistItems: [],
                    blockingReasons: ["Recovered operator state should be reviewed"],
                    warningReasons: [],
                    recommendation: .blocked
                )
            )
        )

        #expect(blocked.rows.contains(OperatorDashboardCardRow(label: "Proposal", value: "Rejected")))
        #expect(blocked.proposalHealthBadge == OperatorDashboardHealthBadgeModel(title: "Proposal Rejected", tone: .critical))
        #expect(blocked.rows.contains(OperatorDashboardCardRow(label: "Proposal Health", value: "Rejected")))
        #expect(blocked.rows.contains(OperatorDashboardCardRow(label: "Approval", value: "Rejected")))
        #expect(blocked.rows.contains(OperatorDashboardCardRow(label: "Rollout Reason", value: "Candidate failed review")))

        #expect(recovery.rows.contains(OperatorDashboardCardRow(label: "Proposal", value: "Approved")))
        #expect(recovery.proposalHealthBadge == OperatorDashboardHealthBadgeModel(title: "Proposal Blocked", tone: .warning))
        #expect(recovery.rows.contains(OperatorDashboardCardRow(label: "Proposal Health", value: "Approved but blocked")))
        #expect(recovery.rows.contains(OperatorDashboardCardRow(label: "Approval", value: "Approved")))
        #expect(recovery.rows.contains(OperatorDashboardCardRow(label: "Rollout Reason", value: "Startup recovery degraded")))
    }

    @Test
    func preservesDeterministicSourceOrderingAcrossCards() {
        let summary = OperatorDashboardSummary(
            catalogVersion: "2026.03",
            sources: [
                OperatorSourceSummary(source: .bundledSample, displayName: "Bundled Sample", isLiveCapable: false, liveSummary: nil, healthSummary: OperatorSourceHealthSummary(state: .static, operationalStatus: .staticBaseline, reasons: [.staticSource], latestObservedAt: nil)),
                OperatorSourceSummary(source: .seoulCapitalSnapshot, displayName: "Seoul Capital Area", isLiveCapable: true, liveSummary: nil, healthSummary: OperatorSourceHealthSummary(state: .healthy, operationalStatus: .inactive, reasons: [.inactive], latestObservedAt: nil)),
                OperatorSourceSummary(source: .koreaNational, displayName: "Korea National", isLiveCapable: true, liveSummary: nil, healthSummary: OperatorSourceHealthSummary(state: .healthy, operationalStatus: .inactive, reasons: [.inactive], latestObservedAt: nil))
            ],
            bootstrapStatus: nil
        )

        let cards = OperatorDashboardPresentation.cardModels(from: summary)

        #expect(cards.map(\.source) == [.bundledSample, .seoulCapitalSnapshot, .koreaNational])
    }

    private func makeProposalSummary(
        id: String,
        source: FlowDatasetSource,
        lifecycleState: RolloutProposalLifecycleState,
        approvalState: ActivationApprovalState,
        rolloutMode: StagedRolloutMode,
        lastDecisionReason: String?
    ) -> OperatorProposalSummary {
        OperatorProposalSummary(
            proposal: RolloutProposal(
                id: id,
                source: source,
                action: .promote,
                targetSnapshotID: "\(source.rawValue)-candidate",
                targetDatasetVersion: "2026.04",
                rolloutMode: rolloutMode,
                lifecycleState: lifecycleState,
                approvalState: approvalState,
                stages: [],
                createdAt: "2026-03-15T07:55:00Z",
                updatedAt: "2026-03-15T08:00:00Z",
                createdBy: "operator-1",
                note: nil,
                executionReadinessSummary: "candidate_ready",
                lastDecisionAt: "2026-03-15T08:00:00Z",
                lastDecisionReason: lastDecisionReason
            )
        )
    }
}
