import Foundation

enum SnapshotActivationEventType: String, Hashable {
    case promoteRequested
    case promoteSucceeded
    case promoteBlocked
    case promoteFailed
    case demoteRequested
    case demoteSucceeded
    case demoteBlocked
    case demoteFailed
    case rollbackRequested
    case rollbackSucceeded
    case rollbackBlocked
    case rollbackFailed
}

enum SnapshotActivationEventTrigger: String, Hashable {
    case operatorManual
    case operatorConfirmed
    case recoveryRollback
    case system
}

enum SnapshotActivationEventStatus: String, Hashable {
    case requested
    case succeeded
    case blocked
    case failed
    case noOp
}

struct SnapshotActivationEventValidationSummary: Hashable {
    let isValid: Bool
    let issueCodes: [SnapshotActivationCommandValidationIssueCode]
}

struct SnapshotActivationEventGuardSummary: Hashable {
    let status: SnapshotActivationGuardStatus
    let reasons: [SnapshotActivationGuardReason]
    let details: [String]
    let candidateSnapshotID: String?
    let activeSnapshotID: String?
    let rollbackTargetSnapshotID: String?
}

struct SnapshotActivationEventExecutionSummary: Hashable {
    let status: SnapshotActivationExecutionStatus
    let blockReason: SnapshotActivationBlockReason?
    let failureReason: SnapshotActivationFailureReason?
    let details: [String]
    let previousActiveSnapshotID: String?
    let resultingActiveSnapshotID: String?
}

struct SnapshotActivationEventResult: Hashable {
    let status: SnapshotActivationEventStatus
    let reasonCode: String?
    let message: String?
}

struct SnapshotActivationEventMetadata: Hashable {
    let source: FlowDatasetSource
    let snapshotID: String?
    let datasetVersion: String?
    let commandID: String
    let commandAction: SnapshotActivationCommand.Action
    let trigger: SnapshotActivationEventTrigger
    let requestedBy: String?
    let note: String?
    let validation: SnapshotActivationEventValidationSummary?
    let guardDecision: SnapshotActivationEventGuardSummary?
    let execution: SnapshotActivationEventExecutionSummary?
}

struct SnapshotActivationHistoryEvent: Hashable {
    let eventID: String
    let type: SnapshotActivationEventType
    let timestamp: String
    let metadata: SnapshotActivationEventMetadata
    let result: SnapshotActivationEventResult

    init(
        eventID: String = UUID().uuidString,
        type: SnapshotActivationEventType,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        metadata: SnapshotActivationEventMetadata,
        result: SnapshotActivationEventResult
    ) {
        self.eventID = eventID
        self.type = type
        self.timestamp = timestamp
        self.metadata = metadata
        self.result = result
    }

    static func requested(
        command: SnapshotActivationCommand,
        eventID: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) -> SnapshotActivationHistoryEvent {
        let type: SnapshotActivationEventType
        switch command.action {
        case .promote:
            type = .promoteRequested
        case .demote:
            type = .demoteRequested
        case .rollback:
            type = .rollbackRequested
        }

        return SnapshotActivationHistoryEvent(
            eventID: eventID,
            type: type,
            timestamp: timestamp,
            metadata: .init(
                source: command.source,
                snapshotID: command.targetSnapshotID,
                datasetVersion: command.targetDatasetVersion,
                commandID: command.context.commandID,
                commandAction: command.action,
                trigger: .from(command.context.trigger),
                requestedBy: command.context.requestedBy,
                note: command.context.note,
                validation: nil,
                guardDecision: nil,
                execution: nil
            ),
            result: .init(status: .requested, reasonCode: nil, message: nil)
        )
    }

    static func fromGuardDecision(
        _ decision: SnapshotActivationGuardDecision,
        validation: SnapshotActivationCommandValidationResult? = nil,
        eventID: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) -> SnapshotActivationHistoryEvent {
        let type = SnapshotActivationEventType.from(action: decision.command.action, guardStatus: decision.status)

        return SnapshotActivationHistoryEvent(
            eventID: eventID,
            type: type,
            timestamp: timestamp,
            metadata: .init(
                source: decision.command.source,
                snapshotID: decision.command.targetSnapshotID,
                datasetVersion: decision.command.targetDatasetVersion,
                commandID: decision.command.context.commandID,
                commandAction: decision.command.action,
                trigger: .from(decision.command.context.trigger),
                requestedBy: decision.command.context.requestedBy,
                note: decision.command.context.note,
                validation: validation.map {
                    .init(isValid: $0.isValid, issueCodes: $0.issues.map(\.code))
                },
                guardDecision: .init(
                    status: decision.status,
                    reasons: decision.reasons,
                    details: decision.details,
                    candidateSnapshotID: decision.candidateSnapshotID,
                    activeSnapshotID: decision.activeSnapshotID,
                    rollbackTargetSnapshotID: decision.rollbackTargetSnapshotID
                ),
                execution: nil
            ),
            result: .init(
                status: SnapshotActivationEventStatus.from(guardStatus: decision.status),
                reasonCode: decision.reasons.first?.rawValue,
                message: decision.details.first
            )
        )
    }

    static func fromExecutionResult(
        _ executionResult: SnapshotActivationExecutionResult,
        validation: SnapshotActivationCommandValidationResult? = nil,
        guardDecision: SnapshotActivationGuardDecision? = nil,
        eventID: String = UUID().uuidString
    ) -> SnapshotActivationHistoryEvent {
        let type = SnapshotActivationEventType.from(action: executionResult.command.action, executionStatus: executionResult.status)

        return SnapshotActivationHistoryEvent(
            eventID: eventID,
            type: type,
            timestamp: executionResult.occurredAt,
            metadata: .init(
                source: executionResult.command.source,
                snapshotID: executionResult.command.targetSnapshotID,
                datasetVersion: executionResult.command.targetDatasetVersion,
                commandID: executionResult.command.context.commandID,
                commandAction: executionResult.command.action,
                trigger: .from(executionResult.command.context.trigger),
                requestedBy: executionResult.command.context.requestedBy,
                note: executionResult.command.context.note,
                validation: validation.map {
                    .init(isValid: $0.isValid, issueCodes: $0.issues.map(\.code))
                },
                guardDecision: guardDecision.map {
                    .init(
                        status: $0.status,
                        reasons: $0.reasons,
                        details: $0.details,
                        candidateSnapshotID: $0.candidateSnapshotID,
                        activeSnapshotID: $0.activeSnapshotID,
                        rollbackTargetSnapshotID: $0.rollbackTargetSnapshotID
                    )
                },
                execution: .init(
                    status: executionResult.status,
                    blockReason: executionResult.blockReason,
                    failureReason: executionResult.failureReason,
                    details: executionResult.details,
                    previousActiveSnapshotID: executionResult.previousState?.activeSnapshotID,
                    resultingActiveSnapshotID: executionResult.resultingState?.activeSnapshotID
                )
            ),
            result: .init(
                status: .from(executionStatus: executionResult.status),
                reasonCode: executionResult.blockReason?.rawValue ?? executionResult.failureReason?.rawValue,
                message: executionResult.details.first
            )
        )
    }
}

private extension SnapshotActivationEventTrigger {
    static func from(_ trigger: SnapshotActivationCommandTrigger) -> SnapshotActivationEventTrigger {
        switch trigger {
        case .operatorManual:
            return .operatorManual
        case .operatorConfirmed:
            return .operatorConfirmed
        case .recoveryRollback:
            return .recoveryRollback
        }
    }
}

private extension SnapshotActivationEventStatus {
    static func from(executionStatus: SnapshotActivationExecutionStatus) -> SnapshotActivationEventStatus {
        switch executionStatus {
        case .succeeded:
            return .succeeded
        case .blocked:
            return .blocked
        case .failed:
            return .failed
        case .noOp:
            return .noOp
        }
    }

    static func from(guardStatus: SnapshotActivationGuardStatus) -> SnapshotActivationEventStatus {
        switch guardStatus {
        case .allowed:
            return .requested
        case .blocked:
            return .blocked
        case .noOp:
            return .noOp
        case .requiresConfirmation:
            return .requested
        }
    }
}

private extension SnapshotActivationEventType {
    static func from(
        action: SnapshotActivationCommand.Action,
        executionStatus: SnapshotActivationExecutionStatus
    ) -> SnapshotActivationEventType {
        switch (action, executionStatus) {
        case (.promote, .succeeded):
            return .promoteSucceeded
        case (.promote, .blocked), (.promote, .noOp):
            return .promoteBlocked
        case (.promote, .failed):
            return .promoteFailed
        case (.demote, .succeeded):
            return .demoteSucceeded
        case (.demote, .blocked), (.demote, .noOp):
            return .demoteBlocked
        case (.demote, .failed):
            return .demoteFailed
        case (.rollback, .succeeded):
            return .rollbackSucceeded
        case (.rollback, .blocked), (.rollback, .noOp):
            return .rollbackBlocked
        case (.rollback, .failed):
            return .rollbackFailed
        }
    }

    static func from(
        action: SnapshotActivationCommand.Action,
        guardStatus: SnapshotActivationGuardStatus
    ) -> SnapshotActivationEventType {
        switch (action, guardStatus) {
        case (.promote, .blocked), (.promote, .noOp):
            return .promoteBlocked
        case (.promote, .allowed), (.promote, .requiresConfirmation):
            return .promoteRequested
        case (.demote, .blocked), (.demote, .noOp):
            return .demoteBlocked
        case (.demote, .allowed), (.demote, .requiresConfirmation):
            return .demoteRequested
        case (.rollback, .blocked), (.rollback, .noOp):
            return .rollbackBlocked
        case (.rollback, .allowed), (.rollback, .requiresConfirmation):
            return .rollbackRequested
        }
    }
}

private extension SnapshotActivationCommand {
    var targetSnapshotID: String? {
        switch self {
        case .promote(let command):
            return command.snapshotID
        case .demote(let command):
            return command.expectedActiveSnapshotID
        case .rollback(let command):
            return command.expectedActiveSnapshotID
        }
    }

    var targetDatasetVersion: String? {
        switch self {
        case .promote(let command):
            return command.datasetVersion
        case .demote, .rollback:
            return nil
        }
    }
}
