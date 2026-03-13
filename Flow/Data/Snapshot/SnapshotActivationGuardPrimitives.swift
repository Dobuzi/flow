import Foundation

enum SnapshotActivationGuardStatus: String, Codable, Hashable {
    case allowed
    case blocked
    case noOp
    case requiresConfirmation
}

enum SnapshotActivationGuardReason: String, Codable, Hashable {
    case staticSource
    case commandInvalid
    case targetSnapshotNotFound
    case targetSnapshotNotEligible
    case targetSnapshotIncompatible
    case activeSnapshotWillChange
    case fallbackTransition
    case noActiveSnapshot
    case noRollbackTarget
    case expectedActiveSnapshotMismatch
    case alreadyActive
    case alreadyInactive
    case policyRejected
}

struct SnapshotActivationGuardInput: Hashable {
    let command: SnapshotActivationCommand
    let isLiveCapable: Bool
    let currentState: SnapshotActivationState?
    let candidateSnapshot: StoredSnapshotVersion?
    let rollbackTarget: StoredSnapshotVersion?
    let activationDecision: SnapshotActivationDecision?
    let rollbackDecision: SnapshotRollbackDecision?

    init(
        command: SnapshotActivationCommand,
        isLiveCapable: Bool,
        currentState: SnapshotActivationState? = nil,
        candidateSnapshot: StoredSnapshotVersion? = nil,
        rollbackTarget: StoredSnapshotVersion? = nil,
        activationDecision: SnapshotActivationDecision? = nil,
        rollbackDecision: SnapshotRollbackDecision? = nil
    ) {
        self.command = command
        self.isLiveCapable = isLiveCapable
        self.currentState = currentState
        self.candidateSnapshot = candidateSnapshot
        self.rollbackTarget = rollbackTarget
        self.activationDecision = activationDecision
        self.rollbackDecision = rollbackDecision
    }

    func baselineDecision() -> SnapshotActivationGuardDecision {
        if !isLiveCapable {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .blocked,
                reasons: [.staticSource]
            )
        }

        let validation = DefaultSnapshotActivationCommandValidator().validate(
            command,
            context: SnapshotActivationCommandValidationContext(
                isLiveCapable: isLiveCapable,
                currentState: currentState,
                candidateSnapshot: candidateSnapshot,
                rollbackTarget: rollbackTarget
            )
        )
        if !validation.isValid {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .blocked,
                reasons: [.commandInvalid],
                details: validation.issues.map(\.code.rawValue)
            )
        }

        switch command {
        case .promote(let promote):
            return promoteDecision(promote)
        case .demote(let demote):
            return demoteDecision(demote)
        case .rollback:
            return rollbackGuardDecision()
        }
    }

    private func promoteDecision(_ command: PromoteSnapshotCommand) -> SnapshotActivationGuardDecision {
        let currentActive = currentState?.activeSnapshotID
        if let snapshotID = command.snapshotID,
           currentActive == snapshotID {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .noOp,
                reasons: [.alreadyActive]
            )
        }

        if let decision = activationDecision {
            switch decision.status {
            case .activatable:
                return confirmationAwarePromotionDecision(targetSnapshotID: decision.candidate?.snapshotID)
            case .snapshotNotFound:
                return SnapshotActivationGuardDecision(
                    input: self,
                    status: .blocked,
                    reasons: [.targetSnapshotNotFound],
                    details: decision.reasons
                )
            case .storedButNotActivatable:
                let mapped = SnapshotActivationGuardReason.from(blockReason: .from(activationDecision: decision))
                return SnapshotActivationGuardDecision(
                    input: self,
                    status: .blocked,
                    reasons: [mapped],
                    details: decision.reasons
                )
            case .noCandidate:
                return SnapshotActivationGuardDecision(
                    input: self,
                    status: .blocked,
                    reasons: [.policyRejected],
                    details: decision.reasons
                )
            }
        }

        if let candidateSnapshot {
            if candidateSnapshot.snapshotID == currentActive {
                return SnapshotActivationGuardDecision(
                    input: self,
                    status: .noOp,
                    reasons: [.alreadyActive]
                )
            }

            if candidateSnapshot.compatibilityClassification != .compatible {
                return SnapshotActivationGuardDecision(
                    input: self,
                    status: .blocked,
                    reasons: [.targetSnapshotIncompatible]
                )
            }

            if candidateSnapshot.activationEligibility.state != .eligible {
                return SnapshotActivationGuardDecision(
                    input: self,
                    status: .blocked,
                    reasons: [.targetSnapshotNotEligible]
                )
            }

            return confirmationAwarePromotionDecision(targetSnapshotID: candidateSnapshot.snapshotID)
        }

        return SnapshotActivationGuardDecision(
            input: self,
            status: .blocked,
            reasons: [.policyRejected]
        )
    }

    private func demoteDecision(_ command: DemoteSnapshotCommand) -> SnapshotActivationGuardDecision {
        guard let active = currentState?.activeSnapshotID else {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .noOp,
                reasons: [.alreadyInactive]
            )
        }

        if let expected = command.expectedActiveSnapshotID,
           expected != active {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .blocked,
                reasons: [.expectedActiveSnapshotMismatch],
                details: ["expected:\(expected)", "actual:\(active)"]
            )
        }

        if let decision = rollbackDecision {
            switch decision.status {
            case .rollbackAvailable:
                if decision.target?.snapshotID == active {
                    return SnapshotActivationGuardDecision(
                        input: self,
                        status: .noOp,
                        reasons: [.alreadyActive]
                    )
                }
                return SnapshotActivationGuardDecision(
                    input: self,
                    status: .requiresConfirmation,
                    reasons: [.fallbackTransition],
                    details: ["safe_fallback_available"] + decision.reasons
                )
            case .noSafeRollback:
                return SnapshotActivationGuardDecision(
                    input: self,
                    status: .blocked,
                    reasons: [mappedRollbackGuardReason(from: decision.reasons)],
                    details: decision.reasons
                )
            }
        }

        guard let rollbackTarget else {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .blocked,
                reasons: [.noRollbackTarget]
            )
        }

        if rollbackTarget.snapshotID == active {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .noOp,
                reasons: [.alreadyActive]
            )
        }

        return SnapshotActivationGuardDecision(
            input: self,
            status: .requiresConfirmation,
            reasons: [.fallbackTransition],
            details: ["safe_fallback_available"]
        )
    }

    private func rollbackGuardDecision() -> SnapshotActivationGuardDecision {
        if let decision = rollbackDecision {
            switch decision.status {
            case .rollbackAvailable:
                if decision.target?.snapshotID == currentState?.activeSnapshotID {
                    return SnapshotActivationGuardDecision(
                        input: self,
                        status: .noOp,
                        reasons: [.alreadyActive]
                    )
                }
                return SnapshotActivationGuardDecision(
                    input: self,
                    status: .requiresConfirmation,
                    reasons: [.fallbackTransition],
                    details: ["rollback_changes_active_snapshot"] + decision.reasons
                )
            case .noSafeRollback:
                return SnapshotActivationGuardDecision(
                    input: self,
                    status: .blocked,
                    reasons: [mappedRollbackGuardReason(from: decision.reasons)],
                    details: decision.reasons
                )
            }
        }

        guard let target = rollbackTarget else {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .blocked,
                reasons: [.noRollbackTarget]
            )
        }

        if target.snapshotID == currentState?.activeSnapshotID {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .noOp,
                reasons: [.alreadyActive]
            )
        }

        return SnapshotActivationGuardDecision(
            input: self,
            status: .requiresConfirmation,
            reasons: [.fallbackTransition],
            details: ["rollback_changes_active_snapshot"]
        )
    }

    private func confirmationAwarePromotionDecision(targetSnapshotID: String?) -> SnapshotActivationGuardDecision {
        guard let currentActive = currentState?.activeSnapshotID else {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .allowed,
                reasons: []
            )
        }

        guard targetSnapshotID != currentActive else {
            return SnapshotActivationGuardDecision(
                input: self,
                status: .noOp,
                reasons: [.alreadyActive]
            )
        }

        return SnapshotActivationGuardDecision(
            input: self,
            status: .requiresConfirmation,
            reasons: [.activeSnapshotWillChange],
            details: ["active_snapshot_change"]
        )
    }

    private func mappedRollbackGuardReason(from reasons: [String]) -> SnapshotActivationGuardReason {
        if reasons.contains("last_known_good_not_found") {
            return .targetSnapshotNotFound
        }
        if reasons.contains(where: { $0 == "last_known_good_not_activatable" || $0.hasPrefix("compatibility_") || $0.contains("schema_version_unsupported") }) {
            return .targetSnapshotIncompatible
        }
        if reasons.contains(where: { $0.hasPrefix("activation_") || $0 == "not_ingestion_candidate" }) {
            return .targetSnapshotNotEligible
        }
        return .noRollbackTarget
    }
}

struct SnapshotActivationGuardDecision: Hashable {
    let command: SnapshotActivationCommand
    let status: SnapshotActivationGuardStatus
    let reasons: [SnapshotActivationGuardReason]
    let details: [String]
    let candidateSnapshotID: String?
    let activeSnapshotID: String?
    let rollbackTargetSnapshotID: String?

    init(
        input: SnapshotActivationGuardInput,
        status: SnapshotActivationGuardStatus,
        reasons: [SnapshotActivationGuardReason],
        details: [String] = []
    ) {
        self.command = input.command
        self.status = status
        self.reasons = reasons
        self.details = details
        self.candidateSnapshotID = input.activationDecision?.candidate?.snapshotID ?? input.candidateSnapshot?.snapshotID
        self.activeSnapshotID = input.currentState?.activeSnapshotID
        self.rollbackTargetSnapshotID = input.rollbackDecision?.target?.snapshotID ?? input.rollbackTarget?.snapshotID
    }
}

extension SnapshotActivationGuardReason {
    static func from(blockReason: SnapshotActivationBlockReason) -> SnapshotActivationGuardReason {
        switch blockReason {
        case .commandInvalid:
            return .commandInvalid
        case .snapshotNotFound:
            return .targetSnapshotNotFound
        case .snapshotNotEligible:
            return .targetSnapshotNotEligible
        case .snapshotIncompatible:
            return .targetSnapshotIncompatible
        case .noActiveSnapshot:
            return .noActiveSnapshot
        case .noRollbackTarget:
            return .noRollbackTarget
        case .sourceMismatch:
            return .expectedActiveSnapshotMismatch
        case .alreadyActive:
            return .alreadyActive
        case .alreadyInactive:
            return .alreadyInactive
        case .policyRejected:
            return .policyRejected
        }
    }
}
