import Foundation

enum OperatorSourceHealthState: String, Hashable {
    case `static`
    case healthy
    case degraded
    case blocked
    case unavailable
    case recoveryNeeded
}

enum OperatorOperationalStatus: String, Hashable {
    case staticBaseline
    case active
    case candidateReady
    case rollbackReady
    case inactive
    case blocked
    case degraded
    case unavailable
    case recoveryNeeded
}

enum OperatorSourceHealthReason: String, Hashable {
    case staticSource
    case bootstrapDegraded
    case syncFailed
    case syncDegraded
    case refreshFailed
    case candidateIncompatible
    case candidateIneligible
    case readinessBlocked
    case pendingValidation
    case rollbackReady
    case candidateReady
    case active
    case inactive
}

struct OperatorSourceHealthSummary: Hashable {
    let state: OperatorSourceHealthState
    let operationalStatus: OperatorOperationalStatus
    let reasons: [OperatorSourceHealthReason]
    let latestObservedAt: String?
}

struct OperatorHealthAggregator {
    let bootstrapStatus: PersistentOperatorStateBootstrapStatus?

    func summary(
        for source: FlowDatasetSource,
        isLiveCapable: Bool,
        liveSummary: OperatorSourceLiveSummary?
    ) -> OperatorSourceHealthSummary {
        guard isLiveCapable, let liveSummary else {
            return OperatorSourceHealthSummary(
                state: .static,
                operationalStatus: .staticBaseline,
                reasons: [.staticSource],
                latestObservedAt: nil
            )
        }

        let latestObservedAt = liveSummary.metrics.activation.latestEventAt
            ?? liveSummary.metrics.refresh.latestRefreshAt
            ?? liveSummary.lastRefreshAt

        if bootstrapStatus?.isDegraded == true {
            return OperatorSourceHealthSummary(
                state: .recoveryNeeded,
                operationalStatus: .recoveryNeeded,
                reasons: [.bootstrapDegraded],
                latestObservedAt: latestObservedAt
            )
        }

        if liveSummary.syncState == .failed {
            return OperatorSourceHealthSummary(
                state: .unavailable,
                operationalStatus: .unavailable,
                reasons: [.syncFailed],
                latestObservedAt: latestObservedAt
            )
        }

        var reasons: [OperatorSourceHealthReason] = []
        if liveSummary.syncState == .degraded {
            reasons.append(.syncDegraded)
        }
        if liveSummary.lastRefreshOutcome == .failed || liveSummary.metrics.refresh.failedCount > 0 {
            reasons.append(.refreshFailed)
        }
        if liveSummary.latestCandidateCompatibility == .incompatible {
            reasons.append(.candidateIncompatible)
        }
        if liveSummary.latestCandidateEligibleForActivation == false {
            reasons.append(.candidateIneligible)
        }
        if liveSummary.readiness == .blocked {
            reasons.append(.readinessBlocked)
        }
        if liveSummary.readiness == .pendingValidation {
            reasons.append(.pendingValidation)
        }
        if liveSummary.rollbackAvailable {
            reasons.append(.rollbackReady)
        }
        if liveSummary.latestCandidateEligibleForActivation == true {
            reasons.append(.candidateReady)
        }
        if liveSummary.operatorActivationStatus == .active || liveSummary.operatorActivationStatus == .activeRollbackReady {
            reasons.append(.active)
        }
        if liveSummary.operatorActivationStatus == .inactive || liveSummary.operatorActivationStatus == .noHistory {
            reasons.append(.inactive)
        }

        if reasons.contains(.candidateIncompatible)
            || reasons.contains(.candidateIneligible)
            || reasons.contains(.readinessBlocked) {
            return OperatorSourceHealthSummary(
                state: .blocked,
                operationalStatus: .blocked,
                reasons: reasons,
                latestObservedAt: latestObservedAt
            )
        }

        if reasons.contains(.refreshFailed)
            || reasons.contains(.syncDegraded)
            || reasons.contains(.pendingValidation)
            || liveSummary.operatorActivationStatus == .attentionRequired {
            return OperatorSourceHealthSummary(
                state: .degraded,
                operationalStatus: .degraded,
                reasons: reasons,
                latestObservedAt: latestObservedAt
            )
        }

        if liveSummary.rollbackAvailable {
            return OperatorSourceHealthSummary(
                state: .healthy,
                operationalStatus: .rollbackReady,
                reasons: reasons,
                latestObservedAt: latestObservedAt
            )
        }

        if liveSummary.latestCandidateEligibleForActivation == true,
           liveSummary.activeSnapshotID == nil {
            return OperatorSourceHealthSummary(
                state: .healthy,
                operationalStatus: .candidateReady,
                reasons: reasons,
                latestObservedAt: latestObservedAt
            )
        }

        if liveSummary.operatorActivationStatus == .active {
            return OperatorSourceHealthSummary(
                state: .healthy,
                operationalStatus: .active,
                reasons: reasons,
                latestObservedAt: latestObservedAt
            )
        }

        return OperatorSourceHealthSummary(
            state: .healthy,
            operationalStatus: .inactive,
            reasons: reasons,
            latestObservedAt: latestObservedAt
        )
    }
}
