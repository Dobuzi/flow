import Testing
@testable import Flow

struct SnapshotActivationHistoryEventTests {
    @Test
    func requestedEventForPromoteCapturesCoreMetadata() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                datasetVersion: "2026.04",
                context: SnapshotActivationCommandContext(
                    commandID: "cmd-promote-001",
                    requestedAt: "2026-03-10T09:00:00Z",
                    trigger: .operatorManual,
                    requestedBy: "operator-a",
                    note: "promote newest compatible snapshot"
                )
            )
        )

        let event = SnapshotActivationHistoryEvent.requested(
            command: command,
            eventID: "evt-001",
            timestamp: "2026-03-10T09:01:00Z"
        )

        #expect(event.type == .promoteRequested)
        #expect(event.result.status == .requested)
        #expect(event.eventID == "evt-001")
        #expect(event.metadata.source == .seoulCapitalSnapshot)
        #expect(event.metadata.snapshotID == "seoul-2026.04")
        #expect(event.metadata.datasetVersion == "2026.04")
        #expect(event.metadata.commandID == "cmd-promote-001")
        #expect(event.metadata.trigger == .operatorManual)
    }

    @Test
    func guardDecisionEventForBlockedRollbackIncludesValidationAndReason() {
        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: nil,
                context: SnapshotActivationCommandContext(
                    commandID: "cmd-rollback-001",
                    requestedAt: "2026-03-10T10:00:00Z",
                    trigger: .recoveryRollback,
                    requestedBy: "operator-b"
                )
            )
        )

        let validation = SnapshotActivationCommandValidationResult(
            command: command,
            issues: []
        )

        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            rollbackDecision: SnapshotRollbackDecision(
                source: .seoulCapitalSnapshot,
                status: .noSafeRollback,
                target: nil,
                reasons: ["last_known_good_missing"]
            )
        ).baselineDecision()

        let event = SnapshotActivationHistoryEvent.fromGuardDecision(
            decision,
            validation: validation,
            eventID: "evt-rollback-blocked",
            timestamp: "2026-03-10T10:00:10Z"
        )

        #expect(event.type == .rollbackBlocked)
        #expect(event.result.status == .blocked)
        #expect(event.result.reasonCode == SnapshotActivationGuardReason.noRollbackTarget.rawValue)
        #expect(event.metadata.validation?.isValid == true)
        #expect(event.metadata.guardDecision?.status == .blocked)
        #expect(event.metadata.guardDecision?.reasons == [.noRollbackTarget])
    }

    @Test
    func executionResultEventForDemoteSuccessCapturesStateTransition() {
        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .koreaNational,
                expectedActiveSnapshotID: "national-2026.03",
                preserveLastKnownGood: true,
                context: SnapshotActivationCommandContext(
                    commandID: "cmd-demote-001",
                    requestedAt: "2026-03-10T11:00:00Z",
                    trigger: .operatorConfirmed,
                    requestedBy: "operator-c"
                )
            )
        )

        let previous = SnapshotActivationState(
            source: .koreaNational,
            activeSnapshotID: "national-2026.03",
            lastKnownGoodSnapshotID: "national-2026.02",
            updatedAt: "2026-03-10T10:59:00Z"
        )

        let resulting = SnapshotActivationState(
            source: .koreaNational,
            activeSnapshotID: nil,
            lastKnownGoodSnapshotID: "national-2026.02",
            updatedAt: "2026-03-10T11:00:10Z"
        )

        let execution = SnapshotActivationExecutionResult.succeeded(
            command: command,
            previousState: previous,
            resultingState: resulting,
            occurredAt: "2026-03-10T11:00:10Z"
        )

        let event = SnapshotActivationHistoryEvent.fromExecutionResult(
            execution,
            eventID: "evt-demote-success"
        )

        #expect(event.type == .demoteSucceeded)
        #expect(event.timestamp == "2026-03-10T11:00:10Z")
        #expect(event.result.status == .succeeded)
        #expect(event.metadata.execution?.status == .succeeded)
        #expect(event.metadata.execution?.previousActiveSnapshotID == "national-2026.03")
        #expect(event.metadata.execution?.resultingActiveSnapshotID == nil)
    }

    @Test
    func executionResultEventForPromoteFailureClassifiesTypeAndReason() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.99",
                context: SnapshotActivationCommandContext(
                    commandID: "cmd-promote-fail-001",
                    requestedAt: "2026-03-10T12:00:00Z",
                    trigger: .operatorConfirmed
                )
            )
        )

        let execution = SnapshotActivationExecutionResult.failed(
            command: command,
            reason: .policyEvaluationFailed,
            previousState: nil,
            details: ["snapshot_not_found"],
            occurredAt: "2026-03-10T12:00:05Z"
        )

        let event = SnapshotActivationHistoryEvent.fromExecutionResult(execution)

        #expect(event.type == .promoteFailed)
        #expect(event.result.status == .failed)
        #expect(event.result.reasonCode == SnapshotActivationFailureReason.policyEvaluationFailed.rawValue)
    }

    @Test
    func commandCompatibilitySupportsPromoteDemoteRollbackActions() {
        let promote = SnapshotActivationHistoryEvent.requested(
            command: .promote(
                PromoteSnapshotCommand(
                    source: .seoulCapitalSnapshot,
                    snapshotID: "seoul-2026.04",
                    context: .init(commandID: "c1", requestedAt: "2026-03-10T00:00:00Z", trigger: .operatorManual)
                )
            )
        )
        let demote = SnapshotActivationHistoryEvent.requested(
            command: .demote(
                DemoteSnapshotCommand(
                    source: .koreaNational,
                    expectedActiveSnapshotID: "national-2026.03",
                    preserveLastKnownGood: true,
                    context: .init(commandID: "c2", requestedAt: "2026-03-10T00:00:00Z", trigger: .operatorConfirmed)
                )
            )
        )
        let rollback = SnapshotActivationHistoryEvent.requested(
            command: .rollback(
                RollbackSnapshotCommand(
                    source: .seoulCapitalSnapshot,
                    expectedActiveSnapshotID: nil,
                    context: .init(commandID: "c3", requestedAt: "2026-03-10T00:00:00Z", trigger: .recoveryRollback)
                )
            )
        )

        #expect(promote.type == .promoteRequested)
        #expect(demote.type == .demoteRequested)
        #expect(rollback.type == .rollbackRequested)
    }
}
