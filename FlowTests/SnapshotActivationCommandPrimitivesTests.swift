import Testing
@testable import Flow

struct SnapshotActivationCommandPrimitivesTests {
    @Test
    func promoteCommandRequiresTargetReference() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: nil,
                datasetVersion: nil,
                context: .init(trigger: .operatorManual)
            )
        )

        let issues = command.validationIssues()
        #expect(issues.contains(.missingTargetReference))
    }

    @Test
    func promoteCommandAcceptsSnapshotOrDatasetVersionTarget() {
        let bySnapshot = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.03",
                datasetVersion: nil,
                context: .init(trigger: .operatorManual)
            )
        )
        #expect(bySnapshot.validationIssues().isEmpty)

        let byVersion = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: nil,
                datasetVersion: "2026.03",
                context: .init(trigger: .operatorManual)
            )
        )
        #expect(byVersion.validationIssues().isEmpty)
    }

    @Test
    func commandExposesSharedSourceActionAndContext() {
        let context = SnapshotActivationCommandContext(
            commandID: "cmd-001",
            requestedAt: "2026-03-10T00:00:00Z",
            trigger: .operatorConfirmed,
            requestedBy: "operator-1",
            note: "promotion request"
        )

        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .koreaNational,
                expectedActiveSnapshotID: "national-2026.03",
                context: context
            )
        )

        #expect(command.source == .koreaNational)
        #expect(command.action == .rollback)
        #expect(command.context.commandID == "cmd-001")
        #expect(command.context.requestedBy == "operator-1")
    }

    @Test
    func executionResultFactoriesPreserveTypedSemantics() {
        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                preserveLastKnownGood: true,
                context: .init(trigger: .operatorManual)
            )
        )
        let previousState = SnapshotActivationState(
            source: .seoulCapitalSnapshot,
            activeSnapshotID: "seoul-2026.03",
            lastKnownGoodSnapshotID: "seoul-2026.02",
            updatedAt: "2026-03-10T00:00:00Z"
        )
        let nextState = SnapshotActivationState(
            source: .seoulCapitalSnapshot,
            activeSnapshotID: nil,
            lastKnownGoodSnapshotID: "seoul-2026.02",
            updatedAt: "2026-03-10T00:01:00Z"
        )

        let success = SnapshotActivationExecutionResult.succeeded(
            command: command,
            previousState: previousState,
            resultingState: nextState
        )
        #expect(success.status == .succeeded)
        #expect(success.resultingState?.activeSnapshotID == nil)
        #expect(success.blockReason == nil)
        #expect(success.failureReason == nil)

        let blocked = SnapshotActivationExecutionResult.blocked(
            command: command,
            reason: .alreadyInactive,
            previousState: previousState
        )
        #expect(blocked.status == .blocked)
        #expect(blocked.blockReason == .alreadyInactive)
        #expect(blocked.failureReason == nil)

        let failed = SnapshotActivationExecutionResult.failed(
            command: command,
            reason: .stateMutationFailed,
            previousState: previousState
        )
        #expect(failed.status == .failed)
        #expect(failed.failureReason == .stateMutationFailed)
        #expect(failed.blockReason == nil)

        let noOp = SnapshotActivationExecutionResult.noOp(
            command: command,
            reason: .alreadyInactive,
            currentState: previousState
        )
        #expect(noOp.status == .noOp)
        #expect(noOp.blockReason == .alreadyInactive)
        #expect(noOp.resultingState == previousState)
    }

    @Test
    func blockReasonMappingAlignsWithExistingActivationPolicyDecisions() {
        let notFoundDecision = SnapshotActivationDecision(
            source: .seoulCapitalSnapshot,
            requestedSnapshotID: "seoul-unknown",
            status: .snapshotNotFound,
            candidate: nil,
            reasons: ["snapshot_not_found"]
        )
        #expect(SnapshotActivationBlockReason.from(activationDecision: notFoundDecision) == .snapshotNotFound)

        let incompatibleDecision = SnapshotActivationDecision(
            source: .seoulCapitalSnapshot,
            requestedSnapshotID: "seoul-2026.04",
            status: .storedButNotActivatable,
            candidate: nil,
            reasons: ["compatibility_incompatible"]
        )
        #expect(SnapshotActivationBlockReason.from(activationDecision: incompatibleDecision) == .snapshotIncompatible)

        let notEligibleDecision = SnapshotActivationDecision(
            source: .seoulCapitalSnapshot,
            requestedSnapshotID: "seoul-2026.04",
            status: .storedButNotActivatable,
            candidate: nil,
            reasons: ["activation_ineligible"]
        )
        #expect(SnapshotActivationBlockReason.from(activationDecision: notEligibleDecision) == .snapshotNotEligible)

        let noRollbackDecision = SnapshotRollbackDecision(
            source: .seoulCapitalSnapshot,
            status: .noSafeRollback,
            target: nil,
            reasons: ["last_known_good_missing"]
        )
        #expect(SnapshotActivationBlockReason.from(rollbackDecision: noRollbackDecision) == .noRollbackTarget)
    }
}
