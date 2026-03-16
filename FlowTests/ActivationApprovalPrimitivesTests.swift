import Testing
@testable import Flow

struct ActivationApprovalPrimitivesTests {
    @Test
    func proposedApprovedRejectedAndExecutedStatesMapCorrectly() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                datasetVersion: nil,
                context: .init(
                    commandID: "cmd-approval-001",
                    requestedAt: "2026-03-16T01:00:00Z",
                    trigger: .operatorManual,
                    requestedBy: "operator-a",
                    note: "promote candidate"
                )
            )
        )

        let proposed = command.proposedRollout(
            proposalID: "proposal-001",
            state: .proposed,
            rolloutMode: .staged,
            executionReadinessSummary: "candidate_ready"
        )
        #expect(proposed.approvalState == .proposed)
        #expect(proposed.rolloutMode == .staged)
        #expect(proposed.proposal.targetSnapshotID == "seoul-2026.04")

        let awaiting = proposed.applying(.submitForApproval, by: "operator-a", at: "2026-03-16T01:01:00Z")
        #expect(awaiting.approvalState == .awaitingApproval)

        let approved = awaiting.applying(.approve, by: "lead-1", at: "2026-03-16T01:02:00Z")
        #expect(approved.approvalState == .approved)
        #expect(approved.decidedBy == "lead-1")

        let executed = approved.markingExecuted(at: "2026-03-16T01:03:00Z")
        #expect(executed.approvalState == .executed)
        #expect(executed.decidedAt == "2026-03-16T01:03:00Z")

        let rejected = proposed.applying(.reject, by: "lead-2", at: "2026-03-16T01:04:00Z", reason: "candidate_incompatible")
        #expect(rejected.approvalState == .rejected)
        #expect(rejected.decisionReason == "candidate_incompatible")
    }

    @Test
    func stagedRolloutScaffoldingPreservesSourceScopingAndCommandCompatibility() {
        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .koreaNational,
                expectedActiveSnapshotID: "national-2026.03",
                context: .init(
                    commandID: "cmd-rollout-001",
                    requestedAt: "2026-03-16T02:00:00Z",
                    trigger: .operatorConfirmed,
                    requestedBy: "operator-b"
                )
            )
        )

        let scaffold = ActivationRolloutCommand.directExecutionCompatible(
            command: command,
            rolloutMode: .rollbackPrepared,
            executionReadinessSummary: "rollback_ready"
        )

        #expect(scaffold.source == .koreaNational)
        #expect(scaffold.action == .rollback)
        #expect(scaffold.command == command)
        #expect(scaffold.approvalState == .approved)
        #expect(scaffold.rolloutMode == .rollbackPrepared)
        #expect(scaffold.proposal.executionReadinessSummary == "rollback_ready")
        #expect(scaffold.proposal.targetSnapshotID == "national-2026.03")
    }

    @Test
    func executionBlockedAndFailedStatesRemainTruthful() {
        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                preserveLastKnownGood: true,
                context: .init(
                    commandID: "cmd-rollout-002",
                    requestedAt: "2026-03-16T03:00:00Z",
                    trigger: .operatorManual,
                    requestedBy: "operator-c"
                )
            )
        )

        let approved = command.proposedRollout(state: .approved, rolloutMode: .dryRun)
        let blocked = approved.markingExecutionBlocked(reason: "requires_confirmation", at: "2026-03-16T03:01:00Z")
        #expect(blocked.approvalState == .executionBlocked)
        #expect(blocked.decisionReason == "requires_confirmation")
        #expect(blocked.source == .seoulCapitalSnapshot)

        let failed = approved.markingExecutionFailed(reason: "state_mutation_failed", at: "2026-03-16T03:02:00Z")
        #expect(failed.approvalState == .executionFailed)
        #expect(failed.decisionReason == "state_mutation_failed")
        #expect(failed.command == command)
    }
}
