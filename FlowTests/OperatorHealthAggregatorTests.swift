import Testing
@testable import Flow

struct OperatorHealthAggregatorTests {
    @Test
    func aggregatesHealthyLiveSourceWithRollbackReadiness() {
        let aggregator = OperatorHealthAggregator(bootstrapStatus: nil)

        let summary = aggregator.summary(
            for: .seoulCapitalSnapshot,
            isLiveCapable: true,
            liveSummary: makeLiveSummary(
                activeSnapshotID: "seoul-2026.04",
                latestCandidateEligibleForActivation: true,
                lastRefreshOutcome: .success,
                rollbackAvailable: true,
                operatorActivationStatus: .activeRollbackReady,
                readiness: .ready,
                syncState: .ready
            )
        )

        #expect(summary.state == .healthy)
        #expect(summary.operationalStatus == .rollbackReady)
        #expect(summary.reasons.contains(.rollbackReady))
        #expect(summary.reasons.contains(.active))
        #expect(summary.latestObservedAt == "2026-03-15T10:02:00Z")
    }

    @Test
    func aggregatesRecoveryNeededWhenBootstrapWasDegraded() {
        let aggregator = OperatorHealthAggregator(
            bootstrapStatus: PersistentOperatorStateBootstrapStatus(
                activationState: .current,
                refreshState: .resetCorrupted,
                activationHistory: .current
            )
        )

        let summary = aggregator.summary(
            for: .koreaNational,
            isLiveCapable: true,
            liveSummary: makeLiveSummary(
                activeSnapshotID: nil,
                latestCandidateEligibleForActivation: nil,
                lastRefreshOutcome: .success,
                rollbackAvailable: false,
                operatorActivationStatus: .noHistory,
                readiness: .ready,
                syncState: .ready
            )
        )

        #expect(summary.state == .recoveryNeeded)
        #expect(summary.operationalStatus == .recoveryNeeded)
        #expect(summary.reasons == [.bootstrapDegraded])
    }

    @Test
    func aggregatesBlockedWhenCandidateIsIncompatibleOrIneligible() {
        let aggregator = OperatorHealthAggregator(bootstrapStatus: nil)

        let summary = aggregator.summary(
            for: .seoulCapitalSnapshot,
            isLiveCapable: true,
            liveSummary: makeLiveSummary(
                activeSnapshotID: "seoul-2026.03",
                latestCandidateCompatibility: .incompatible,
                latestCandidateEligibleForActivation: false,
                lastRefreshOutcome: .success,
                rollbackAvailable: false,
                operatorActivationStatus: .active,
                readiness: .blocked,
                syncState: .ready
            )
        )

        #expect(summary.state == .blocked)
        #expect(summary.operationalStatus == .blocked)
        #expect(summary.reasons.contains(.candidateIncompatible))
        #expect(summary.reasons.contains(.candidateIneligible))
        #expect(summary.reasons.contains(.readinessBlocked))
    }

    @Test
    func aggregatesUnavailableAndDegradedDeterministically() {
        let aggregator = OperatorHealthAggregator(bootstrapStatus: nil)

        let unavailable = aggregator.summary(
            for: .koreaNational,
            isLiveCapable: true,
            liveSummary: makeLiveSummary(
                activeSnapshotID: nil,
                lastRefreshOutcome: .failed,
                rollbackAvailable: false,
                operatorActivationStatus: .attentionRequired,
                readiness: .blocked,
                syncState: .failed
            )
        )
        let degraded = aggregator.summary(
            for: .koreaNational,
            isLiveCapable: true,
            liveSummary: makeLiveSummary(
                activeSnapshotID: nil,
                latestCandidateEligibleForActivation: nil,
                lastRefreshOutcome: .failed,
                rollbackAvailable: false,
                operatorActivationStatus: .attentionRequired,
                readiness: .pendingValidation,
                syncState: .degraded
            )
        )

        #expect(unavailable.state == .unavailable)
        #expect(unavailable.operationalStatus == .unavailable)
        #expect(unavailable.reasons == [.syncFailed])

        #expect(degraded.state == .degraded)
        #expect(degraded.operationalStatus == .degraded)
        #expect(degraded.reasons.contains(.refreshFailed))
        #expect(degraded.reasons.contains(.syncDegraded))
        #expect(degraded.reasons.contains(.pendingValidation))
    }

    @Test
    func keepsStaticSourcesTruthful() {
        let aggregator = OperatorHealthAggregator(bootstrapStatus: nil)

        let summary = aggregator.summary(
            for: .bundledSample,
            isLiveCapable: false,
            liveSummary: nil
        )

        #expect(summary.state == .static)
        #expect(summary.operationalStatus == .staticBaseline)
        #expect(summary.reasons == [.staticSource])
        #expect(summary.latestObservedAt == nil)
    }

    private func makeLiveSummary(
        activeSnapshotID: String?,
        latestCandidateCompatibility: IngestionCompatibilityClassification? = .compatible,
        latestCandidateEligibleForActivation: Bool? = true,
        lastRefreshOutcome: DatasetRefreshOutcome?,
        rollbackAvailable: Bool,
        operatorActivationStatus: DatasetOperatorActivationStatus,
        readiness: DatasetRefreshReadiness,
        syncState: DatasetSyncState
    ) -> OperatorSourceLiveSummary {
        OperatorSourceLiveSummary(
            activeSnapshotID: activeSnapshotID,
            lastKnownGoodSnapshotID: "lkg-2026.03",
            latestCandidateSnapshotID: "candidate-2026.04",
            latestCandidateCompatibility: latestCandidateCompatibility,
            latestCandidateEligibleForActivation: latestCandidateEligibleForActivation,
            lastRefreshOutcome: lastRefreshOutcome,
            lastRefreshAt: "2026-03-15T10:02:00Z",
            rollbackAvailable: rollbackAvailable,
            operatorActivationStatus: operatorActivationStatus,
            readiness: readiness,
            syncState: syncState,
            metrics: OperatorSourceMetrics(
                activation: .init(
                    requestedCount: 1,
                    succeededCount: 1,
                    blockedCount: 0,
                    failedCount: 0,
                    noOpCount: 0,
                    rollbackRequestedCount: rollbackAvailable ? 1 : 0,
                    latestEventAt: "2026-03-15T10:02:00Z"
                ),
                refresh: .init(
                    attemptCount: 1,
                    succeededCount: lastRefreshOutcome == .success ? 1 : 0,
                    failedCount: lastRefreshOutcome == .failed ? 1 : 0,
                    latestRefreshAt: "2026-03-15T10:01:00Z",
                    latestRefreshLatencySeconds: 60
                )
            )
        )
    }
}
