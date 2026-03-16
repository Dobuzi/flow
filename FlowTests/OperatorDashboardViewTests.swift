import Testing
@testable import Flow

struct OperatorDashboardViewTests {
    @Test
    func buildsLiveCapableCardWithCandidateReadinessAndRefreshHealth() throws {
        let summary = OperatorDashboardSummary(
            catalogVersion: "2026.03",
            sources: [
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
                        lastRefreshAt: "2026-03-15T08:00:00Z",
                        rollbackAvailable: true,
                        operatorActivationStatus: .activeRollbackReady,
                        readiness: .ready,
                        syncState: .ready,
                        metrics: OperatorSourceMetrics(
                            activation: .init(
                                requestedCount: 1,
                                succeededCount: 1,
                                blockedCount: 0,
                                failedCount: 0,
                                noOpCount: 0,
                                rollbackRequestedCount: 1,
                                latestEventAt: "2026-03-15T08:05:00Z"
                            ),
                            refresh: .init(
                                attemptCount: 1,
                                succeededCount: 1,
                                failedCount: 0,
                                latestRefreshAt: "2026-03-15T08:00:00Z",
                                latestRefreshLatencySeconds: 90
                            )
                        )
                    ),
                    healthSummary: OperatorSourceHealthSummary(
                        state: .healthy,
                        operationalStatus: .rollbackReady,
                        reasons: [.rollbackReady, .active],
                        latestObservedAt: "2026-03-15T08:05:00Z"
                    ),
                    approvalSummary: OperatorApprovalSummary(
                        approvalState: .approved,
                        decisionSummary: "Rollback-prepared rollout compatible",
                        rolloutMode: .rollbackPrepared,
                        directExecutionCompatible: true
                    ),
                    rolloutReadinessSummary: OperatorRolloutReadinessSummary(
                        state: .stagedEligible,
                        summary: "Rollback-prepared rollout available",
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
        #expect(card.statusSummary == "Rollback ready")
        #expect(card.reasonSummary == "Rollback ready • Candidate ready")
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Active Snapshot", value: "seoul-2026.03")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Last Known Good", value: "seoul-2026.02")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Latest Candidate", value: "seoul-2026.04")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Candidate Compatibility", value: "Compatible")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Candidate Ready", value: "Ready")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Approval", value: "Approved")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Approval Detail", value: "Rollback-prepared rollout compatible")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Rollout Mode", value: "Rollback Prepared")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Rollout Readiness", value: "Staged Eligible")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Last Refresh", value: "Success")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Rollback Available", value: "Yes")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Rollout Reason", value: "Rollback-prepared rollout available")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Preflight", value: "Staged")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Preflight Notes", value: "Candidate is compatible")))
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
        #expect(card.rows == [
            OperatorDashboardCardRow(label: "Refresh", value: "Not supported"),
            OperatorDashboardCardRow(label: "Activation", value: "Not applicable")
        ])
    }

    @Test
    func buildsBlockedAndRecoveryNeededHealthIndicators() throws {
        let blocked = OperatorDashboardPresentation.cardModel(
            from: OperatorSourceSummary(
                source: .koreaNational,
                displayName: "Korea National",
                isLiveCapable: true,
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
                    approvalState: .proposed,
                    decisionSummary: "Candidate proposed but blocked",
                    rolloutMode: .staged,
                    directExecutionCompatible: false
                ),
                rolloutReadinessSummary: OperatorRolloutReadinessSummary(
                    state: .blocked,
                    summary: "Candidate blocked",
                    blockedReason: "Candidate incompatible"
                ),
                rolloutPreflight: RolloutPreflightResult(
                    source: .koreaNational,
                    overallReady: false,
                    checklistItems: [
                        RolloutChecklistItem(
                            kind: .candidateCompatibility,
                            title: "Candidate compatibility",
                            status: .blocked,
                            detail: "Candidate is incompatible"
                        )
                    ],
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
                    approvalState: .awaitingApproval,
                    decisionSummary: "Recovered state should be reviewed",
                    rolloutMode: .staged,
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
                    checklistItems: [
                        RolloutChecklistItem(
                            kind: .bootstrapRecovery,
                            title: "Bootstrap recovery",
                            status: .blocked,
                            detail: "Recovered operator state should be reviewed"
                        )
                    ],
                    blockingReasons: ["Recovered operator state should be reviewed"],
                    warningReasons: [],
                    recommendation: .blocked
                )
            )
        )

        #expect(blocked.healthBadge == OperatorDashboardHealthBadgeModel(title: "Blocked", tone: .critical))
        #expect(blocked.statusSummary == "Candidate blocked")
        #expect(blocked.reasonSummary == "Candidate incompatible • Readiness blocked")
        #expect(blocked.rows.contains(OperatorDashboardCardRow(label: "Approval", value: "Proposed")))
        #expect(blocked.rows.contains(OperatorDashboardCardRow(label: "Rollout Readiness", value: "Blocked")))
        #expect(blocked.rows.contains(OperatorDashboardCardRow(label: "Rollout Reason", value: "Candidate incompatible")))
        #expect(blocked.rows.contains(OperatorDashboardCardRow(label: "Preflight", value: "Blocked")))
        #expect(blocked.rows.contains(OperatorDashboardCardRow(label: "Preflight Notes", value: "Candidate is incompatible")))

        #expect(recovery.healthBadge == OperatorDashboardHealthBadgeModel(title: "Recovery Needed", tone: .warning))
        #expect(recovery.statusSummary == "Recovered state needs review")
        #expect(recovery.reasonSummary == "Startup recovery degraded")
        #expect(recovery.rows.contains(OperatorDashboardCardRow(label: "Approval", value: "Awaiting Approval")))
        #expect(recovery.rows.contains(OperatorDashboardCardRow(label: "Rollout Reason", value: "Startup recovery degraded")))
        #expect(recovery.rows.contains(OperatorDashboardCardRow(label: "Preflight", value: "Blocked")))
        #expect(recovery.rows.contains(OperatorDashboardCardRow(label: "Preflight Notes", value: "Recovered operator state should be reviewed")))
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

    @Test
    func surfacesDegradedBootstrapBanner() throws {
        let banner = OperatorDashboardPresentation.bootstrapBanner(
            from: PersistentOperatorStateBootstrapStatus(
                activationState: .current,
                refreshState: .resetCorrupted,
                activationHistory: .recoveredPartial
            )
        )

        let resolved = try #require(banner)
        #expect(resolved.isDegraded)
        #expect(resolved.title == "Recovered With Degraded Operator State")
        #expect(resolved.detail.contains("Activation current"))
        #expect(resolved.detail.contains("Refresh reset corrupted"))
        #expect(resolved.detail.contains("History partial recovery"))
    }
}
