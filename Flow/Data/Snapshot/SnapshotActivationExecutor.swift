import Foundation

protocol SnapshotActivationExecuting {
    func execute(_ command: SnapshotActivationCommand) async -> SnapshotActivationExecutionResult
}

struct SnapshotActivationExecutionContext: Hashable {
    let source: FlowDatasetSource
    let isLiveCapable: Bool
    let currentState: SnapshotActivationState
    let candidateSnapshot: StoredSnapshotVersion?
    let rollbackTarget: StoredSnapshotVersion?
    let activationDecision: SnapshotActivationDecision?
    let rollbackDecision: SnapshotRollbackDecision?
}

struct DefaultSnapshotActivationExecutor: SnapshotActivationExecuting {
    private let validator: SnapshotActivationCommandValidating
    private let activationPolicy: SnapshotActivationPolicying
    private let versionStore: DatasetVersionStoring
    private let historyStore: SnapshotActivationHistoryStoring

    init(
        validator: SnapshotActivationCommandValidating = DefaultSnapshotActivationCommandValidator(),
        activationPolicy: SnapshotActivationPolicying,
        versionStore: DatasetVersionStoring,
        historyStore: SnapshotActivationHistoryStoring
    ) {
        self.validator = validator
        self.activationPolicy = activationPolicy
        self.versionStore = versionStore
        self.historyStore = historyStore
    }

    func execute(_ command: SnapshotActivationCommand) async -> SnapshotActivationExecutionResult {
        await historyStore.append(.requested(command: command))

        let context = await buildContext(for: command)
        let validation = validator.validate(
            command,
            context: SnapshotActivationCommandValidationContext(
                isLiveCapable: context.isLiveCapable,
                currentState: context.currentState,
                candidateSnapshot: context.candidateSnapshot,
                rollbackTarget: context.rollbackTarget
            )
        )

        if !validation.isValid {
            let result = SnapshotActivationExecutionResult.failed(
                command: command,
                reason: .policyEvaluationFailed,
                previousState: context.currentState,
                details: validation.issues.map(\.code.rawValue)
            )
            await historyStore.append(
                .fromExecutionResult(result, validation: validation)
            )
            return result
        }

        let guardDecision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: context.isLiveCapable,
            currentState: context.currentState,
            candidateSnapshot: context.candidateSnapshot,
            rollbackTarget: context.rollbackTarget,
            activationDecision: context.activationDecision,
            rollbackDecision: context.rollbackDecision
        ).baselineDecision()

        switch guardDecision.status {
        case .blocked:
            let result = SnapshotActivationExecutionResult.blocked(
                command: command,
                reason: mappedBlockReason(from: guardDecision.reasons.first),
                previousState: context.currentState,
                details: guardDecision.details
            )
            await historyStore.append(
                .fromExecutionResult(result, validation: validation, guardDecision: guardDecision)
            )
            return result

        case .noOp:
            let result = SnapshotActivationExecutionResult.noOp(
                command: command,
                reason: mappedBlockReason(from: guardDecision.reasons.first),
                currentState: context.currentState,
                details: guardDecision.details
            )
            await historyStore.append(
                .fromExecutionResult(result, validation: validation, guardDecision: guardDecision)
            )
            return result

        case .requiresConfirmation:
            guard shouldAutoConfirm(command.context.trigger) else {
                let result = SnapshotActivationExecutionResult.blocked(
                    command: command,
                    reason: .policyRejected,
                    previousState: context.currentState,
                    details: ["requires_confirmation"] + guardDecision.details
                )
                await historyStore.append(
                    .fromExecutionResult(result, validation: validation, guardDecision: guardDecision)
                )
                return result
            }

            let result = await performExecution(command: command, context: context)
            await historyStore.append(
                .fromExecutionResult(result, validation: validation, guardDecision: guardDecision)
            )
            return result

        case .allowed:
            let result = await performExecution(command: command, context: context)
            await historyStore.append(
                .fromExecutionResult(result, validation: validation, guardDecision: guardDecision)
            )
            return result
        }
    }

    private func performExecution(
        command: SnapshotActivationCommand,
        context: SnapshotActivationExecutionContext
    ) async -> SnapshotActivationExecutionResult {
        switch command {
        case .promote(let promote):
            let requestedSnapshotID = resolvedPromoteSnapshotID(promote, context: context)
            do {
                let resulting = try await activationPolicy.activate(
                    source: promote.source,
                    requestedSnapshotID: requestedSnapshotID
                )
                var details: [String] = []
                if context.currentState.activeSnapshotID != nil,
                   context.currentState.activeSnapshotID != resulting.activeSnapshotID,
                   resulting.lastKnownGoodSnapshotID == context.currentState.activeSnapshotID {
                    details.append("last_known_good_preserved")
                }
                return .succeeded(
                    command: command,
                    previousState: context.currentState,
                    resultingState: resulting,
                    details: details
                )
            } catch let error as SnapshotActivationError {
                return mapActivationError(
                    error,
                    command: command,
                    previousState: context.currentState
                )
            } catch {
                return .failed(
                    command: command,
                    reason: .stateMutationFailed,
                    previousState: context.currentState,
                    details: [String(describing: error)]
                )
            }

        case .demote:
            do {
                let resulting = try await activationPolicy.rollback(source: command.source)
                var details: [String] = ["demoted_to_safe_fallback"]
                if let rollbackTargetID = context.rollbackTarget?.snapshotID,
                   rollbackTargetID == resulting.activeSnapshotID {
                    details.append("safe_fallback_restored")
                }
                if context.currentState.activeSnapshotID != nil,
                   resulting.lastKnownGoodSnapshotID == context.currentState.activeSnapshotID {
                    details.append("last_known_good_preserved")
                }
                return .succeeded(
                    command: command,
                    previousState: context.currentState,
                    resultingState: resulting,
                    details: details
                )
            } catch SnapshotActivationError.noRollbackTarget {
                return .blocked(
                    command: command,
                    reason: .noRollbackTarget,
                    previousState: context.currentState
                )
            } catch {
                return .failed(
                    command: command,
                    reason: .stateMutationFailed,
                    previousState: context.currentState,
                    details: [String(describing: error)]
                )
            }

        case .rollback(let rollback):
            do {
                let resulting = try await activationPolicy.rollback(source: rollback.source)
                var details: [String] = []
                if let rollbackTargetID = context.rollbackTarget?.snapshotID,
                   rollbackTargetID == resulting.activeSnapshotID {
                    details.append("rollback_target_restored")
                }
                return .succeeded(
                    command: command,
                    previousState: context.currentState,
                    resultingState: resulting,
                    details: details
                )
            } catch SnapshotActivationError.noRollbackTarget {
                return .blocked(
                    command: command,
                    reason: .noRollbackTarget,
                    previousState: context.currentState
                )
            } catch {
                return .failed(
                    command: command,
                    reason: .stateMutationFailed,
                    previousState: context.currentState,
                    details: [String(describing: error)]
                )
            }
        }
    }

    private func buildContext(for command: SnapshotActivationCommand) async -> SnapshotActivationExecutionContext {
        let source = command.source
        let currentState = await activationPolicy.currentState(for: source)
        let isLiveCapable = source != .bundledSample

        let candidate = await resolveCandidateSnapshot(for: command)
        let rollbackDecision = await activationPolicy.evaluateRollback(source: source)
        let activationDecision: SnapshotActivationDecision?
        if case .promote(let promote) = command {
            activationDecision = await activationPolicy.evaluateActivation(
                source: source,
                requestedSnapshotID: resolvedPromoteSnapshotID(promote, candidateSnapshot: candidate)
            )
        } else {
            activationDecision = nil
        }

        return SnapshotActivationExecutionContext(
            source: source,
            isLiveCapable: isLiveCapable,
            currentState: currentState,
            candidateSnapshot: candidate,
            rollbackTarget: rollbackDecision.target,
            activationDecision: activationDecision,
            rollbackDecision: rollbackDecision
        )
    }

    private func resolveCandidateSnapshot(for command: SnapshotActivationCommand) async -> StoredSnapshotVersion? {
        switch command {
        case .promote(let promote):
            return await resolvePromoteCandidate(promote)
        case .demote(let demote):
            guard let expectedID = normalizedID(demote.expectedActiveSnapshotID) else { return nil }
            return await versionStore.snapshot(snapshotID: expectedID)
        case .rollback(let rollback):
            guard let expectedID = normalizedID(rollback.expectedActiveSnapshotID) else { return nil }
            return await versionStore.snapshot(snapshotID: expectedID)
        }
    }

    private func resolvePromoteCandidate(_ command: PromoteSnapshotCommand) async -> StoredSnapshotVersion? {
        if let snapshotID = normalizedID(command.snapshotID) {
            return await versionStore.snapshot(snapshotID: snapshotID)
        }

        if let datasetVersion = normalizedDatasetVersion(command.datasetVersion) {
            return await versionStore.snapshot(source: command.source, datasetVersion: datasetVersion)
        }

        return nil
    }

    private func resolvedPromoteSnapshotID(
        _ command: PromoteSnapshotCommand,
        context: SnapshotActivationExecutionContext
    ) -> String? {
        resolvedPromoteSnapshotID(command, candidateSnapshot: context.candidateSnapshot)
    }

    private func resolvedPromoteSnapshotID(
        _ command: PromoteSnapshotCommand,
        candidateSnapshot: StoredSnapshotVersion?
    ) -> String? {
        if let snapshotID = normalizedID(command.snapshotID) {
            return snapshotID
        }
        if let resolved = candidateSnapshot?.snapshotID {
            return resolved
        }
        return nil
    }

    private func normalizedID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedDatasetVersion(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mapActivationError(
        _ error: SnapshotActivationError,
        command: SnapshotActivationCommand,
        previousState: SnapshotActivationState
    ) -> SnapshotActivationExecutionResult {
        switch error {
        case .noCandidate:
            return .blocked(
                command: command,
                reason: .policyRejected,
                previousState: previousState,
                details: ["no_candidate"]
            )
        case .snapshotNotFound(_, let snapshotID):
            return .blocked(
                command: command,
                reason: .snapshotNotFound,
                previousState: previousState,
                details: ["snapshot_not_found", snapshotID]
            )
        case .snapshotNotActivatable(_, _, let reasons):
            let hasCompatibilityReason = reasons.contains(where: { $0.hasPrefix("compatibility_") || $0.contains("schema_version_unsupported") })
            return .blocked(
                command: command,
                reason: hasCompatibilityReason ? .snapshotIncompatible : .snapshotNotEligible,
                previousState: previousState,
                details: reasons
            )
        case .noRollbackTarget:
            return .blocked(
                command: command,
                reason: .noRollbackTarget,
                previousState: previousState
            )
        }
    }

    private func shouldAutoConfirm(_ trigger: SnapshotActivationCommandTrigger) -> Bool {
        switch trigger {
        case .operatorConfirmed, .recoveryRollback:
            return true
        case .operatorManual:
            return false
        }
    }

    private func mappedBlockReason(from guardReason: SnapshotActivationGuardReason?) -> SnapshotActivationBlockReason {
        guard let guardReason else { return .policyRejected }

        switch guardReason {
        case .commandInvalid:
            return .commandInvalid
        case .targetSnapshotNotFound:
            return .snapshotNotFound
        case .targetSnapshotNotEligible:
            return .snapshotNotEligible
        case .targetSnapshotIncompatible:
            return .snapshotIncompatible
        case .noActiveSnapshot:
            return .noActiveSnapshot
        case .noRollbackTarget:
            return .noRollbackTarget
        case .expectedActiveSnapshotMismatch:
            return .sourceMismatch
        case .alreadyActive:
            return .alreadyActive
        case .alreadyInactive:
            return .alreadyInactive
        case .staticSource, .policyRejected:
            return .policyRejected
        }
    }
}
