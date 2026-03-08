import Foundation

struct SnapshotActivationState: Hashable {
    let source: FlowDatasetSource
    let activeSnapshotID: String?
    let lastKnownGoodSnapshotID: String?
    let updatedAt: String
}

struct SnapshotActivationDecision: Hashable {
    enum Status: String, Hashable {
        case activatable
        case storedButNotActivatable
        case snapshotNotFound
        case noCandidate
    }

    let source: FlowDatasetSource
    let requestedSnapshotID: String?
    let status: Status
    let candidate: StoredSnapshotVersion?
    let reasons: [String]
}

struct SnapshotRollbackDecision: Hashable {
    enum Status: String, Hashable {
        case rollbackAvailable
        case noSafeRollback
    }

    let source: FlowDatasetSource
    let status: Status
    let target: StoredSnapshotVersion?
    let reasons: [String]
}

enum SnapshotActivationError: Error, Equatable {
    case noCandidate(FlowDatasetSource)
    case snapshotNotFound(source: FlowDatasetSource, snapshotID: String)
    case snapshotNotActivatable(source: FlowDatasetSource, snapshotID: String, reasons: [String])
    case noRollbackTarget(FlowDatasetSource)
}

protocol SnapshotActivationPolicying {
    func currentState(for source: FlowDatasetSource) async -> SnapshotActivationState
    func evaluateActivation(source: FlowDatasetSource, requestedSnapshotID: String?) async -> SnapshotActivationDecision
    func activate(source: FlowDatasetSource, requestedSnapshotID: String?) async throws -> SnapshotActivationState
    func evaluateRollback(source: FlowDatasetSource) async -> SnapshotRollbackDecision
    func rollback(source: FlowDatasetSource) async throws -> SnapshotActivationState
}

actor DefaultSnapshotActivationPolicy: SnapshotActivationPolicying {
    private let versionStore: DatasetVersionStoring
    private var stateBySource: [FlowDatasetSource: SnapshotActivationState] = [:]
    private let nowProvider: () -> String

    init(
        versionStore: DatasetVersionStoring,
        nowProvider: @escaping () -> String = { ISO8601DateFormatter().string(from: Date()) }
    ) {
        self.versionStore = versionStore
        self.nowProvider = nowProvider
    }

    func currentState(for source: FlowDatasetSource) async -> SnapshotActivationState {
        if let state = stateBySource[source] {
            return state
        }
        return SnapshotActivationState(
            source: source,
            activeSnapshotID: nil,
            lastKnownGoodSnapshotID: nil,
            updatedAt: nowProvider()
        )
    }

    func evaluateActivation(source: FlowDatasetSource, requestedSnapshotID: String?) async -> SnapshotActivationDecision {
        if let requestedSnapshotID {
            guard let candidate = await versionStore.snapshot(snapshotID: requestedSnapshotID),
                  candidate.source == source else {
                return SnapshotActivationDecision(
                    source: source,
                    requestedSnapshotID: requestedSnapshotID,
                    status: .snapshotNotFound,
                    candidate: nil,
                    reasons: ["snapshot_not_found"]
                )
            }

            if isActivatable(candidate) {
                return SnapshotActivationDecision(
                    source: source,
                    requestedSnapshotID: requestedSnapshotID,
                    status: .activatable,
                    candidate: candidate,
                    reasons: []
                )
            }

            return SnapshotActivationDecision(
                source: source,
                requestedSnapshotID: requestedSnapshotID,
                status: .storedButNotActivatable,
                candidate: candidate,
                reasons: nonActivatableReasons(candidate)
            )
        }

        let candidates = await versionStore.versions(for: source)
        guard !candidates.isEmpty else {
            return SnapshotActivationDecision(
                source: source,
                requestedSnapshotID: nil,
                status: .noCandidate,
                candidate: nil,
                reasons: ["no_stored_snapshot"]
            )
        }

        if let activatable = candidates.first(where: isActivatable(_:)) {
            return SnapshotActivationDecision(
                source: source,
                requestedSnapshotID: nil,
                status: .activatable,
                candidate: activatable,
                reasons: []
            )
        }

        return SnapshotActivationDecision(
            source: source,
            requestedSnapshotID: nil,
            status: .storedButNotActivatable,
            candidate: candidates.first,
            reasons: ["no_activatable_candidate"]
        )
    }

    func activate(source: FlowDatasetSource, requestedSnapshotID: String?) async throws -> SnapshotActivationState {
        let decision = await evaluateActivation(source: source, requestedSnapshotID: requestedSnapshotID)
        guard decision.status == .activatable, let candidate = decision.candidate else {
            switch decision.status {
            case .noCandidate:
                throw SnapshotActivationError.noCandidate(source)
            case .snapshotNotFound:
                throw SnapshotActivationError.snapshotNotFound(
                    source: source,
                    snapshotID: requestedSnapshotID ?? "unknown"
                )
            case .storedButNotActivatable:
                throw SnapshotActivationError.snapshotNotActivatable(
                    source: source,
                    snapshotID: decision.candidate?.snapshotID ?? requestedSnapshotID ?? "unknown",
                    reasons: decision.reasons
                )
            case .activatable:
                throw SnapshotActivationError.noCandidate(source)
            }
        }

        let previous = await currentState(for: source)
        let lastKnownGood: String?
        if previous.activeSnapshotID == candidate.snapshotID {
            lastKnownGood = previous.lastKnownGoodSnapshotID
        } else {
            lastKnownGood = previous.activeSnapshotID ?? previous.lastKnownGoodSnapshotID
        }

        let next = SnapshotActivationState(
            source: source,
            activeSnapshotID: candidate.snapshotID,
            lastKnownGoodSnapshotID: lastKnownGood,
            updatedAt: nowProvider()
        )
        stateBySource[source] = next
        return next
    }

    func evaluateRollback(source: FlowDatasetSource) async -> SnapshotRollbackDecision {
        let current = await currentState(for: source)
        guard let rollbackID = current.lastKnownGoodSnapshotID else {
            return SnapshotRollbackDecision(
                source: source,
                status: .noSafeRollback,
                target: nil,
                reasons: ["last_known_good_missing"]
            )
        }
        guard let target = await versionStore.snapshot(snapshotID: rollbackID) else {
            return SnapshotRollbackDecision(
                source: source,
                status: .noSafeRollback,
                target: nil,
                reasons: ["last_known_good_not_found"]
            )
        }
        guard isActivatable(target) else {
            return SnapshotRollbackDecision(
                source: source,
                status: .noSafeRollback,
                target: nil,
                reasons: ["last_known_good_not_activatable"]
            )
        }
        return SnapshotRollbackDecision(
            source: source,
            status: .rollbackAvailable,
            target: target,
            reasons: []
        )
    }

    func rollback(source: FlowDatasetSource) async throws -> SnapshotActivationState {
        let decision = await evaluateRollback(source: source)
        guard decision.status == .rollbackAvailable, let target = decision.target else {
            throw SnapshotActivationError.noRollbackTarget(source)
        }

        let previous = await currentState(for: source)
        let next = SnapshotActivationState(
            source: source,
            activeSnapshotID: target.snapshotID,
            lastKnownGoodSnapshotID: previous.activeSnapshotID,
            updatedAt: nowProvider()
        )
        stateBySource[source] = next
        return next
    }

    private func isActivatable(_ candidate: StoredSnapshotVersion) -> Bool {
        candidate.isIngestionCandidate
            && candidate.compatibilityClassification == .compatible
            && candidate.activationEligibility.state == .eligible
    }

    private func nonActivatableReasons(_ candidate: StoredSnapshotVersion) -> [String] {
        var reasons: [String] = []
        if !candidate.isIngestionCandidate {
            reasons.append("not_ingestion_candidate")
        }
        if candidate.compatibilityClassification != .compatible {
            reasons.append("compatibility_\(candidate.compatibilityClassification.rawValue)")
        }
        if candidate.activationEligibility.state != .eligible {
            reasons.append("activation_\(candidate.activationEligibility.state.rawValue)")
        }
        return reasons + candidate.compatibilityReasons
    }
}
