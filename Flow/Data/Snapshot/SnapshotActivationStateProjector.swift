import Foundation

enum ProjectedActivationStatus: String, Hashable {
    case noHistory
    case inactive
    case inactiveCandidateReady
    case active
    case activeRollbackReady
    case attentionRequired
}

enum ProjectedActivationCommandOutcome: String, Hashable {
    case none
    case requested
    case succeeded
    case blocked
    case failed
}

struct ProjectedActivationState: Hashable {
    let source: FlowDatasetSource
    let status: ProjectedActivationStatus
    let activeSnapshotID: String?
    let lastKnownGoodSnapshotID: String?
    let latestCandidateSnapshotID: String?
    let latestCandidateDatasetVersion: String?
    let latestCandidateCompatibility: IngestionCompatibilityClassification?
    let latestCandidateEligibleForActivation: Bool?
    let latestActivationEvent: SnapshotActivationHistoryEvent?
    let latestPromoteOutcome: ProjectedActivationCommandOutcome
    let rollbackAvailable: Bool
    let hasActivationHistory: Bool
    let projectedAt: String
}

protocol SnapshotActivationStateProjecting {
    func project(for source: FlowDatasetSource) async -> ProjectedActivationState
}

struct DefaultSnapshotActivationStateProjector: SnapshotActivationStateProjecting {
    private let activationPolicy: SnapshotActivationPolicying
    private let historyStore: SnapshotActivationHistoryStoring
    private let versionStore: DatasetVersionStoring
    private let nowProvider: () -> String

    init(
        activationPolicy: SnapshotActivationPolicying,
        historyStore: SnapshotActivationHistoryStoring,
        versionStore: DatasetVersionStoring,
        nowProvider: @escaping () -> String = { ISO8601DateFormatter().string(from: Date()) }
    ) {
        self.activationPolicy = activationPolicy
        self.historyStore = historyStore
        self.versionStore = versionStore
        self.nowProvider = nowProvider
    }

    func project(for source: FlowDatasetSource) async -> ProjectedActivationState {
        let currentState = await activationPolicy.currentState(for: source)
        let versions = await versionStore.versions(for: source)
        let latestCandidate = versions.first
        let latestEvent = await historyStore.latestEvent(for: source)
        let hasHistory = latestEvent != nil

        let activationDecision = await activationPolicy.evaluateActivation(
            source: source,
            requestedSnapshotID: latestCandidate?.snapshotID
        )
        let latestCandidateEligible: Bool?
        switch activationDecision.status {
        case .activatable:
            latestCandidateEligible = true
        case .storedButNotActivatable:
            latestCandidateEligible = false
        case .snapshotNotFound, .noCandidate:
            latestCandidateEligible = nil
        }

        let rollbackDecision = await activationPolicy.evaluateRollback(source: source)
        let rollbackAvailable = rollbackDecision.status == .rollbackAvailable

        let promoteOutcome = await latestPromoteOutcome(for: source)
        let status = deriveStatus(
            activeSnapshotID: currentState.activeSnapshotID,
            hasHistory: hasHistory,
            promoteOutcome: promoteOutcome,
            activationDecision: activationDecision,
            rollbackAvailable: rollbackAvailable
        )

        return ProjectedActivationState(
            source: source,
            status: status,
            activeSnapshotID: currentState.activeSnapshotID,
            lastKnownGoodSnapshotID: currentState.lastKnownGoodSnapshotID,
            latestCandidateSnapshotID: latestCandidate?.snapshotID,
            latestCandidateDatasetVersion: latestCandidate?.datasetVersion,
            latestCandidateCompatibility: latestCandidate?.compatibilityClassification,
            latestCandidateEligibleForActivation: latestCandidateEligible,
            latestActivationEvent: latestEvent,
            latestPromoteOutcome: promoteOutcome,
            rollbackAvailable: rollbackAvailable,
            hasActivationHistory: hasHistory,
            projectedAt: nowProvider()
        )
    }

    private func latestPromoteOutcome(for source: FlowDatasetSource) async -> ProjectedActivationCommandOutcome {
        let events = await historyStore.events(for: source)
        guard let event = events.first(where: isPromoteEvent(_:)) else {
            return .none
        }

        switch event.type {
        case .promoteRequested:
            return .requested
        case .promoteSucceeded:
            return .succeeded
        case .promoteBlocked:
            return .blocked
        case .promoteFailed:
            return .failed
        default:
            return .none
        }
    }

    private func isPromoteEvent(_ event: SnapshotActivationHistoryEvent) -> Bool {
        switch event.type {
        case .promoteRequested, .promoteSucceeded, .promoteBlocked, .promoteFailed:
            return true
        default:
            return false
        }
    }

    private func deriveStatus(
        activeSnapshotID: String?,
        hasHistory: Bool,
        promoteOutcome: ProjectedActivationCommandOutcome,
        activationDecision: SnapshotActivationDecision,
        rollbackAvailable: Bool
    ) -> ProjectedActivationStatus {
        if promoteOutcome == .failed || promoteOutcome == .blocked {
            return .attentionRequired
        }

        if activeSnapshotID != nil {
            return rollbackAvailable ? .activeRollbackReady : .active
        }

        if activationDecision.status == .activatable {
            return .inactiveCandidateReady
        }

        return hasHistory ? .inactive : .noHistory
    }
}
